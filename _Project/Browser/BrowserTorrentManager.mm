#import "BrowserTorrentManager.h"
#import "BrowserPreferencesStore.h"

#import <libtorrent/add_torrent_params.hpp>
#import <libtorrent/download_priority.hpp>
#import <libtorrent/hex.hpp>
#import <libtorrent/magnet_uri.hpp>
#import <libtorrent/read_resume_data.hpp>
#import <libtorrent/session.hpp>
#import <libtorrent/settings_pack.hpp>
#import <libtorrent/torrent_handle.hpp>
#import <libtorrent/torrent_info.hpp>
#import <libtorrent/torrent_status.hpp>
#import <libtorrent/write_resume_data.hpp>
#import <libtorrent/alert_types.hpp>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

namespace lt = libtorrent;

@implementation BrowserTorrentSnapshot
@end

@implementation BrowserTorrentFile
@end

static NSString *BrowserTorrentString(std::string const& value) {
    return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static BOOL BrowserTorrentIsPaddingFile(lt::file_storage const& storage, lt::file_index_t index) {
    if (!storage.pad_file_at(index)) return NO;
    NSString *path = BrowserTorrentString(storage.file_path(index));
    BOOL inPaddingDirectory = NO;
    for (NSString *component in path.pathComponents) {
        if ([component.lowercaseString isEqualToString:@".pad"]) { inPaddingDirectory = YES; break; }
    }
    if (!inPaddingDirectory) return NO;
    // Never hide a playable file solely because a padding flag was reported.
    return ![@[@"mp4", @"m4v", @"mov", @"mp3", @"m4a", @"mkv", @"avi"]
        containsObject:path.pathExtension.lowercaseString];
}

static NSError *BrowserTorrentError(NSString *message) {
    return [NSError errorWithDomain:@"BrowserTorrent" code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @"Torrent error"}];
}

static NSString *BrowserTorrentHashString(lt::sha1_hash const& hash) {
    return BrowserTorrentString(lt::aux::to_hex({hash.data(), hash.size()}));
}

