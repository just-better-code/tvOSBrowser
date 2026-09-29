#import <UIKit/UIKit.h>

@interface BrowserHistoryViewController : UIViewController

@property (nonatomic, copy) void (^historyDidChange)(void);
@property (nonatomic, copy) void (^openURLString)(NSString *URLString);

@end
