#import "BrowserTorrentManager.h"

#import <libtorrent/add_torrent_params.hpp>
#import <libtorrent/download_priority.hpp>
#import <libtorrent/hex.hpp>
#import <libtorrent/magnet_uri.hpp>
#import <libtorrent/session.hpp>
#import <libtorrent/torrent_handle.hpp>
#import <libtorrent/torrent_info.hpp>
#import <libtorrent/torrent_status.hpp>

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
        [[NSFileManager defaultManager] createDirectoryAtPath:_storagePath withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:_metadataPath withIntermediateDirectories:YES attributes:nil error:nil];
        _session = std::make_unique<lt::session>();
        [self restoreSources];
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

- (void)restoreSources {
    NSDictionary<NSString *, NSDictionary *> *sources = [self storedSources];
    [sources enumerateKeysAndObjectsUsingBlock:^(NSString *hash, NSDictionary *source, BOOL *stop) {
        NSArray<NSNumber *> *skipped = source[@"skipped"];
        if ([skipped isKindOfClass:NSArray.class]) {
            self.skippedFilesByHash[hash] = [NSMutableSet setWithArray:skipped];
        }
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
    params.flags |= lt::torrent_flags::sequential_download;
    lt::torrent_handle handle = _session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        if (error) *error = BrowserTorrentError(BrowserTorrentString(ec.message()));
        return nil;
    }
    hash = BrowserTorrentHashString(handle.info_hash());
    if (persist) [self saveSource:@{@"magnet": magnet} forHash:hash];
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
    params.flags |= lt::torrent_flags::sequential_download;
    lt::torrent_handle handle = _session->add_torrent(params, ec);
    if (ec || !handle.is_valid()) {
        if (error) *error = BrowserTorrentError(BrowserTorrentString(ec.message()));
        return nil;
    }
    hash = BrowserTorrentHashString(handle.info_hash());
    if (persist) {
        NSString *filename = [hash stringByAppendingPathExtension:@"torrent"];
        if ([data writeToFile:[self.metadataPath stringByAppendingPathComponent:filename] atomically:YES]) {
            [self saveSource:@{@"torrent": filename} forHash:hash];
        }
    }
    return hash;
}

- (void)applyStoredFileSelectionsForHandle:(lt::torrent_handle const&)handle {
    if (!handle.is_valid() || !handle.torrent_file()) return;
    NSString *hash = BrowserTorrentHashString(handle.info_hash());
    NSSet<NSNumber *> *skipped = nil;
    @synchronized (self) {
        if ([self.appliedFileSelections containsObject:hash]) return;
        [self.appliedFileSelections addObject:hash];
        skipped = [self.skippedFilesByHash[hash] copy];
    }
    int count = handle.torrent_file()->files().num_files();
    for (NSNumber *number in skipped) {
        NSInteger index = number.integerValue;
        if (index >= 0 && index < count) {
            handle.file_priority(lt::file_index_t((int)index), lt::dont_download);
        }
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
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < storage.num_files(); ++i) {
        lt::file_index_t index(i);
        BrowserTorrentFile *file = [BrowserTorrentFile new];
        file.index = i;
        file.path = BrowserTorrentString(storage.file_path(index));
        file.name = file.path.lastPathComponent;
        file.size = storage.file_size(index);
        file.downloaded = i < progress.size() ? progress[i] : 0;
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
    handle.file_priority(fileIndex, enabled ? lt::default_priority : lt::dont_download);
    @synchronized (self) {
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
    _session->remove_torrent(handle, deleteFiles ? lt::session::delete_files : lt::remove_flags_t{});
    NSMutableDictionary *sources = [self storedSources];
    NSString *filename = sources[identifier][@"torrent"];
    if (filename) [[NSFileManager defaultManager] removeItemAtPath:[self.metadataPath stringByAppendingPathComponent:filename] error:nil];
    [sources removeObjectForKey:identifier];
    [sources writeToFile:self.indexPath atomically:YES];
    @synchronized (self) {
        [self.skippedFilesByHash removeObjectForKey:identifier];
        [self.appliedFileSelections removeObject:identifier];
    }
    return YES;
}

- (BOOL)setPaused:(BOOL)paused forTorrent:(NSString *)identifier {
    lt::torrent_handle handle = [self handleForIdentifier:identifier];
    if (!handle.is_valid()) return NO;
    if (paused) handle.pause(); else handle.resume();
    return YES;
}

@end