@interface BrowserTorrentManager () {
    std::unique_ptr<lt::session> _session;
}
@property (nonatomic, copy) NSString *storagePath;
@property (nonatomic, copy) NSString *metadataPath;
@property (nonatomic, copy) NSString *indexPath;
@property (nonatomic, copy) NSString *orderPath;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableSet<NSNumber *> *> *skippedFilesByHash;
@property (nonatomic) NSMutableSet<NSString *> *appliedFileSelections;
@property (nonatomic) NSMutableSet<NSString *> *pendingFileSelections;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *activePlaybackFiles;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *lastLoggedFilePercent;
@property (nonatomic) NSTimer *resumeTimer;
@property (nonatomic) NSMutableDictionary<NSString *, NSDate *> *lastResumeRequest;
@property (nonatomic) NSMutableSet<NSString *> *completedResumeRequested;
@property (nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *pendingResetSources;
@property (nonatomic) NSMutableDictionary<NSString *, id> *pendingResetCompletions;
@end

@implementation BrowserTorrentManager

+ (instancetype)sharedManager {
    static BrowserTorrentManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [[BrowserTorrentManager alloc] initPrivate]; });
    return manager;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        _storagePath = [caches stringByAppendingPathComponent:@"BrowserTorrents/Downloads"];
        _metadataPath = [caches stringByAppendingPathComponent:@"BrowserTorrents/Metadata"];
        _indexPath = [_metadataPath stringByAppendingPathComponent:@"sources.plist"];
        _orderPath = [_metadataPath stringByAppendingPathComponent:@"order.plist"];
        _skippedFilesByHash = [NSMutableDictionary dictionary];
        _appliedFileSelections = [NSMutableSet set];
        _pendingFileSelections = [NSMutableSet set];
        _activePlaybackFiles = [NSMutableDictionary dictionary];
        _lastLoggedFilePercent = [NSMutableDictionary dictionary];
        _lastResumeRequest = [NSMutableDictionary dictionary];
        _completedResumeRequested = [NSMutableSet set];
        _pendingResetSources = [NSMutableDictionary dictionary];
        _pendingResetCompletions = [NSMutableDictionary dictionary];
        [[NSFileManager defaultManager] createDirectoryAtPath:_storagePath withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:_metadataPath withIntermediateDirectories:YES attributes:nil error:nil];
        lt::settings_pack settings;
        settings.set_int(lt::settings_pack::alert_mask, int(lt::alert_category::error | lt::alert_category::storage));
        _session = std::make_unique<lt::session>(settings);
        [self restoreSources];
        _resumeTimer = [NSTimer timerWithTimeInterval:10 target:self
            selector:@selector(checkpointTorrents) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_resumeTimer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (NSMutableDictionary<NSString *, NSDictionary *> *)storedSources {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:self.indexPath];
    return [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveSource:(NSDictionary *)source forHash:(NSString *)hash {
    NSMutableDictionary *sources = [self storedSources];
    sources[hash] = source;
    [sources writeToFile:self.indexPath atomically:YES];
}

- (NSString *)resumePathForHash:(NSString *)hash {
    return [self.metadataPath stringByAppendingPathComponent:[hash stringByAppendingPathExtension:@"fastresume"]];
}

- (BOOL)applySavedResumeForHash:(NSString *)hash toParams:(lt::add_torrent_params&)params {
    NSData *data = [NSData dataWithContentsOfFile:[self resumePathForHash:hash]];
    if (!data.length) return NO;
    lt::error_code ec;
    lt::add_torrent_params saved = lt::read_resume_data(
        {(char const *)data.bytes, (std::ptrdiff_t)data.length}, ec);
    NSString *savedHash = BrowserTorrentHashString(saved.ti ? saved.ti->info_hash() : saved.info_hash);
    if (ec || ![savedHash isEqualToString:hash]) {
        BrowserDebugLog(@"[TorrentState] resume rejected code=%d", ec.value());
        return NO;
    }
    params = std::move(saved);
    params.save_path = self.storagePath.UTF8String;
    BrowserDebugLog(@"[TorrentState] resume loaded bytes=%lu", (unsigned long)data.length);
    return YES;
}

- (void)checkpointTorrents {
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);
    NSDictionary *sources = [self storedSources];
    for (lt::alert *alert : alerts) {
        if (auto *deleted = lt::alert_cast<lt::torrent_deleted_alert>(alert)) {
            [self finishResetForHash:BrowserTorrentHashString(deleted->info_hash) deletionError:nil];
        } else if (auto *failedDelete = lt::alert_cast<lt::torrent_delete_failed_alert>(alert)) {
            [self finishResetForHash:BrowserTorrentHashString(failedDelete->info_hash)
                deletionError:BrowserTorrentError(@"Could not remove cached torrent files; the original torrent was restored.")];
        } else if (auto *saved = lt::alert_cast<lt::save_resume_data_alert>(alert)) {
            if (!saved->handle.is_valid()) continue;
            NSString *hash = BrowserTorrentHashString(saved->handle.info_hash());
            if (!sources[hash]) continue;
            std::vector<char> bytes = lt::write_resume_data_buf(saved->params);
            NSData *data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
            BOOL written = [data writeToFile:[self resumePathForHash:hash] atomically:YES];
            BrowserDebugLog(@"[TorrentState] resume saved=%d bytes=%lu", written, (unsigned long)data.length);
        } else if (auto *failed = lt::alert_cast<lt::save_resume_data_failed_alert>(alert)) {
            BrowserDebugLog(@"[TorrentState] resume save failed code=%d", failed->error.value());
        }
    }
    for (lt::torrent_handle const& handle : _session->get_torrents()) {
        if (!handle.is_valid()) continue;
        [self applyStoredFileSelectionsForHandle:handle];
        lt::torrent_status status = handle.status();
        BrowserDebugLog(@"[TorrentState] tick metadata=%d progress=%.4f down=%d peers=%d paused=%d",
            status.has_metadata, status.progress, status.download_payload_rate,
            status.num_peers, bool(status.flags & lt::torrent_flags::paused));
        if (!status.has_metadata) continue;
        auto info = handle.torrent_file();
        if (info) {
            std::vector<std::int64_t> fileProgress;
            handle.file_progress(fileProgress);
            int count = std::min(3, info->files().num_files());
            for (int index = 0; index < count; ++index) {
                lt::file_index_t fileIndex(index);
                std::int64_t size = info->files().file_size(fileIndex);
                std::int64_t downloaded = index < fileProgress.size() ? fileProgress[index] : 0;
                BrowserDebugLog(@"[TorrentState] tick fileIndex=%d priority=%d downloaded=%lld size=%lld",
                    index, int(handle.file_priority(fileIndex)), (long long)downloaded, (long long)size);
            }
        }
        NSString *hash = BrowserTorrentHashString(handle.info_hash());
        if (!sources[hash]) continue;
        BOOL complete = status.state == lt::torrent_status::finished || status.state == lt::torrent_status::seeding;
        if (!complete) [self.completedResumeRequested removeObject:hash];
        BOOL newlyComplete = complete && ![self.completedResumeRequested containsObject:hash];
        BOOL missing = ![[NSFileManager defaultManager] fileExistsAtPath:[self resumePathForHash:hash]];
        NSDate *lastRequest = self.lastResumeRequest[hash];
        BOOL intervalElapsed = !lastRequest || -[lastRequest timeIntervalSinceNow] >= 60;
        if ((missing && intervalElapsed) || newlyComplete || (intervalElapsed && handle.need_save_resume_data())) {
            handle.save_resume_data(lt::torrent_handle::save_info_dict);
            self.lastResumeRequest[hash] = NSDate.date;
            if (complete) [self.completedResumeRequested addObject:hash];
        }
    }
}

- (void)finishResetForHash:(NSString *)hash deletionError:(NSError *)deletionError {
    NSDictionary *original = self.pendingResetSources[hash];
    void (^completion)(NSError *) = self.pendingResetCompletions[hash];
    if (!original) return;
    [self.pendingResetSources removeObjectForKey:hash];
    [self.pendingResetCompletions removeObjectForKey:hash];
    NSMutableDictionary *sources = [self storedSources];
    NSMutableDictionary *source = [original mutableCopy];
    if (!deletionError) {
        [[NSFileManager defaultManager] removeItemAtPath:[self resumePathForHash:hash] error:nil];
        [self.appliedFileSelections removeObject:hash];
        [self.activePlaybackFiles removeObjectForKey:hash];
        [self.lastResumeRequest removeObjectForKey:hash];
        [self.completedResumeRequested removeObject:hash];
        if ([source[@"magnet"] isKindOfClass:NSString.class]) {
            source[@"selectionPending"] = @YES;
            [self.pendingFileSelections addObject:hash];
        } else {
            NSString *filename = source[@"torrent"];
            NSData *data = [NSData dataWithContentsOfFile:[self.metadataPath stringByAppendingPathComponent:filename ?: @""]];
            lt::error_code ec;
            auto info = data ? std::make_shared<lt::torrent_info>((char const *)data.bytes, (int)data.length, ec) : nullptr;
            if (!info || ec) deletionError = BrowserTorrentError(@"Cached files were removed, but torrent metadata could not be reopened.");
            else {
                NSMutableArray *skipped = [NSMutableArray array];
                for (int index = 0; index < info->files().num_files(); ++index) [skipped addObject:@(index)];
                source[@"skipped"] = skipped;
                self.skippedFilesByHash[hash] = [NSMutableSet setWithArray:skipped];
            }
        }
        source[@"selectionPolicy"] = @"manual";
    }
    [source removeObjectForKey:@"resetPending"];
    sources[hash] = source;
    if (![sources writeToFile:self.indexPath atomically:YES]) deletionError = BrowserTorrentError(@"Could not save the reset torrent entry.");
    if (!deletionError) {
        NSError *addError = nil;
        NSString *added = nil;
        if ([source[@"magnet"] isKindOfClass:NSString.class]) {
            added = [self addMagnetString:source[@"magnet"] persist:NO error:&addError];
        } else {
            NSData *data = [NSData dataWithContentsOfFile:[self.metadataPath stringByAppendingPathComponent:source[@"torrent"]]];
            added = [self addTorrentData:data persist:NO error:&addError];
        }
        if (!added) deletionError = addError ?: BrowserTorrentError(@"Could not reopen the reset torrent.");
    } else {
        NSMutableDictionary *restoredSources = [self storedSources];
        restoredSources[hash] = original;
        [restoredSources writeToFile:self.indexPath atomically:YES];
        [self.skippedFilesByHash removeObjectForKey:hash];
        NSArray *skipped = original[@"skipped"];
        if ([skipped isKindOfClass:NSArray.class]) self.skippedFilesByHash[hash] = [NSMutableSet setWithArray:skipped];
        [self.pendingFileSelections removeObject:hash];
        if ([original[@"selectionPending"] boolValue]) [self.pendingFileSelections addObject:hash];
        if ([original[@"magnet"] isKindOfClass:NSString.class]) {
            [self addMagnetString:original[@"magnet"] persist:NO error:nil];
        } else {
            NSData *data = [NSData dataWithContentsOfFile:[self.metadataPath stringByAppendingPathComponent:original[@"torrent"]]];
            [self addTorrentData:data persist:NO error:nil];
        }
        lt::torrent_handle restored = [self handleForIdentifier:hash];
        if (restored.is_valid()) restored.force_recheck();
    }
    BrowserDebugLog(@"[TorrentState] reset completed success=%d", deletionError == nil);
    if (completion) completion(deletionError);
}

- (void)restoreSources {
    NSDictionary<NSString *, NSDictionary *> *sources = [self storedSources];
    [sources enumerateKeysAndObjectsUsingBlock:^(NSString *hash, NSDictionary *source, BOOL *stop) {
        NSArray<NSNumber *> *skipped = source[@"skipped"];
        if ([skipped isKindOfClass:NSArray.class]) {
            self.skippedFilesByHash[hash] = [NSMutableSet setWithArray:skipped];
        }
        if ([source[@"selectionPending"] boolValue]) [self.pendingFileSelections addObject:hash];
        NSString *magnet = source[@"magnet"];
        NSString *filename = source[@"torrent"];
        if ([magnet isKindOfClass:NSString.class]) {
            [self addMagnetString:magnet persist:NO error:nil];
        } else if ([filename isKindOfClass:NSString.class]) {
            NSData *data = [NSData dataWithContentsOfFile:[self.metadataPath stringByAppendingPathComponent:filename]];
            if (data) [self addTorrentData:data persist:NO error:nil];
        }
        if ([source[@"resetPending"] boolValue]) {
            lt::torrent_handle restored = [self handleForIdentifier:hash];
            if (restored.is_valid()) {
                restored.force_recheck();
                NSMutableDictionary *updated = [self storedSources];
                NSMutableDictionary *entry = [updated[hash] mutableCopy];
                [entry removeObjectForKey:@"resetPending"];
                updated[hash] = entry;
                [updated writeToFile:self.indexPath atomically:YES];
                BrowserDebugLog(@"[TorrentState] interrupted reset recovered with recheck");
            }
        }
    }];
    [self applyStoredQueueOrder];
}

- (void)applyStoredQueueOrder {
    NSArray<NSString *> *order = [NSArray arrayWithContentsOfFile:self.orderPath];
    for (NSString *identifier in order.reverseObjectEnumerator) {
        if (![identifier isKindOfClass:NSString.class]) continue;
        lt::torrent_handle handle = [self handleForIdentifier:identifier];
        if (handle.is_valid()) handle.queue_position_top();
    }
}

- (BOOL)addMagnetString:(NSString *)magnet error:(NSError **)error {
    return [self identifierForMagnetString:magnet error:error] != nil;
}

- (NSString *)identifierForMagnetString:(NSString *)magnet error:(NSError **)error {
    return [self addMagnetString:magnet persist:YES error:error];
}

- (NSString *)addMagnetString:(NSString *)magnet persist:(BOOL)persist error:(NSError **)error {
    if (![magnet.lowercaseString hasPrefix:@"magnet:?"]) {
        if (error) *error = BrowserTorrentError(@"This is not a BitTorrent magnet link.");
        return nil;
    }
    lt::error_code ec;
    lt::add_torrent_params params = lt::parse_magnet_uri(magnet.UTF8String, ec);
    if (ec) {
        if (error) *error = BrowserTorrentError(BrowserTorrentString(ec.message()));
        return nil;
    }
    NSString *hash = BrowserTorrentHashString(params.info_hash);
    if ([self handleForIdentifier:hash].is_valid()) return hash;
    params.save_path = self.storagePath.UTF8String;
    if (!persist) [self applySavedResumeForHash:hash toParams:params];
    params.flags |= lt::torrent_flags::sequential_download;
    if (persist || [self.pendingFileSelections containsObject:hash]) {
        params.flags |= lt::torrent_flags::upload_mode;
    }
    lt::torrent_handle handle = _session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        if (error) *error = BrowserTorrentError(BrowserTorrentString(ec.message()));
        return nil;
    }
    hash = BrowserTorrentHashString(handle.info_hash());
    if (persist) {
        [self.pendingFileSelections addObject:hash];
        [self saveSource:@{@"magnet": magnet, @"selectionPending": @YES} forHash:hash];
    }
    return hash;
}

