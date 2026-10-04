#import <UIKit/UIKit.h>

@interface BrowserTorrentVLCPlayerViewController : UIViewController
- (instancetype)initWithTorrentIdentifier:(NSString *)identifier fileIndex:(NSInteger)index title:(NSString *)title;
@end
