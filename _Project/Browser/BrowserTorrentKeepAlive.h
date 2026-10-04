#import <Foundation/Foundation.h>

@interface BrowserTorrentKeepAlive : NSObject
+ (instancetype)sharedKeepAlive;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end
