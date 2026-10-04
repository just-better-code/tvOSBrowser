#import <Foundation/Foundation.h>

@interface BrowserTorrentHTTPServer : NSObject
@property (nonatomic, readonly) NSURL *mediaURL;
- (instancetype)initWithTorrentIdentifier:(NSString *)identifier fileIndex:(NSInteger)index;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
@end