- (BOOL)addTorrentData:(NSData *)data error:(NSError **)error {
    return [self identifierForTorrentData:data error:error] != nil;
}

- (NSString *)identifierForTorrentData:(NSData *)data error:(NSError **)error {
    return [self addTorrentData:data persist:YES error:error];
}

- (NSString *)addTorrentData:(NSData *)data persist:(BOOL)persist error:(NSError **)error {
    if (data.length == 0 || data.length > 16 * 1024 * 1024) {
        if (error) *error = BrowserTorrentError(@"Invalid or oversized .torrent file.");
        return nil;
    }
    lt::error_code ec;
    auto info = std::make_shared<lt::torrent_info>((char const *)data.bytes, (int)data.length, ec);
    if (ec) {
        if (error) *error = BrowserTorrentError(BrowserTorrentString(ec.message()));
        return nil;
    }
    NSString *hash = BrowserTorrentHashString(info->info_hash());
    if ([self handleForIdentifier:hash].is_valid()) return hash;
    lt::add_torrent_params params;
    params.ti = info;
    params.save_path = self.storagePath.UTF8String;
    if (!persist) [self applySavedResumeForHash:hash toParams:params];
    params.ti = info;
    params.flags |= lt::torrent_flags::sequential_download;
    int count = info->files().num_files();
    if (persist) {
        params.file_priorities.assign(count, lt::dont_download);
    } else {
        params.file_priorities.assign(count, lt::default_priority);
        for (NSNumber *number in self.skippedFilesByHash[hash]) {
            NSInteger index = number.integerValue;
            if (index >= 0 && index < count) params.file_priorities[(size_t)index] = lt::dont_download;
        }
    }
    lt::torrent_handle handle = _session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        if (error) *error = BrowserTorrentError(BrowserTorrentString(ec.message()));
        return nil;
    }
    hash = BrowserTorrentHashString(handle.info_hash());
    if (persist) {
        NSMutableArray<NSNumber *> *skipped = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        for (int i = 0; i < count; ++i) [skipped addObject:@(i)];
        self.skippedFilesByHash[hash] = [NSMutableSet setWithArray:skipped];
        NSString *filename = [hash stringByAppendingPathExtension:@"torrent"];
        if ([data writeToFile:[self.metadataPath stringByAppendingPathComponent:filename] atomically:YES]) {
            [self saveSource:@{@"torrent": filename, @"skipped": skipped} forHash:hash];
        }
    }
    return hash;
}

