#import "BrowserTorrentManager.h"

#import <libtorrent/add_torrent_params.hpp>
#import <libtorrent/download_priority.hpp>
#import <libtorrent/hex.hpp>
#import <libtorrent/magnet_uri.hpp>
#import <libtorrent/read_resume_data.hpp>
#import <libtorrent/session.hpp>
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
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableSet<NSNumber *> *> *skippedFilesByHash;
@property (nonatomic) NSMutableSet<NSString *> *appliedFileSelections;
@property (nonatomic) NSMutableSet<NSString *> *pendingFileSelections;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *activePlaybackFiles;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *lastLoggedFilePercent;
@property (nonatomic) NSTimer *resumeTimer;
@property (nonatomic) NSMutableDictionary<NSString *, NSDate *> *lastResumeRequest;
@property (nonatomic) NSMutableSet<NSString *> *completedResumeRequested;
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
        _skippedFilesByHash = [NSMutableDictionary dictionary];
        _appliedFileSelections = [NSMutableSet set];
        _pendingFileSelections = [NSMutableSet set];
        _activePlaybackFiles = [NSMutableDictionary dictionary];
        _lastLoggedFilePercent = [NSMutableDictionary dictionary];
        _lastResumeRequest = [NSMutableDictionary dictionary];
        _completedResumeRequested = [NSMutableSet set];
        [[NSFileManager defaultManager] createDirectoryAtPath:_storagePath withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:_metadataPath withIntermediateDirectories:YES attributes:nil error:nil];
        _session = std::make_unique<lt::session>();
        [self restoreSources];
        _resumeTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self
            selector:@selector(checkpointTorrents) userInfo:nil repeats:YES];
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
        NSLog(@"[TorrentState] resume rejected code=%d", ec.value());
        return NO;
    }
    params = std::move(saved);
    params.save_path = self.storagePath.UTF8String;
    NSLog(@"[TorrentState] resume loaded bytes=%lu", (unsigned long)data.length);
    return YES;
}

- (void)checkpointTorrents {
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);
    NSDictionary *sources = [self storedSources];
    for (lt::alert *alert : alerts) {
        if (auto *saved = lt::alert_cast<lt::save_resume_data_alert>(alert)) {
            if (!saved->handle.is_valid()) continue;
            NSString *hash = BrowserTorrentHashString(saved->handle.info_hash());
            if (!sources[hash]) continue;
            std::vector<char> bytes = lt::write_resume_data_buf(saved->params);
            NSData *data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
            BOOL written = [data writeToFile:[self resumePathForHash:hash] atomically:YES];
            NSLog(@"[TorrentState] resume saved=%d bytes=%lu", written, (unsigned long)data.length);
        } else if (auto *failed = lt::alert_cast<lt::save_resume_data_failed_alert>(alert)) {
            NSLog(@"[TorrentState] resume save failed code=%d", failed->error.value());
        }
    }
    for (lt::torrent_handle const& handle : _session->get_torrents()) {
        if (!handle.is_valid()) continue;
        lt::torrent_status status = handle.status();
        if (!status.has_metadata) continue;
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
    }];
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
        skipped = [self.skippedFilesByHash[hash] copy];
        int count = handle.torrent_file()->files().num_files();
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
        snapshot.progress = status.progress;
        snapshot.downloadRate = status.download_payload_rate;
        snapshot.peers = status.num_peers;
        snapshot.hasMetadata = status.has_metadata;
        if (status.flags & lt::torrent_flags::paused) {
            snapshot.state = @"Paused";
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
    return result;
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
            NSLog(@"[TorrentState] fileIndex=%d progress=%ld downloaded=%lld size=%lld state=%d rate=%d",
                i, (long)percent, (long long)file.downloaded, (long long)file.size,
                (int)torrentStatus.state, torrentStatus.download_payload_rate);
            self.lastLoggedFilePercent[logKey] = @(percent);
        }
        file.padFile = storage.pad_file_at(index);
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
    if (info->files().pad_file_at(lt::file_index_t((int)index))) return;
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
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    auto info = handle.is_valid() ? handle.torrent_file() : nullptr;
    if (!info || index < 0 || index >= info->files().num_files()) return NO;
    lt::file_index_t fileIndex((int)index);
    if (info->files().pad_file_at(fileIndex)) return NO;
    [self applyStoredFileSelectionsForHandle:handle];
    @synchronized (self) {
        handle.file_priority(fileIndex, enabled ? lt::default_priority : lt::dont_download);
        NSMutableSet<NSNumber *> *skipped = self.skippedFilesByHash[identifier];
        if (!skipped) {
            skipped = [NSMutableSet set];
            self.skippedFilesByHash[identifier] = skipped;
        }
        if (enabled) [skipped removeObject:@(index)]; else [skipped addObject:@(index)];
        NSMutableDictionary *sources = [self storedSources];
        NSMutableDictionary *source = [sources[identifier] mutableCopy] ?: [NSMutableDictionary dictionary];
        source[@"skipped"] = skipped.allObjects;
        sources[identifier] = source;
        [sources writeToFile:self.indexPath atomically:YES];
        NSNumber *activeIndex = self.activePlaybackFiles[identifier];
        if (activeIndex && !enabled && activeIndex.integerValue == index) {
            [self.activePlaybackFiles removeObjectForKey:identifier];
        } else if (activeIndex) {
            [self applyPlaybackPriorityForHandle:handle fileIndex:activeIndex.integerValue];
        }
    }
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

