#import "BrowserTabOverviewController.h"

#import "BrowserTabViewModel.h"
#import "BrowserTopBarView.h"
#import "BrowserViewModel.h"

static CGFloat const kTabOverviewPanelWidth = 1520.0;
static CGFloat const kTabOverviewPanelHeight = 760.0;
static CGFloat const kTabCardWidth = 260.0;
static CGFloat const kTabCardHeight = 240.0;
static CGFloat const kTabCardSpacing = 20.0;
static CGFloat const kTabCardGlowInset = 12.0;

@interface BrowserTabOverviewController ()

@property (nonatomic, weak) id<BrowserTabOverviewControllerHost> host;
@property (nonatomic) BrowserViewModel *viewModel;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, weak) BrowserTopBarView *topMenuView;
@property (nonatomic, weak) UIImageView *cursorView;
@property (nonatomic) UIVisualEffectView *overlayView;
@property (nonatomic) UIView *panelView;
@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIButton *addButton;
@property (nonatomic) NSMutableArray<UIView *> *cardViews;
@property (nonatomic, readwrite, getter=isVisible) BOOL visible;
@property (nonatomic) BOOL cursorModeBeforeShowing;

@end

@implementation BrowserTabOverviewController

- (instancetype)initWithHost:(id<BrowserTabOverviewControllerHost>)host
                   viewModel:(BrowserViewModel *)viewModel
                    rootView:(UIView *)rootView
                  topMenuView:(BrowserTopBarView *)topMenuView
                  cursorView:(UIImageView *)cursorView {
    self = [super init];
    if (self) {
        _host = host;
        _viewModel = viewModel;
        _rootView = rootView;
        _topMenuView = topMenuView;
        _cursorView = cursorView;
        _cardViews = [NSMutableArray array];
        [self setupIfNeeded];
    }
    return self;
}

- (void)setupIfNeeded {
    if (self.overlayView != nil) {
        return;
    }

    self.overlayView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.overlayView.frame = self.rootView.bounds;
    self.overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayView.hidden = YES;
    self.overlayView.alpha = 0.97;
    self.overlayView.userInteractionEnabled = NO;

    self.panelView = [[UIView alloc] initWithFrame:CGRectMake((CGRectGetWidth(self.rootView.bounds) - kTabOverviewPanelWidth) / 2.0,
                                                              160.0,
                                                              kTabOverviewPanelWidth,
                                                              kTabOverviewPanelHeight)];
    self.panelView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    self.panelView.layer.cornerRadius = 26.0;
    self.panelView.clipsToBounds = YES;
    self.panelView.userInteractionEnabled = NO;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(48.0, 32.0, 600.0, 46.0)];
    titleLabel.text = @"Tabs";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    [self.panelView addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(48.0, 80.0, 720.0, 34.0)];
    subtitleLabel.text = @"Switch tabs, close tabs, or open something new.";
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [self.panelView addSubview:subtitleLabel];

    self.addButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.addButton.frame = CGRectMake(CGRectGetWidth(self.panelView.bounds) - 112.0, 32.0, 64.0, 64.0);
    [self.addButton setImage:[UIImage imageNamed:@"plus"] forState:UIControlStateNormal];
    self.addButton.tag = 9001;
    self.addButton.userInteractionEnabled = NO;
    [self.panelView addSubview:self.addButton];

    CGFloat addTabLabelWidth = 180.0;
    CGFloat addTabLabelX = CGRectGetMidX(self.addButton.frame) - (addTabLabelWidth / 2.0);
    UILabel *addTabLabel = [[UILabel alloc] initWithFrame:CGRectMake(addTabLabelX, 98.0, addTabLabelWidth, 28.0)];
    addTabLabel.text = @"New Tab";
    addTabLabel.textAlignment = NSTextAlignmentCenter;
    addTabLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    addTabLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    [self.panelView addSubview:addTabLabel];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(48.0,
                                                                     148.0,
                                                                     kTabOverviewPanelWidth - 96.0,
                                                                     kTabOverviewPanelHeight - 196.0)];
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.alwaysBounceHorizontal = YES;
    self.scrollView.alwaysBounceVertical = NO;
    self.scrollView.userInteractionEnabled = NO;
    [self.panelView addSubview:self.scrollView];

    [self.overlayView.contentView addSubview:self.panelView];
    [self.rootView addSubview:self.overlayView];
}