- (void)applyStoredFileSelectionsForHandle:(lt::torrent_handle const&)handle {
    if (!handle.is_valid() || !handle.torrent_file()) return;
    NSString *hash = BrowserTorrentHashString(handle.info_hash());
    NSSet<NSNumber *> *skipped = nil;
    BOOL pending = NO;
    @synchronized (self) {
        if ([self.appliedFileSelections containsObject:hash]) return;
        [self.appliedFileSelections addObject:hash];
        pending = [self.pendingFileSelections containsObject:hash];
        if (pending) {
            int count = handle.torrent_file()->files().num_files();
            NSMutableSet<NSNumber *> *allFiles = [NSMutableSet set];
            for (int i = 0; i < count; ++i) [allFiles addObject:@(i)];
            self.skippedFilesByHash[hash] = allFiles;
            [self.pendingFileSelections removeObject:hash];
            NSMutableDictionary *sources = [self storedSources];
            NSMutableDictionary *source = [sources[hash] mutableCopy] ?: [NSMutableDictionary dictionary];
            source[@"skipped"] = allFiles.allObjects;
            [source removeObjectForKey:@"selectionPending"];
            sources[hash] = source;
            [sources writeToFile:self.indexPath atomically:YES];
        }
        int count = handle.torrent_file()->files().num_files();
        if (count == 1) {
            NSMutableDictionary *sources = [self storedSources];
            NSMutableDictionary *source = [sources[hash] mutableCopy];
            if ([source[@"selectionPolicy"] isEqualToString:@"automaticSingleFile"]) {
                self.skippedFilesByHash[hash] = [NSMutableSet setWithObject:@0];
                source[@"skipped"] = @[@0];
                source[@"selectionPolicy"] = @"manual";
                sources[hash] = source;
                [sources writeToFile:self.indexPath atomically:YES];
                BrowserDebugLog(@"[TorrentState] restored manual start for single-file torrent");
            }
        }
        skipped = [self.skippedFilesByHash[hash] copy];
        for (NSNumber *number in skipped) {
            NSInteger index = number.integerValue;
            if (index >= 0 && index < count) {
                handle.file_priority(lt::file_index_t((int)index), lt::dont_download);
            }
        }
        if (pending) handle.set_upload_mode(false);
    }
}

- (lt::torrent_handle)handleForIdentifier:(NSString *)identifier {
    if (identifier.length != 40) return {};
    lt::sha1_hash hash;
    if (!lt::aux::from_hex({identifier.UTF8String, (std::ptrdiff_t)identifier.length}, hash.data())) return {};
    return _session->find_torrent(hash);
}

