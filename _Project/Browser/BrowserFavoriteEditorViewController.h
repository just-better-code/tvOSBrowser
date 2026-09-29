#import <UIKit/UIKit.h>

@interface BrowserFavoriteEditorViewController : UIViewController

- (instancetype)initWithTitle:(NSString *)title URLString:(NSString *)URLString;

@property (nonatomic, copy) NSString * (^saveHandler)(NSString *title, NSString *URLString);
@property (nonatomic, copy) void (^deleteHandler)(void);

@end
