#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTopBarView : UIVisualEffectView

@property (nonatomic, readonly) UIImageView *backImageView;
@property (nonatomic, readonly) UIImageView *refreshImageView;
@property (nonatomic, readonly) UIImageView *forwardImageView;
@property (nonatomic, readonly) UIImageView *homeImageView;
@property (nonatomic, readonly) UIImageView *tabsImageView;
@property (nonatomic, readonly) UIImageView *fullscreenImageView;
@property (nonatomic, readonly) UIImageView *menuImageView;
@property (nonatomic, readonly) UILabel *URLLabel;
@property (nonatomic, readonly) UIActivityIndicatorView *loadingSpinner;

- (CGRect)interactiveFrameForView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