- (NSArray<BrowserTorrentSnapshot *> *)torrents {
    NSMutableArray *result = [NSMutableArray array];
    for (lt::torrent_handle const& handle : _session->get_torrents()) {
        [self applyStoredFileSelectionsForHandle:handle];
        lt::torrent_status status = handle.status();
        BrowserTorrentSnapshot *snapshot = [BrowserTorrentSnapshot new];
        snapshot.identifier = BrowserTorrentHashString(handle.info_hash());
        snapshot.name = BrowserTorrentString(status.name);
        snapshot.downloadRate = status.download_payload_rate;
        snapshot.uploadRate = status.upload_payload_rate;
        snapshot.selectedSize = status.total_wanted;
        snapshot.selectedDownloaded = status.total_wanted_done;
        snapshot.progress = snapshot.selectedSize > 0
            ? MIN(1.0, (double)snapshot.selectedDownloaded / snapshot.selectedSize) : 0;
        snapshot.totalSize = status.has_metadata ? handle.torrent_file()->total_size() : 0;
        snapshot.peers = status.num_peers;
        snapshot.seeds = status.num_seeds;
        snapshot.hasMetadata = status.has_metadata;
        if (status.flags & lt::torrent_flags::paused) {
            snapshot.state = @"Paused";
        } else if (status.has_metadata && snapshot.selectedSize == 0) {
            snapshot.state = @"Waiting for Start";
        } else {
            switch (status.state) {
                case lt::torrent_status::downloading_metadata: snapshot.state = @"Finding metadata"; break;
                case lt::torrent_status::downloading: snapshot.state = @"Downloading"; break;
                case lt::torrent_status::seeding: snapshot.state = @"Complete / seeding"; break;
                case lt::torrent_status::checking_files: snapshot.state = @"Checking files"; break;
                case lt::torrent_status::checking_resume_data: snapshot.state = @"Checking files"; break;
                default: snapshot.state = @"Waiting"; break;
            }
        }
        [result addObject:snapshot];
    }
    NSArray<NSString *> *storedOrder = [NSArray arrayWithContentsOfFile:self.orderPath];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *identifier in storedOrder) {
        if (![identifier isKindOfClass:NSString.class]) continue;
        for (BrowserTorrentSnapshot *snapshot in result) {
            if ([snapshot.identifier isEqualToString:identifier] && ![order containsObject:identifier]) {
                [order addObject:identifier];
                break;
            }
        }
    }
    for (BrowserTorrentSnapshot *snapshot in result) {
        if (![order containsObject:snapshot.identifier]) [order addObject:snapshot.identifier];
    }
    if (![order isEqualToArray:storedOrder ?: @[]]) [order writeToFile:self.orderPath atomically:YES];
    [result sortUsingComparator:^NSComparisonResult(BrowserTorrentSnapshot *left, BrowserTorrentSnapshot *right) {
        NSUInteger a = [order indexOfObject:left.identifier];
        NSUInteger b = [order indexOfObject:right.identifier];
        return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
    }];
    return result;
}

- (BOOL)moveTorrent:(NSString *)identifier by:(NSInteger)direction {
    if (direction != -1 && direction != 1) return NO;
    NSArray<BrowserTorrentSnapshot *> *snapshots = [self torrents];
    NSMutableArray<NSString *> *order = [NSMutableArray arrayWithCapacity:snapshots.count];
    for (BrowserTorrentSnapshot *snapshot in snapshots) [order addObject:snapshot.identifier];
    NSUInteger current = [order indexOfObject:identifier];
    if (current == NSNotFound || (direction < 0 && current == 0) ||
        (direction > 0 && current + 1 >= order.count)) return NO;
    [order exchangeObjectAtIndex:current withObjectAtIndex:(NSUInteger)((NSInteger)current + direction)];
    if (![order writeToFile:self.orderPath atomically:YES]) return NO;
    [self applyStoredQueueOrder];
    BrowserDebugLog(@"[TorrentState] moved torrent priority direction=%ld", (long)direction);
    return YES;
}

- (NSArray<BrowserTorrentFile *> *)filesForTorrent:(NSString *)identifier {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    if (!handle.is_valid()) return @[];
    auto info = handle.torrent_file();
    if (!info) return @[];
    [self applyStoredFileSelectionsForHandle:handle];
    lt::file_storage const& storage = info->files();
    std::vector<std::int64_t> progress;
    handle.file_progress(progress);
    lt::torrent_status torrentStatus = handle.status();
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < storage.num_files(); ++i) {
        lt::file_index_t index(i);
        BrowserTorrentFile *file = [BrowserTorrentFile new];
        file.index = i;
        file.path = BrowserTorrentString(storage.file_path(index));
        file.name = file.path.lastPathComponent;
        file.size = storage.file_size(index);
        file.downloaded = i < progress.size() ? progress[i] : 0;
        NSInteger percent = file.size > 0 ? (NSInteger)(100.0 * file.downloaded / file.size) : 0;
        NSString *logKey = [NSString stringWithFormat:@"%@:%d", identifier, i];
        NSNumber *lastPercent = self.lastLoggedFilePercent[logKey];
        if (!lastPercent || percent >= lastPercent.integerValue + 5 || percent <= lastPercent.integerValue - 5 ||
            (percent == 100 && lastPercent.integerValue != 100)) {
            BrowserDebugLog(@"[TorrentState] fileIndex=%d progress=%ld downloaded=%lld size=%lld state=%d rate=%d",
                i, (long)percent, (long long)file.downloaded, (long long)file.size,
                (int)torrentStatus.state, torrentStatus.download_payload_rate);
            self.lastLoggedFilePercent[logKey] = @(percent);
        }
        file.padFile = BrowserTorrentIsPaddingFile(storage, index);
        @synchronized (self) {
            file.downloadEnabled = !file.padFile && ![self.skippedFilesByHash[identifier] containsObject:@(i)];
        }
        [result addObject:file];
    }
    return result;
}

