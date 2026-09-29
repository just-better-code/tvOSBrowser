#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A torrent stored in tvOS's purgeable Caches directory.
@interface BrowserTorrentSnapshot : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *state;
@property (nonatomic) double progress;
@property (nonatomic) int64_t downloadRate;
@property (nonatomic) NSInteger peers;
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
- (BOOL)isFileCompleteForTorrent:(NSString *)identifier fileIndex:(NSInteger)index;
- (nullable NSData *)availableDataForTorrent:(NSString *)identifier
                                 fileIndex:(NSInteger)index
                                    offset:(int64_t)offset
                                    length:(NSUInteger)length;
- (void)prioritizeTorrent:(NSString *)identifier fileIndex:(NSInteger)index offset:(int64_t)offset;
- (BOOL)removeTorrent:(NSString *)identifier deleteFiles:(BOOL)deleteFiles;
- (BOOL)setPaused:(BOOL)paused forTorrent:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
