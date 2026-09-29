#import <UIKit/UIKit.h>

@interface BrowserTorrentLibraryViewController : UIViewController
- (void)promptToAddTorrent;
- (void)selectTorrent:(NSString *)identifier;
- (void)importTorrentRequest:(NSURLRequest *)request;
@end