- (NSURL *)fileURLForTorrent:(NSString *)identifier fileIndex:(NSInteger)index {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || index < 0 || index >= info->files().num_files()) return nil;
    NSString *path = BrowserTorrentString(info->files().file_path(lt::file_index_t((int)index)));
    return [NSURL fileURLWithPath:[self.storagePath stringByAppendingPathComponent:path]];
}

- (void)prioritizePlaybackForTorrent:(NSString *)identifier fileIndex:(NSInteger)index {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || index < 0 || index >= info->files().num_files()) return;
    if (BrowserTorrentIsPaddingFile(info->files(), lt::file_index_t((int)index))) return;
    [self setDownloadEnabled:YES forTorrent:identifier fileIndex:index];
    @synchronized (self) {
        NSNumber *previous = self.activePlaybackFiles[identifier];
        if (previous && previous.integerValue != index) {
            handle.file_priority(lt::file_index_t((int)previous.integerValue), lt::default_priority);
        }
        self.activePlaybackFiles[identifier] = @(index);
    }
    [self applyPlaybackPriorityForHandle:handle fileIndex:index];
}

- (void)applyPlaybackPriorityForHandle:(lt::torrent_handle const&)handle fileIndex:(NSInteger)index {
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || index < 0 || index >= info->files().num_files()) return;
    lt::file_index_t fileIndex((int)index);
    handle.file_priority(fileIndex, lt::download_priority_t(7));
    lt::file_storage const& files = info->files();
    int pieceLength = info->piece_length();
    int first = (int)(files.file_offset(fileIndex) / pieceLength);
    int last = (int)((files.file_offset(fileIndex) + files.file_size(fileIndex) - 1) / pieceLength);
    for (int piece = first; piece <= std::min(first + 3, last); ++piece) {
        handle.piece_priority(lt::piece_index_t(piece), lt::download_priority_t(7));
    }
    for (int piece = std::max(first, last - 3); piece <= last; ++piece) {
        handle.piece_priority(lt::piece_index_t(piece), lt::download_priority_t(7));
    }
}

- (BOOL)setDownloadEnabled:(BOOL)enabled forTorrent:(NSString *)identifier fileIndex:(NSInteger)index {
    return [self setDownloadEnabled:enabled forTorrent:identifier fileIndexes:@[@(index)]];
}

- (BOOL)setDownloadEnabled:(BOOL)enabled forTorrent:(NSString *)identifier fileIndexes:(NSArray<NSNumber *> *)indexes {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || indexes.count == 0) return NO;
    for (NSNumber *number in indexes) {
        NSInteger index = number.integerValue;
        if (index < 0 || index >= info->files().num_files() ||
            BrowserTorrentIsPaddingFile(info->files(), lt::file_index_t((int)index))) return NO;
    }
    [self applyStoredFileSelectionsForHandle:handle];
    @synchronized (self) {
        NSMutableSet<NSNumber *> *skipped = self.skippedFilesByHash[identifier];
        if (!skipped) {
            skipped = [NSMutableSet set];
            self.skippedFilesByHash[identifier] = skipped;
        }
        NSNumber *activeIndex = self.activePlaybackFiles[identifier];
        for (NSNumber *number in indexes) {
            NSInteger index = number.integerValue;
            handle.file_priority(lt::file_index_t((int)index), enabled ? lt::default_priority : lt::dont_download);
            if (enabled) [skipped removeObject:number]; else [skipped addObject:number];
            if (activeIndex && !enabled && activeIndex.integerValue == index) activeIndex = nil;
        }
        NSMutableDictionary *sources = [self storedSources];
        NSMutableDictionary *source = [sources[identifier] mutableCopy] ?: [NSMutableDictionary dictionary];
        source[@"skipped"] = skipped.allObjects;
        source[@"selectionPolicy"] = @"explicit";
        sources[identifier] = source;
        [sources writeToFile:self.indexPath atomically:YES];
        if (!activeIndex) {
            [self.activePlaybackFiles removeObjectForKey:identifier];
        } else {
            [self applyPlaybackPriorityForHandle:handle fileIndex:activeIndex.integerValue];
        }
    }
    if (enabled) {
        handle.resume();
        [self applyStoredQueueOrder];
    }
    BrowserDebugLog(@"[TorrentState] selected %lu files enabled=%d", (unsigned long)indexes.count, enabled);
    return YES;
}

- (BOOL)downloadAllFilesForTorrent:(NSString *)identifier {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info) return NO;
    [self applyStoredFileSelectionsForHandle:handle];
    @synchronized (self) {
        NSMutableSet<NSNumber *> *skipped = [NSMutableSet set];
        for (int index = 0; index < info->files().num_files(); ++index) {
            lt::file_index_t fileIndex(index);
            if (BrowserTorrentIsPaddingFile(info->files(), fileIndex)) {
                [skipped addObject:@(index)];
            } else {
                handle.file_priority(fileIndex, lt::default_priority);
            }
        }
        self.skippedFilesByHash[identifier] = skipped;
        NSMutableDictionary *sources = [self storedSources];
        NSMutableDictionary *source = [sources[identifier] mutableCopy] ?: [NSMutableDictionary dictionary];
        source[@"skipped"] = skipped.allObjects;
        source[@"selectionPolicy"] = @"explicit";
        sources[identifier] = source;
        [sources writeToFile:self.indexPath atomically:YES];
        NSNumber *active = self.activePlaybackFiles[identifier];
        if (active) [self applyPlaybackPriorityForHandle:handle fileIndex:active.integerValue];
    }
    handle.resume();
    [self applyStoredQueueOrder];
    BrowserDebugLog(@"[TorrentState] enabled all files count=%d", info->files().num_files());
    return YES;
}

