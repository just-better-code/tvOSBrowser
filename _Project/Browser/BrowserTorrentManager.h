#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A torrent stored in tvOS's purgeable Caches directory.
@interface BrowserTorrentSnapshot : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *state;
@property (nonatomic) double progress;
@property (nonatomic) int64_t downloadRate;
@property (nonatomic) int64_t uploadRate;
@property (nonatomic) int64_t selectedSize;
@property (nonatomic) int64_t selectedDownloaded;
@property (nonatomic) int64_t totalSize;
@property (nonatomic) NSInteger peers;
@property (nonatomic) NSInteger seeds;
@property (nonatomic) BOOL hasMetadata;
@end

@interface BrowserTorrentFile : NSObject
@property (nonatomic) NSInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) int64_t size;
@property (nonatomic) int64_t downloaded;
@property (nonatomic) BOOL downloadEnabled;
@property (nonatomic) BOOL padFile;
@end

@interface BrowserTorrentManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)addMagnetString:(NSString *)magnet error:(NSError **)error;
- (BOOL)addTorrentData:(NSData *)data error:(NSError **)error;
- (nullable NSString *)identifierForMagnetString:(NSString *)magnet error:(NSError **)error;
- (nullable NSString *)identifierForTorrentData:(NSData *)data error:(NSError **)error;
- (NSArray<BrowserTorrentSnapshot *> *)torrents;
- (NSArray<BrowserTorrentFile *> *)filesForTorrent:(NSString *)identifier;
- (nullable NSURL *)fileURLForTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (void)prioritizePlaybackForTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (BOOL)setDownloadEnabled:(BOOL)enabled forTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (BOOL)setDownloadEnabled:(BOOL)enabled forTorrent:(NSString *)identifier fileIndexes:(NSArray<NSNumber *> *)indexes;
- (BOOL)downloadAllFilesForTorrent:(NSString *)identifier;
- (BOOL)moveTorrent:(NSString *)identifier by:(NSInteger)direction;
- (BOOL)isFileCompleteForTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (double)downloadProgressForTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (int64_t)playbackPositionForTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (void)savePlaybackPosition:(int64_t)milliseconds forTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (void)clearPlaybackPositionsForTorrent:(NSString *)identifier;
- (nullable NSData *)availableDataForTorrent:(NSString *)identifier
                                 fileIndex:(NSInteger)index
                                    offset:(int64_t)offset
                                    length:(NSUInteger)length;
- (void)prioritizeTorrent:(NSString *)identifier fileIndex:(NSInteger)index offset:(int64_t)offset;
- (BOOL)removeTorrent:(NSString *)identifier deleteFiles:(BOOL)deleteFiles;
- (BOOL)resetTorrent:(NSString *)identifier completion:(void (^)(NSError * _Nullable error))completion;
- (uint64_t)clearAllTorrentDownloadsWithRemovedCount:(NSUInteger *)removedCount error:(NSError **)error;
- (uint64_t)totalTorrentCacheBytes;
- (BOOL)setPaused:(BOOL)paused forTorrent:(NSString *)identifier;
/// Aggregate only manually selected, incomplete, unpaused payloads for background scheduling.
- (void)backgroundTransferPending:(BOOL *)pending downloadedBytes:(int64_t *)downloadedBytes;
- (void)requestFastResumeCheckpoint;
@end

NS_ASSUME_NONNULL_END
