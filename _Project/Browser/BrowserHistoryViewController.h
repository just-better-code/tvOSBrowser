#import <UIKit/UIKit.h>

@interface BrowserHistoryViewController : UIViewController

@property (nonatomic, copy) void (^historyDidChange)(void);

@end
