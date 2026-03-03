#import "BrowserTopBarView.h"

#if __has_include(<UIKit/UIGlassEffect.h>)
#import <UIKit/UIGlassEffect.h>
#endif

static CGFloat const kTopBarHorizontalInset = 40.0;
static CGFloat const kTopBarVerticalInset = 8.0;
static CGFloat const kTopBarHeight = 86.0;
static CGFloat const kTopBarMaxWidth = 1760.0;
static CGFloat const kTopBarIconSize = 52.0;
static CGFloat const kTopBarLeadingPadding = 28.0;
static CGFloat const kTopBarTrailingPadding = 26.0;
static CGFloat const kTopBarIconSpacing = 24.0;
static CGFloat const kTopBarLabelSpacing = 28.0;
static CGFloat const kTopBarSpinnerSpacing = 22.0;

@interface BrowserTopBarView ()

@property (nonatomic) UIView *chromeContainerView;
@property (nonatomic) UIVisualEffectView *chromeEffectView;
@property (nonatomic) UIImageView *backImageView;
@property (nonatomic) UIImageView *refreshImageView;
@property (nonatomic) UIImageView *forwardImageView;
@property (nonatomic) UIImageView *homeImageView;
@property (nonatomic) UIImageView *tabsImageView;
@property (nonatomic) UIImageView *fullscreenImageView;
@property (nonatomic) UIImageView *menuImageView;
@property (nonatomic) UILabel *URLLabel;
@property (nonatomic) UIActivityIndicatorView *loadingSpinner;

@end

@implementation BrowserTopBarView

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect {
    self = [super initWithEffect:effect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];

    for (UIView *subview in [self.contentView.subviews copy]) {
        if (subview != self.chromeContainerView) {
            [subview removeFromSuperview];
        }
    }
}

- (void)commonInit {
    self.effect = nil;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;
    self.userInteractionEnabled = NO;

    self.chromeContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.chromeContainerView.backgroundColor = UIColor.clearColor;
    self.chromeContainerView.userInteractionEnabled = NO;
    self.chromeContainerView.clipsToBounds = NO;
    [self.contentView addSubview:self.chromeContainerView];

    self.chromeEffectView = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.chromeEffectView.userInteractionEnabled = NO;
    self.chromeEffectView.clipsToBounds = YES;
    [self.chromeContainerView addSubview:self.chromeEffectView];

    _backImageView = [self newIconViewNamed:@"go-back-left-arrow"];
    _refreshImageView = [self newIconViewNamed:@"refresh-button"];
    _forwardImageView = [self newIconViewNamed:@"right-arrow-forward"];
    _homeImageView = [self newIconViewNamed:@"house-outline"];
    _tabsImageView = [self newIconViewNamed:@"multi-tab"];
    _fullscreenImageView = [self newIconViewNamed:@"resize-arrows"];
    _menuImageView = [self newIconViewNamed:@"menu-2"];

    _URLLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _URLLabel.text = @"tvOS Browser";
    _URLLabel.textAlignment = NSTextAlignmentCenter;
    _URLLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    _URLLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _URLLabel.adjustsFontSizeToFitWidth = NO;
    _URLLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.chromeEffectView.contentView addSubview:_URLLabel];

    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingSpinner.color = [UIColor colorWithWhite:1.0 alpha:0.92];
    _loadingSpinner.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    _loadingSpinner.hidesWhenStopped = YES;
    [self.chromeEffectView.contentView addSubview:_loadingSpinner];

    NSArray<UIImageView *> *iconViews = @[
        _backImageView,
        _refreshImageView,
        _forwardImageView,
        _homeImageView,
        _tabsImageView,
        _fullscreenImageView,
        _menuImageView
    ];
    for (UIImageView *imageView in iconViews) {
        [self.chromeEffectView.contentView addSubview:imageView];
    }

    [self applyVisualStyle];
}

- (UIImageView *)newIconViewNamed:(NSString *)imageName {
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:imageName]];
    imageView.userInteractionEnabled = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.alpha = 0.95;
    return imageView;
}

