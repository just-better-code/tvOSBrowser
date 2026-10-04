#import <UIKit/UIKit.h>

@interface BrowserTorrentLibraryViewController : UIViewController
- (void)selectTorrent:(NSString *)identifier;
- (void)focusTorrent:(NSString *)identifier;
- (void)handleBackPress;
- (void)importTorrentRequest:(NSURLRequest *)request;
- (void)showImportError:(NSString *)message;
@end