- (BOOL)isFileCompleteForTorrent:(NSString *)identifier fileIndex:(NSInteger)index {
    for (BrowserTorrentFile *file in [self filesForTorrent:identifier]) {
        if (file.index == index) return file.size > 0 && file.downloaded >= file.size;
    }
    return NO;
}

- (NSData *)availableDataForTorrent:(NSString *)identifier
                          fileIndex:(NSInteger)index
                             offset:(int64_t)offset
                             length:(NSUInteger)length {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || index < 0 || index >= info->files().num_files() || offset < 0 || length == 0) return nil;
    lt::file_index_t fileIndex((int)index);
    lt::file_storage const& files = info->files();
    int64_t fileSize = files.file_size(fileIndex);
    if (offset >= fileSize) return nil;
    NSUInteger readLength = (NSUInteger)std::min<int64_t>((int64_t)length, fileSize - offset);
    int64_t globalStart = files.file_offset(fileIndex) + offset;
    int64_t globalEnd = globalStart + (int64_t)readLength - 1;
    int pieceLength = info->piece_length();
    int first = (int)(globalStart / pieceLength);
    int last = (int)(globalEnd / pieceLength);
    for (int piece = first; piece <= last; ++piece) {
        if (!handle.have_piece(lt::piece_index_t(piece))) return nil;
    }
    NSURL *URL = [self fileURLForTorrent:identifier fileIndex:index];
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:URL error:nil];
    if (!file) return nil;
    @try {
        [file seekToFileOffset:(uint64_t)offset];
        NSData *data = [file readDataOfLength:readLength];
        [file closeFile];
        return data.length == readLength ? data : nil;
    } @catch (NSException *exception) {
        [file closeFile];
        return nil;
    }
}

- (void)prioritizeTorrent:(NSString *)identifier fileIndex:(NSInteger)index offset:(int64_t)offset {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || index < 0 || index >= info->files().num_files() || offset < 0) return;
    lt::file_index_t fileIndex((int)index);
    if (offset >= info->files().file_size(fileIndex)) return;
    int piece = (int)((info->files().file_offset(fileIndex) + offset) / info->piece_length());
    for (int i = piece; i < std::min(piece + 4, info->num_pieces()); ++i) {
        handle.piece_priority(lt::piece_index_t(i), lt::download_priority_t(7));
    }
}

- (BOOL)removeTorrent:(NSString *)identifier deleteFiles:(BOOL)deleteFiles {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    if (!handle.is_valid()) return NO;
    @synchronized (self) {
        _session->remove_torrent(handle, deleteFiles ? lt::session::delete_files : lt::remove_flags_t{});
        NSMutableDictionary *sources = [self storedSources];
        NSString *filename = sources[identifier][@"torrent"];
        if (filename) [[NSFileManager defaultManager] removeItemAtPath:[self.metadataPath stringByAppendingPathComponent:filename] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self resumePathForHash:identifier] error:nil];
        [sources removeObjectForKey:identifier];
        [sources writeToFile:self.indexPath atomically:YES];
        [self.skippedFilesByHash removeObjectForKey:identifier];
        [self.appliedFileSelections removeObject:identifier];
        [self.pendingFileSelections removeObject:identifier];
        [self.activePlaybackFiles removeObjectForKey:identifier];
        [self.lastResumeRequest removeObjectForKey:identifier];
        [self.completedResumeRequested removeObject:identifier];
    }
    return YES;
}

- (BOOL)resetTorrent:(NSString *)identifier completion:(void (^)(NSError *))completion {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    if (!handle.is_valid() || self.pendingResetSources[identifier]) return NO;
    NSMutableDictionary *sources = [self storedSources];
    NSDictionary *source = sources[identifier];
    NSString *filename = source[@"torrent"];
    if (![source[@"magnet"] isKindOfClass:NSString.class] &&
        (![filename isKindOfClass:NSString.class] ||
         ![[NSFileManager defaultManager] fileExistsAtPath:[self.metadataPath stringByAppendingPathComponent:filename]])) return NO;
    self.pendingResetSources[identifier] = source;
    if (completion) self.pendingResetCompletions[identifier] = [completion copy];
    NSMutableDictionary *pending = [source mutableCopy];
    pending[@"resetPending"] = @YES;
    sources[identifier] = pending;
    if (![sources writeToFile:self.indexPath atomically:YES]) {
        [self.pendingResetSources removeObjectForKey:identifier];
        [self.pendingResetCompletions removeObjectForKey:identifier];
        return NO;
    }
    _session->remove_torrent(handle, lt::session::delete_files);
    BrowserDebugLog(@"[TorrentState] reset requested");
    [self performSelector:@selector(pollResetAlerts) withObject:nil afterDelay:1.0 inModes:@[NSRunLoopCommonModes]];
    return YES;
}

- (void)pollResetAlerts {
    if (self.pendingResetSources.count == 0) return;
    [self checkpointTorrents];
    if (self.pendingResetSources.count > 0)
        [self performSelector:@selector(pollResetAlerts) withObject:nil afterDelay:1.0 inModes:@[NSRunLoopCommonModes]];
}