- (void)applyVisualStyle {
#if __has_include(<UIKit/UIGlassEffect.h>)
    if (@available(tvOS 26.0, *)) {
        self.effect = nil;

        UIGlassEffect *glassEffect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glassEffect.interactive = YES;
        glassEffect.tintColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        self.chromeEffectView.effect = glassEffect;
        self.chromeEffectView.alpha = 1.0;
        self.chromeContainerView.layer.shadowOpacity = 0.0;
        self.chromeContainerView.layer.shadowOffset = CGSizeZero;
        self.chromeContainerView.layer.shadowRadius = 0.0;
        self.chromeContainerView.layer.borderWidth = 0.0;
        return;
    }
#endif

    self.effect = nil;
    self.chromeEffectView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.chromeEffectView.alpha = 0.98;
    self.chromeContainerView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.chromeContainerView.layer.shadowOpacity = 0.28;
    self.chromeContainerView.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    self.chromeContainerView.layer.shadowRadius = 22.0;
    self.chromeContainerView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    self.chromeContainerView.layer.borderWidth = 1.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.contentView.frame = self.bounds;

    CGFloat width = MIN(CGRectGetWidth(self.bounds) - (kTopBarHorizontalInset * 2.0), kTopBarMaxWidth);
    width = MAX(width, 860.0);
    CGFloat originX = floor((CGRectGetWidth(self.bounds) - width) / 2.0);
    CGRect chromeFrame = CGRectMake(originX, kTopBarVerticalInset, width, kTopBarHeight);

    self.chromeContainerView.frame = chromeFrame;
    self.chromeContainerView.layer.cornerRadius = chromeFrame.size.height / 2.0;
    self.chromeContainerView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.chromeContainerView.bounds
                                                                           cornerRadius:self.chromeContainerView.layer.cornerRadius].CGPath;

    self.chromeEffectView.frame = self.chromeContainerView.bounds;
    self.chromeEffectView.layer.cornerRadius = self.chromeContainerView.layer.cornerRadius;

    CGFloat iconY = floor((CGRectGetHeight(chromeFrame) - kTopBarIconSize) / 2.0);
    CGFloat leftX = kTopBarLeadingPadding;
    NSArray<UIImageView *> *leftIcons = @[
        self.backImageView,
        self.refreshImageView,
        self.forwardImageView,
        self.homeImageView,
        self.tabsImageView
    ];
    for (UIImageView *imageView in leftIcons) {
        imageView.frame = CGRectMake(leftX, iconY, kTopBarIconSize, kTopBarIconSize);
        leftX += kTopBarIconSize + kTopBarIconSpacing;
    }

    CGFloat rightX = CGRectGetWidth(chromeFrame) - kTopBarTrailingPadding - kTopBarIconSize;
    self.menuImageView.frame = CGRectMake(rightX, iconY, kTopBarIconSize, kTopBarIconSize);

    rightX = CGRectGetMinX(self.menuImageView.frame) - kTopBarIconSpacing - kTopBarIconSize;
    self.fullscreenImageView.frame = CGRectMake(rightX, iconY, kTopBarIconSize, kTopBarIconSize);

    CGFloat spinnerSide = 34.0;
    rightX = CGRectGetMinX(self.fullscreenImageView.frame) - kTopBarSpinnerSpacing - spinnerSide;
    self.loadingSpinner.frame = CGRectMake(rightX,
                                           floor((CGRectGetHeight(chromeFrame) - spinnerSide) / 2.0),
                                           spinnerSide,
                                           spinnerSide);

    CGFloat labelOriginX = CGRectGetMaxX(self.tabsImageView.frame) + kTopBarLabelSpacing;
    CGFloat labelTrailingX = CGRectGetMinX(self.loadingSpinner.frame) - kTopBarLabelSpacing;
    CGFloat labelWidth = MAX(200.0, labelTrailingX - labelOriginX);
    self.URLLabel.frame = CGRectMake(labelOriginX,
                                     0.0,
                                     labelWidth,
                                     CGRectGetHeight(chromeFrame));
}

- (CGRect)interactiveFrameForView:(UIView *)view {
    return [self convertRect:view.bounds fromView:view];
}

@end