- (void)reload {
    for (UIView *subview in self.scrollView.subviews) {
        [subview removeFromSuperview];
    }
    [self.cardViews removeAllObjects];

    CGFloat currentX = kTabCardGlowInset;
    CGFloat usableWidth = CGRectGetWidth(self.scrollView.bounds);
    for (NSInteger index = 0; index < self.viewModel.tabs.count; index++) {
        BrowserTabViewModel *tab = self.viewModel.tabs[index];
        UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(currentX, kTabCardGlowInset, kTabCardWidth, kTabCardHeight)];
        cardView.tag = 1000 + index;
        cardView.backgroundColor = UIColor.clearColor;
        cardView.layer.cornerRadius = 24.0;
        cardView.clipsToBounds = NO;
        if (index == self.viewModel.activeTabIndex) {
            cardView.layer.shadowColor = [UIColor colorWithRed:0.23 green:0.57 blue:1.0 alpha:1.0].CGColor;
            cardView.layer.shadowOffset = CGSizeZero;
            cardView.layer.shadowOpacity = 0.75;
            cardView.layer.shadowRadius = 9.0;
        } else {
            cardView.layer.shadowOpacity = 0.0;
        }

        UIView *cardContentView = [[UIView alloc] initWithFrame:cardView.bounds];
        cardContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cardContentView.backgroundColor = [UIColor colorWithWhite:index == self.viewModel.activeTabIndex ? 0.18 : 0.14 alpha:1.0];
        cardContentView.layer.cornerRadius = 24.0;
        cardContentView.clipsToBounds = YES;
        [cardView addSubview:cardContentView];

        UIImageView *thumbnailView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, kTabCardWidth, 150.0)];
        thumbnailView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        thumbnailView.clipsToBounds = YES;
        thumbnailView.image = tab.snapshotImage;
        [cardContentView addSubview:thumbnailView];

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 164.0, kTabCardWidth - 36.0, 26.0)];
        titleLabel.text = tab.title.length > 0 ? tab.title : @"New Tab";
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        [cardContentView addSubview:titleLabel];

        UILabel *urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 194.0, kTabCardWidth - 36.0, 32.0)];
        urlLabel.text = tab.URLString.length > 0 ? tab.URLString : @"Home page";
        urlLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        urlLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        urlLabel.numberOfLines = 2;
        [cardContentView addSubview:urlLabel];

        if (self.viewModel.tabs.count > 1) {
            UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
            closeButton.frame = CGRectMake(kTabCardWidth - 86.0, 14.0, 72.0, 30.0);
            closeButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.42];
            [closeButton setTitle:@"Close" forState:UIControlStateNormal];
            [closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            closeButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
            closeButton.layer.cornerRadius = 15.0;
            closeButton.tag = 2000 + index;
            [cardContentView addSubview:closeButton];
        }

        [self.scrollView addSubview:cardView];
        [self.cardViews addObject:cardView];
        currentX += kTabCardWidth + kTabCardSpacing;
    }

    CGFloat contentWidth = MAX(usableWidth, currentX - kTabCardSpacing + kTabCardGlowInset);
    self.scrollView.contentSize = CGSizeMake(contentWidth, kTabCardHeight + (kTabCardGlowInset * 2.0));
}

- (void)show {
    [self reload];
    self.cursorModeBeforeShowing = [self.host browserTabOverviewControllerCursorModeEnabled];
    self.visible = YES;
    self.overlayView.hidden = NO;
    [self.host browserTabOverviewControllerSetCursorModeEnabled:YES];
    [self.rootView bringSubviewToFront:self.overlayView];
    if (!self.topMenuView.isHidden) {
        [self.rootView bringSubviewToFront:self.topMenuView];
    }
    [self.rootView bringSubviewToFront:self.cursorView];
}

- (void)dismiss {
    if (!self.visible) {
        return;
    }

    self.visible = NO;
    self.overlayView.hidden = YES;
    [self.host browserTabOverviewControllerSetCursorModeEnabled:self.cursorModeBeforeShowing];
}

- (BOOL)containsPoint:(CGPoint)viewPoint {
    if (!self.visible) {
        return NO;
    }

    CGPoint overlayPoint = [self.rootView convertPoint:viewPoint toView:self.overlayView.contentView];
    return CGRectContainsPoint(self.panelView.frame, overlayPoint);
}

- (BOOL)handleSelectionAtPoint:(CGPoint)viewPoint {
    if (!self.visible) {
        return NO;
    }

    CGPoint overlayPoint = [self.rootView convertPoint:viewPoint toView:self.overlayView.contentView];
    if (!CGRectContainsPoint(self.panelView.frame, overlayPoint)) {
        [self dismiss];
        return YES;
    }

    CGPoint panelPoint = [self.rootView convertPoint:viewPoint toView:self.panelView];
    if (CGRectContainsPoint(self.addButton.frame, panelPoint)) {
        [self.host browserTabOverviewControllerCreateNewTabLoadingHomePage:YES];
        [self dismiss];
        return YES;
    }

    CGPoint scrollPoint = [self.rootView convertPoint:viewPoint toView:self.scrollView];
    for (UIView *cardView in self.cardViews) {
        if (!CGRectContainsPoint(cardView.frame, scrollPoint)) {
            continue;
        }

        NSInteger tabIndex = cardView.tag - 1000;
        UIView *closeButton = [cardView viewWithTag:2000 + tabIndex];
        if (closeButton != nil) {
            CGRect closeButtonFrame = [cardView convertRect:closeButton.frame toView:self.scrollView];
            if (CGRectContainsPoint(closeButtonFrame, scrollPoint)) {
                [self.host browserTabOverviewControllerCloseTabAtIndex:tabIndex];
                [self reload];
                return YES;
            }
        }

        [self.host browserTabOverviewControllerSwitchToTabAtIndex:tabIndex];
        [self dismiss];
        return YES;
    }

    return YES;
}

@end