- (uint64_t)cleanUnlistedCacheFilesWithRemovedCount:(NSUInteger *)removedCount {
    @synchronized (self) {
        NSFileManager *manager = NSFileManager.defaultManager;
        NSString *downloadsRoot = self.storagePath.stringByStandardizingPath;
        NSString *metadataRoot = self.metadataPath.stringByStandardizingPath;
        NSMutableSet<NSString *> *keepDownloads = [NSMutableSet set];
        for (lt::torrent_handle const& handle : _session->get_torrents()) {
            auto info = handle.torrent_file();
            if (!info) continue;
            lt::file_storage const& files = info->files();
            for (int i = 0; i < files.num_files(); ++i) {
                NSString *relative = BrowserTorrentString(files.file_path(lt::file_index_t(i)));
                NSString *path = [[downloadsRoot stringByAppendingPathComponent:relative] stringByStandardizingPath];
                if ([path hasPrefix:[downloadsRoot stringByAppendingString:@"/"]]) [keepDownloads addObject:path];
            }
        }
        NSMutableSet<NSString *> *keepMetadata = [NSMutableSet setWithObject:self.indexPath.stringByStandardizingPath];
        for (NSDictionary *source in [self storedSources].allValues) {
            NSString *filename = source[@"torrent"];
            if (![filename isKindOfClass:NSString.class]) continue;
            NSString *path = [[metadataRoot stringByAppendingPathComponent:filename] stringByStandardizingPath];
            if ([path hasPrefix:[metadataRoot stringByAppendingString:@"/"]]) [keepMetadata addObject:path];
        }
        for (NSString *hash in [self storedSources]) {
            [keepMetadata addObject:[self resumePathForHash:hash].stringByStandardizingPath];
        }
        uint64_t freed = 0;
        NSUInteger count = 0;
        for (NSArray *entry in @[@[downloadsRoot, keepDownloads], @[metadataRoot, keepMetadata]]) {
            NSString *root = entry[0];
            NSSet<NSString *> *keep = entry[1];
            NSMutableArray<NSURL *> *directories = [NSMutableArray array];
            NSDirectoryEnumerator<NSURL *> *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:root]
                includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey, NSURLFileSizeKey]
                options:NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
            for (NSURL *URL in enumerator) {
                NSNumber *symbolicLink = nil;
                [URL getResourceValue:&symbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
                if (symbolicLink.boolValue) {
                    [enumerator skipDescendants];
                    if ([manager removeItemAtURL:URL error:nil]) count++;
                    continue;
                }
                NSNumber *directory = nil;
                [URL getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
                if (directory.boolValue) { [directories addObject:URL]; continue; }
                if ([keep containsObject:URL.path.stringByStandardizingPath]) continue;
                NSNumber *size = nil;
                [URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                if ([manager removeItemAtURL:URL error:nil]) {
                    freed += size.unsignedLongLongValue;
                    count++;
                }
            }
            for (NSURL *directory in directories.reverseObjectEnumerator) {
                [manager removeItemAtURL:directory error:nil];
            }
        }
        if (removedCount) *removedCount = count;
        return freed;
    }
}

- (BOOL)setPaused:(BOOL)paused forTorrent:(NSString *)identifier {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    if (!handle.is_valid()) return NO;
    if (paused) handle.pause(); else handle.resume();
    return YES;
}

@end