- (uint64_t)clearAllTorrentDownloadsWithRemovedCount:(NSUInteger *)removedCount error:(NSError **)error {
    @synchronized (self) {
        uint64_t before = [self totalTorrentCacheBytes];
        NSUInteger count = 0;
        NSDirectoryEnumerator<NSURL *> *files = [NSFileManager.defaultManager
            enumeratorAtURL:[NSURL fileURLWithPath:self.storagePath]
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey]
            options:NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
        for (NSURL *URL in files) {
            NSNumber *directory = nil;
            [URL getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
            if (!directory.boolValue) count++;
        }
        NSMutableDictionary<NSString *, NSDictionary *> *sources = [self storedSources];
        for (NSDictionary *source in sources.allValues) {
            NSString *filename = source[@"torrent"];
            if (![filename isKindOfClass:NSString.class]) continue;
            NSString *path = [self.metadataPath stringByAppendingPathComponent:filename];
            if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
                if (error) *error = BrowserTorrentError(@"A listed torrent is missing its metadata; downloads were kept to avoid losing its entry.");
                return 0;
            }
        }
        for (NSString *hash in sources.allKeys) {
            NSMutableDictionary *source = [sources[hash] mutableCopy];
            lt::torrent_handle handle = [self handleForIdentifier:hash];
            auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
            if (info) {
                NSMutableArray<NSNumber *> *allFiles = [NSMutableArray array];
                for (int index = 0; index < info->files().num_files(); ++index) [allFiles addObject:@(index)];
                source[@"skipped"] = allFiles;
            }
            if ([source[@"magnet"] isKindOfClass:NSString.class]) source[@"selectionPending"] = @YES;
            source[@"selectionPolicy"] = @"manual";
            sources[hash] = source;
        }
        if (![sources writeToFile:self.indexPath atomically:YES]) {
            if (error) *error = BrowserTorrentError(@"Could not save torrent entries; downloads were kept.");
            return 0;
        }
        _session.reset();
        NSFileManager *manager = NSFileManager.defaultManager;
        NSError *storageError = nil;
        BOOL removed = [manager removeItemAtPath:self.storagePath error:&storageError];
        BOOL recreated = [manager createDirectoryAtPath:self.storagePath
                            withIntermediateDirectories:YES attributes:nil error:nil];
        if (!removed || !recreated) {
            BrowserDebugLog(@"[TorrentState] clear failed code=%ld", (long)storageError.code);
            lt::settings_pack settings;
            settings.set_int(lt::settings_pack::alert_mask, int(lt::alert_category::error | lt::alert_category::storage));
            _session = std::make_unique<lt::session>(settings);
            [self restoreSources];
            if (error) *error = BrowserTorrentError(@"Could not purge the torrent downloads.");
            return 0;
        }
        NSDirectoryEnumerator<NSURL *> *metadata = [manager enumeratorAtURL:[NSURL fileURLWithPath:self.metadataPath]
            includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
        for (NSURL *URL in metadata) {
            if ([URL.pathExtension.lowercaseString isEqualToString:@"fastresume"]) {
                [manager removeItemAtURL:URL error:nil];
                count++;
            }
        }
        [self.skippedFilesByHash removeAllObjects];
        [self.appliedFileSelections removeAllObjects];
        [self.pendingFileSelections removeAllObjects];
        [self.activePlaybackFiles removeAllObjects];
        [self.lastLoggedFilePercent removeAllObjects];
        [self.lastResumeRequest removeAllObjects];
        [self.completedResumeRequested removeAllObjects];
        lt::settings_pack settings;
        settings.set_int(lt::settings_pack::alert_mask, int(lt::alert_category::error | lt::alert_category::storage));
        _session = std::make_unique<lt::session>(settings);
        [self restoreSources];
        if (removedCount) *removedCount = count;
        uint64_t after = [self totalTorrentCacheBytes];
        BrowserDebugLog(@"[TorrentState] cleared downloads files=%lu freed=%llu", (unsigned long)count,
            (unsigned long long)(before > after ? before - after : 0));
        return before > after ? before - after : 0;
    }
}

- (uint64_t)totalTorrentCacheBytes {
    NSFileManager *manager = NSFileManager.defaultManager;
    uint64_t total = 0;
    for (NSString *root in @[self.storagePath, self.metadataPath]) {
        NSDirectoryEnumerator<NSURL *> *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:root]
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey, NSURLFileSizeKey]
            options:NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
        for (NSURL *URL in enumerator) {
            NSNumber *symbolicLink = nil;
            [URL getResourceValue:&symbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
            if (symbolicLink.boolValue) { [enumerator skipDescendants]; continue; }
            NSNumber *directory = nil;
            [URL getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
            if (directory.boolValue) continue;
            NSNumber *size = nil;
            [URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            total += size.unsignedLongLongValue;
        }
    }
    return total;
}

- (BOOL)setPaused:(BOOL)paused forTorrent:(NSString *)identifier {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    if (!handle.is_valid()) return NO;
    if (paused) handle.pause(); else handle.resume();
    return YES;
}

- (void)backgroundTransferPending:(BOOL *)pending downloadedBytes:(int64_t *)downloadedBytes {
    BOOL hasPending = NO;
    int64_t downloaded = 0;
    for (lt::torrent_handle const& handle : _session->get_torrents()) {
        if (!handle.is_valid()) continue;
        [self applyStoredFileSelectionsForHandle:handle];
        lt::torrent_status status = handle.status();
        if (!status.has_metadata || (status.flags & lt::torrent_flags::paused)) continue;
        downloaded += status.total_wanted_done;
        if (status.total_wanted > status.total_wanted_done) hasPending = YES;
    }
    if (pending) *pending = hasPending;
    if (downloadedBytes) *downloadedBytes = downloaded;
}

- (void)requestFastResumeCheckpoint {
    for (lt::torrent_handle const& handle : _session->get_torrents()) {
        if (!handle.is_valid() || !handle.torrent_file()) continue;
        handle.save_resume_data(lt::torrent_handle::save_info_dict);
    }
    BrowserDebugLog(@"[TorrentState] background resume checkpoint requested");
}

@end
