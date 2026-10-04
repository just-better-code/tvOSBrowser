#import <Foundation/Foundation.h>

@class AVURLAsset;

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTorrentAssetLoader : NSObject
- (BOOL)attachToAsset:(AVURLAsset *)asset;
@end

NS_ASSUME_NONNULL_END
