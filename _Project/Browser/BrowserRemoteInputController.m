#import "BrowserRemoteInputController.h"

static UIImage *BrowserDefaultCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Cursor"];
    });
    return image;
}

static UIImage *BrowserPointerCursor(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = [UIImage imageNamed:@"Pointer"];
    });
    return image;
}

static NSTimeInterval const kBrowserCursorIdleDelay = 3.0;
static CGFloat const kBrowserMagnifierDiameter = 384.0;

static NSString *BrowserPressTypeString(UIPressType type) {
    switch (type) {
        case UIPressTypeMenu: return @"Menu";
        case UIPressTypePlayPause: return @"PlayPause";
        case UIPressTypeSelect: return @"Select";
        case UIPressTypeUpArrow: return @"Up";
        case UIPressTypeDownArrow: return @"Down";
        case UIPressTypeLeftArrow: return @"Left";
        case UIPressTypeRightArrow: return @"Right";
        default: return [NSString stringWithFormat:@"Type-%ld", (long)type];
    }
}

static NSString *BrowserPressPhaseString(UIPressPhase phase) {
    switch (phase) {
        case UIPressPhaseBegan: return @"Began";
        case UIPressPhaseChanged: return @"Changed";
        case UIPressPhaseStationary: return @"Stationary";
        case UIPressPhaseEnded: return @"Ended";
        case UIPressPhaseCancelled: return @"Cancelled";
        default: return [NSString stringWithFormat:@"Phase-%ld", (long)phase];
    }
}

@interface BrowserRemoteInputController ()

@property (nonatomic, weak) id<BrowserRemoteInputControllerHost> host;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, readwrite) UIImageView *cursorView;
@property (nonatomic, readwrite) UIPanGestureRecognizer *manualScrollPanRecognizer;
@property (nonatomic, readwrite, getter=isCursorModeEnabled) BOOL cursorModeEnabled;
@property (nonatomic) CGPoint lastTouchLocation;
@property (nonatomic) CADisplayLink *manualScrollDisplayLink;
@property (nonatomic) CGPoint manualScrollVelocity;
@property (nonatomic) CFTimeInterval manualScrollLastTimestamp;
@property (nonatomic) CFTimeInterval manualScrollLastMovementTimestamp;
@property (nonatomic) CFTimeInterval lastDirectSelectPressTimestamp;
@property (nonatomic) BOOL awaitingSecondHorizontalPress;
@property (nonatomic) UIPressType pendingHorizontalPressType;
@property (nonatomic) CFTimeInterval lastHorizontalPressTimestamp;
@property (nonatomic) CFTimeInterval lastTabOverviewUpPressTimestamp;
@property (nonatomic) CFTimeInterval lastPlayPausePressTimestamp;
@property (nonatomic) BOOL awaitingSecondPlayPausePress;
@property (nonatomic) BOOL primaryActionInProgress;
@property (nonatomic) BOOL hoverRequestInFlight;
@property (nonatomic) CGPoint latestHoverPoint;
@property (nonatomic) NSUInteger hoverGeneration;
@property (nonatomic) NSUInteger cursorIdleGeneration;
@property (nonatomic) BOOL cursorIdleHidden;
@property (nonatomic) UIView *magnifierView;
@property (nonatomic) UIImageView *magnifierImageView;
@property (nonatomic) BOOL magnifierCaptureInFlight;
@property (nonatomic) CFTimeInterval lastMagnifierCaptureTimestamp;
@property (nonatomic) CGPoint latestMagnifierPoint;
@property (nonatomic) NSUInteger magnifierGeneration;
@property (nonatomic) NSTimer *magnifierRefreshTimer;

@end

@implementation BrowserRemoteInputController

- (instancetype)initWithHost:(id<BrowserRemoteInputControllerHost>)host
                    rootView:(UIView *)rootView {
    self = [super init];
    if (self) {
        _host = host;
        _rootView = rootView;
        _lastTouchLocation = CGPointMake(-1, -1);
        _cursorModeEnabled = YES;

        _cursorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
        _cursorView.center = CGPointMake(CGRectGetMidX([UIScreen mainScreen].bounds), CGRectGetMidY([UIScreen mainScreen].bounds));
        _cursorView.image = BrowserDefaultCursor();

        _magnifierView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, kBrowserMagnifierDiameter, kBrowserMagnifierDiameter)];
        _magnifierView.hidden = YES;
        _magnifierView.userInteractionEnabled = NO;
        _magnifierView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
        _magnifierView.layer.cornerRadius = kBrowserMagnifierDiameter / 2.0;
        _magnifierView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.88].CGColor;
        _magnifierView.layer.borderWidth = 5.0;
        _magnifierView.layer.shadowColor = UIColor.blackColor.CGColor;
        _magnifierView.layer.shadowOpacity = 0.6;
        _magnifierView.layer.shadowRadius = 20.0;
        _magnifierView.layer.shadowOffset = CGSizeMake(0.0, 8.0);
        _magnifierImageView = [[UIImageView alloc] initWithFrame:CGRectInset(_magnifierView.bounds, 5.0, 5.0)];
        _magnifierImageView.contentMode = UIViewContentModeScaleAspectFill;
        _magnifierImageView.clipsToBounds = YES;
        _magnifierImageView.layer.cornerRadius = (kBrowserMagnifierDiameter - 10.0) / 2.0;
        [_magnifierView addSubview:_magnifierImageView];
        [rootView addSubview:_magnifierView];
        [rootView bringSubviewToFront:_cursorView];

        _manualScrollPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleManualScrollPan:)];
        _manualScrollPanRecognizer.allowedTouchTypes = @[ @(UITouchTypeIndirect) ];
        _manualScrollPanRecognizer.cancelsTouchesInView = NO;
        _manualScrollPanRecognizer.enabled = NO;
        [rootView addGestureRecognizer:_manualScrollPanRecognizer];
    }
    return self;
}

- (void)setMagnifierEnabled:(BOOL)magnifierEnabled {
    if (_magnifierEnabled == magnifierEnabled) {
        return;
    }
    _magnifierEnabled = magnifierEnabled;
    self.magnifierGeneration += 1;
    [self.magnifierRefreshTimer invalidate];
    self.magnifierRefreshTimer = nil;
    self.magnifierImageView.image = nil;
    self.magnifierView.hidden = YES;
    if (magnifierEnabled) {
        [self noteCursorActivity];
        [self updateMagnifierAtPoint:self.cursorView.frame.origin];
        __weak typeof(self) weakSelf = self;
        self.magnifierRefreshTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf != nil && !strongSelf.cursorIdleHidden) {
                [strongSelf updateMagnifierAtPoint:strongSelf.cursorView.frame.origin];
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.magnifierRefreshTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)updateMagnifierAtPoint:(CGPoint)point {
    if (!self.magnifierEnabled || !self.cursorModeEnabled || self.cursorIdleHidden ||
        [self.host browserRemoteInputControllerPresentedViewController] != nil ||
        [self.host browserRemoteInputControllerTabOverviewVisible] ||
        [self.host browserRemoteInputControllerTopBarFocusActive]) {
        self.magnifierView.hidden = YES;
        return;
    }
    CGFloat viewWidth = CGRectGetWidth(self.rootView.bounds);
    CGFloat viewHeight = CGRectGetHeight(self.rootView.bounds);
    CGFloat x = MIN(MAX(16.0, point.x - kBrowserMagnifierDiameter / 2.0),
                    MAX(16.0, viewWidth - kBrowserMagnifierDiameter - 16.0));
    CGFloat y = MIN(MAX(16.0, point.y - kBrowserMagnifierDiameter / 2.0),
                    MAX(16.0, viewHeight - kBrowserMagnifierDiameter - 16.0));
    self.magnifierView.frame = CGRectMake(x, y,
                                           kBrowserMagnifierDiameter, kBrowserMagnifierDiameter);
    [self.rootView bringSubviewToFront:self.magnifierView];
    [self.rootView bringSubviewToFront:self.cursorView];
    self.latestMagnifierPoint = point;
    CFTimeInterval now = CACurrentMediaTime();
    if (self.magnifierCaptureInFlight || now - self.lastMagnifierCaptureTimestamp < 0.12) {
        return;
    }
    self.magnifierCaptureInFlight = YES;
    self.lastMagnifierCaptureTimestamp = now;
    NSUInteger generation = self.magnifierGeneration;
    __weak typeof(self) weakSelf = self;
    [self.host browserRemoteInputControllerCaptureMagnifierAtPoint:point completion:^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf.magnifierCaptureInFlight = NO;
        if (generation != strongSelf.magnifierGeneration || !strongSelf.magnifierEnabled) { return; }
        strongSelf.magnifierImageView.image = image;
        strongSelf.magnifierView.hidden = image == nil || strongSelf.cursorIdleHidden ||
            [strongSelf.host browserRemoteInputControllerPresentedViewController] != nil ||
            [strongSelf.host browserRemoteInputControllerTabOverviewVisible] ||
            [strongSelf.host browserRemoteInputControllerTopBarFocusActive];
        if (!CGPointEqualToPoint(point, strongSelf.latestMagnifierPoint)) {
            [strongSelf updateMagnifierAtPoint:strongSelf.latestMagnifierPoint];
        }
    }];
}

- (void)setCursorModeEnabled:(BOOL)cursorModeEnabled {
    BOOL wasCursorModeEnabled = self.cursorModeEnabled;
    _cursorModeEnabled = cursorModeEnabled;
    self.hoverGeneration += 1;
    self.lastTouchLocation = CGPointMake(-1, -1);
    [self stopManualScrollInertia];
    [self refreshInteractionState];
    if (cursorModeEnabled) {
        [self noteCursorActivity];
    } else {
        self.cursorIdleGeneration += 1;
    }
    if (!wasCursorModeEnabled && cursorModeEnabled) {
        [self.host browserRemoteInputControllerPersistSession];
    }
}

- (void)noteCursorActivity {
    if (!self.cursorModeEnabled) {
        return;
    }
    self.cursorIdleHidden = NO;
    self.cursorView.hidden = [self.host browserRemoteInputControllerTabOverviewVisible] ||
        [self.host browserRemoteInputControllerTopBarFocusActive];
    self.magnifierView.hidden = !self.magnifierEnabled || self.magnifierImageView.image == nil ||
        self.cursorView.hidden || [self.host browserRemoteInputControllerPresentedViewController] != nil;
    if (self.cursorView.alpha < 1.0) {
        [UIView animateWithDuration:0.15 animations:^{
            self.cursorView.alpha = 1.0;
        }];
    }

    NSUInteger generation = ++self.cursorIdleGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBrowserCursorIdleDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || generation != strongSelf.cursorIdleGeneration || !strongSelf.cursorModeEnabled) {
            return;
        }
        strongSelf.cursorIdleHidden = YES;
        strongSelf.magnifierView.hidden = YES;
        [UIView animateWithDuration:0.25 animations:^{
            strongSelf.cursorView.alpha = 0.0;
        } completion:^(__unused BOOL finished) {
            if (generation == strongSelf.cursorIdleGeneration && strongSelf.cursorIdleHidden) {
                strongSelf.cursorView.hidden = YES;
            }
        }];
    });
}

- (void)requestHoverStateAtPoint:(CGPoint)point {
    self.latestHoverPoint = point;
    if (self.hoverRequestInFlight) {
        return;
    }

    self.hoverRequestInFlight = YES;
    NSUInteger generation = self.hoverGeneration;
    __weak typeof(self) weakSelf = self;
    [self.host browserRemoteInputControllerHoverStateAtCursorPoint:point completion:^(BOOL isInteractive) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.hoverRequestInFlight = NO;
        if (!strongSelf.cursorModeEnabled ||
            [strongSelf.host browserRemoteInputControllerTopBarFocusActive] ||
            [strongSelf.host browserRemoteInputControllerTabOverviewVisible]) {
            return;
        }
        if (generation != strongSelf.hoverGeneration) {
            [strongSelf requestHoverStateAtPoint:strongSelf.latestHoverPoint];
            return;
        }
        if (!CGPointEqualToPoint(strongSelf.latestHoverPoint, point)) {
            [strongSelf requestHoverStateAtPoint:strongSelf.latestHoverPoint];
            return;
        }
        strongSelf.cursorView.image = isInteractive ? BrowserPointerCursor() : BrowserDefaultCursor();
    }];
}

- (void)refreshInteractionState {
    UIScrollView *scrollView = [self.host browserRemoteInputControllerActiveScrollView];
    BOOL topBarFocusActive = [self.host browserRemoteInputControllerTopBarFocusActive];
    BOOL shouldAllowWebInteraction = !self.cursorModeEnabled &&
        ![self.host browserRemoteInputControllerTabOverviewVisible] &&
        !topBarFocusActive;
    scrollView.scrollEnabled = shouldAllowWebInteraction;
    self.manualScrollPanRecognizer.enabled = shouldAllowWebInteraction;
    [self.host browserRemoteInputControllerSetWebInteractionEnabled:shouldAllowWebInteraction];
    self.cursorView.hidden = !self.cursorModeEnabled ||
        [self.host browserRemoteInputControllerTabOverviewVisible] ||
        topBarFocusActive || self.cursorIdleHidden;
    self.magnifierView.hidden = !self.magnifierEnabled || self.magnifierImageView.image == nil ||
        self.cursorView.hidden || [self.host browserRemoteInputControllerPresentedViewController] != nil;
    if (self.cursorModeEnabled && self.cursorIdleGeneration == 0) {
        [self noteCursorActivity];
    }
}

- (BOOL)applyManualScrollDelta:(CGPoint)delta {
    UIScrollView *scrollView = [self.host browserRemoteInputControllerActiveScrollView];
    if (scrollView == nil) {
        return NO;
    }

    CGPoint contentOffset = scrollView.contentOffset;
    CGFloat maxOffsetX = MAX(0.0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
    CGFloat maxOffsetY = MAX(0.0, scrollView.contentSize.height - CGRectGetHeight(scrollView.bounds));
    CGFloat nextOffsetX = MIN(MAX(contentOffset.x + delta.x, 0.0), maxOffsetX);
    CGFloat nextOffsetY = MIN(MAX(contentOffset.y + delta.y, 0.0), maxOffsetY);
    CGPoint nextOffset = CGPointMake(nextOffsetX, nextOffsetY);
    [scrollView setContentOffset:nextOffset animated:NO];
    return !CGPointEqualToPoint(contentOffset, nextOffset);
}

- (void)stopManualScrollInertia {
    [self.manualScrollDisplayLink invalidate];
    self.manualScrollDisplayLink = nil;
    self.manualScrollVelocity = CGPointZero;
    self.manualScrollLastTimestamp = 0;
    self.manualScrollLastMovementTimestamp = 0;
}

- (void)startManualScrollInertiaWithVelocity:(CGPoint)velocity {
    [self stopManualScrollInertia];
    if (fabs(velocity.x) < 25.0 && fabs(velocity.y) < 25.0) {
        return;
    }

    self.manualScrollVelocity = velocity;
    self.manualScrollLastTimestamp = 0;
    self.manualScrollDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleManualScrollDisplayLink:)];
    [self.manualScrollDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)handleManualScrollDisplayLink:(CADisplayLink *)displayLink {
    if (self.cursorModeEnabled ||
        [self.host browserRemoteInputControllerTabOverviewVisible] ||
        [self.host browserRemoteInputControllerTopBarFocusActive]) {
        [self stopManualScrollInertia];
        return;
    }

    if (self.manualScrollLastTimestamp <= 0) {
        self.manualScrollLastTimestamp = displayLink.timestamp;
        return;
    }

    CFTimeInterval deltaTime = displayLink.timestamp - self.manualScrollLastTimestamp;
    self.manualScrollLastTimestamp = displayLink.timestamp;

    CGPoint step = CGPointMake(self.manualScrollVelocity.x * deltaTime, self.manualScrollVelocity.y * deltaTime);
    BOOL didMove = [self applyManualScrollDelta:step];

    CGFloat decay = pow(0.92, deltaTime * 60.0);
    self.manualScrollVelocity = CGPointMake(self.manualScrollVelocity.x * decay, self.manualScrollVelocity.y * decay);

    if (!didMove ||
        (fabs(self.manualScrollVelocity.x) < 10.0 && fabs(self.manualScrollVelocity.y) < 10.0)) {
        [self stopManualScrollInertia];
        [self.host browserRemoteInputControllerPersistSession];
    }
}

- (void)handleGlobalSelectPressEndedNotification {
    if ([self.host browserRemoteInputControllerPresentedViewController] != nil) {
        return;
    }

    if ([self.host browserRemoteInputControllerTopBarFocusActive]) {
        return;
    }

    if ((CACurrentMediaTime() - self.lastDirectSelectPressTimestamp) < 0.15) {
        return;
    }

    [self handleSelectPressEnded];
}

- (void)handleSelectPressEnded {
    self.lastTouchLocation = CGPointMake(-1, -1);

    if ([self.host browserRemoteInputControllerPresentedViewController] != nil) {
        return;
    }

    if ([self.host browserRemoteInputControllerTabOverviewVisible]) {
        [self.host browserRemoteInputControllerHandleTabOverviewSelectionAtPoint:self.cursorView.frame.origin];
        return;
    }

    [self noteCursorActivity];

    if ([self.host browserRemoteInputControllerNewTabVisible]) {
        [self.host browserRemoteInputControllerActivateNewTabSelection];
        return;
    }

    if (self.primaryActionInProgress) {
        return;
    }
    self.primaryActionInProgress = YES;
    [self.host browserRemoteInputControllerHandlePrimaryAction];
    self.primaryActionInProgress = NO;
}

- (void)handleDeferredHorizontalPressAction {
    if (!self.awaitingSecondHorizontalPress) {
        return;
    }
    self.awaitingSecondHorizontalPress = NO;
    if ([self.host browserRemoteInputControllerPresentedViewController] != nil ||
        [self.host browserRemoteInputControllerTopBarFocusActive] ||
        [self.host browserRemoteInputControllerTabOverviewVisible]) {
        return;
    }
    if (self.pendingHorizontalPressType == UIPressTypeLeftArrow) {
        [self.host browserRemoteInputControllerHandleHistoryBackPress];
    } else {
        [self.host browserRemoteInputControllerHandleHistoryForwardPress];
    }
}

- (void)handleDeferredPlayPausePressAction {
    if (!self.awaitingSecondPlayPausePress) { return; }
    self.awaitingSecondPlayPausePress = NO;
    if ([self.host browserRemoteInputControllerPresentedViewController] == nil &&
        ![self.host browserRemoteInputControllerTopBarFocusActive]) {
        [self.host browserRemoteInputControllerHandlePlayPausePress];
    }
}

- (void)handlePlayPausePressEnded {
    CFTimeInterval now = CACurrentMediaTime();
    if (self.awaitingSecondPlayPausePress &&
        now - self.lastPlayPausePressTimestamp < 0.35) {
        self.awaitingSecondPlayPausePress = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                  selector:@selector(handleDeferredPlayPausePressAction)
                                                    object:nil];
        [self.host browserRemoteInputControllerToggleMagnifier];
        return;
    }
    self.awaitingSecondPlayPausePress = YES;
    self.lastPlayPausePressTimestamp = now;
    [self performSelector:@selector(handleDeferredPlayPausePressAction) withObject:nil afterDelay:0.35];
}

- (void)handleHorizontalPressEnded:(UIPressType)pressType {
    CFTimeInterval now = CACurrentMediaTime();
    if (self.awaitingSecondHorizontalPress &&
        self.pendingHorizontalPressType == pressType &&
        (now - self.lastHorizontalPressTimestamp) < 0.35) {
        self.awaitingSecondHorizontalPress = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredHorizontalPressAction) object:nil];
        if (pressType == UIPressTypeLeftArrow) {
            [self.host browserRemoteInputControllerHandleTabOverviewPress];
        } else {
            [self.host browserRemoteInputControllerHandleAdvancedMenuPress];
        }
        return;
    }

    if (self.awaitingSecondHorizontalPress) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredHorizontalPressAction) object:nil];
        [self handleDeferredHorizontalPressAction];
    }

    self.awaitingSecondHorizontalPress = YES;
    self.pendingHorizontalPressType = pressType;
    self.lastHorizontalPressTimestamp = now;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredHorizontalPressAction) object:nil];
    [self performSelector:@selector(handleDeferredHorizontalPressAction) withObject:nil afterDelay:0.35];
}

- (void)handleVerticalPressEnded:(UIPressType)pressType {
    if ([self.host browserRemoteInputControllerPresentedViewController] != nil ||
        [self.host browserRemoteInputControllerTopBarFocusActive] ||
        [self.host browserRemoteInputControllerTabOverviewVisible]) {
        return;
    }

    CGFloat direction = pressType == UIPressTypeDownArrow ? 1.0 : -1.0;
    UIScrollView *scrollView = [self.host browserRemoteInputControllerActiveScrollView];
    CGFloat pageStep = scrollView == nil ? 150.0 : MAX(120.0, CGRectGetHeight(scrollView.bounds) * 0.275);
    [self stopManualScrollInertia];
    [self applyManualScrollDelta:CGPointMake(0, direction * pageStep)];
    [self.host browserRemoteInputControllerPersistSession];
}

- (void)handleManualScrollPan:(UIPanGestureRecognizer *)gestureRecognizer {
    if (self.cursorModeEnabled ||
        [self.host browserRemoteInputControllerTabOverviewVisible] ||
        [self.host browserRemoteInputControllerTopBarFocusActive]) {
        return;
    }

    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [self stopManualScrollInertia];
    }

    CGPoint translation = [gestureRecognizer translationInView:self.rootView];
    if (!CGPointEqualToPoint(translation, CGPointZero)) {
        [self applyManualScrollDelta:CGPointMake(-translation.x, -translation.y)];
        [gestureRecognizer setTranslation:CGPointZero inView:self.rootView];
        self.manualScrollLastMovementTimestamp = CACurrentMediaTime();
    }

    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        CFTimeInterval timeSinceLastMovement = CACurrentMediaTime() - self.manualScrollLastMovementTimestamp;
        CGPoint velocity = [gestureRecognizer velocityInView:self.rootView];
        if (timeSinceLastMovement < 0.08) {
            [self startManualScrollInertiaWithVelocity:CGPointMake(-velocity.x, -velocity.y)];
        } else {
            [self stopManualScrollInertia];
        }
        [self.host browserRemoteInputControllerPersistSession];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateCancelled ||
               gestureRecognizer.state == UIGestureRecognizerStateFailed) {
        [self stopManualScrollInertia];
        [self.host browserRemoteInputControllerPersistSession];
    }
}

- (void)handlePressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    UIPress *press = presses.anyObject;
    if (press != nil && (press.type == UIPressTypeMenu || press.type == UIPressTypePlayPause || press.type == UIPressTypeSelect)) {
        NSLog(@"[InputTrace][Root] pressesBegan type=%@ phase=%@ presented=%@",
              BrowserPressTypeString(press.type),
              BrowserPressPhaseString(press.phase),
              [self.host browserRemoteInputControllerPresentedViewController] == nil ? @"(nil)" : NSStringFromClass([[self.host browserRemoteInputControllerPresentedViewController] class]));
    }
    (void)event;
}

- (BOOL)handlePressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    (void)event;
    UIPress *press = presses.anyObject;
    if (press == nil) {
        return NO;
    }
    if (self.awaitingSecondPlayPausePress && press.type != UIPressTypePlayPause) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                  selector:@selector(handleDeferredPlayPausePressAction)
                                                    object:nil];
        [self handleDeferredPlayPausePressAction];
    }
    if (![self.host browserRemoteInputControllerTabOverviewVisible] || press.type != UIPressTypeUpArrow) {
        self.lastTabOverviewUpPressTimestamp = 0.0;
    }
    if (self.awaitingSecondHorizontalPress &&
        press.type != UIPressTypeLeftArrow && press.type != UIPressTypeRightArrow) {
        self.awaitingSecondHorizontalPress = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredHorizontalPressAction) object:nil];
    }
    if (press.type == UIPressTypeMenu || press.type == UIPressTypePlayPause || press.type == UIPressTypeSelect) {
        NSLog(@"[InputTrace][Root] pressesEnded type=%@ phase=%@ presented=%@ tabOverview=%@",
              BrowserPressTypeString(press.type),
              BrowserPressPhaseString(press.phase),
              [self.host browserRemoteInputControllerPresentedViewController] == nil ? @"(nil)" : NSStringFromClass([[self.host browserRemoteInputControllerPresentedViewController] class]),
              [self.host browserRemoteInputControllerTabOverviewVisible] ? @"YES" : @"NO");
    }

    if ([self.host browserRemoteInputControllerTopBarFocusActive]) {
        if (press.type == UIPressTypeMenu || press.type == UIPressTypeDownArrow) {
            [self.host browserRemoteInputControllerDeactivateTopBarFocus];
            return YES;
        }
        if (press.type == UIPressTypePlayPause) {
            return YES;
        }
        if (press.type == UIPressTypeSelect ||
            press.type == UIPressTypeLeftArrow ||
            press.type == UIPressTypeRightArrow ||
            press.type == UIPressTypeUpArrow) {
            return NO;
        }
    }

    UIViewController *presentedViewController = [self.host browserRemoteInputControllerPresentedViewController];
    if (presentedViewController != nil && ![presentedViewController isKindOfClass:[UIAlertController class]]) {
        if ([self.host browserRemoteInputControllerTabOverviewVisible]) {
            if (press.type == UIPressTypeUpArrow) {
                CFTimeInterval now = CACurrentMediaTime();
                if (self.lastTabOverviewUpPressTimestamp > 0.0 &&
                    (now - self.lastTabOverviewUpPressTimestamp) < 0.42) {
                    self.lastTabOverviewUpPressTimestamp = 0.0;
                    [self.host browserRemoteInputControllerHandleTabOverviewAlternateAction];
                } else {
                    self.lastTabOverviewUpPressTimestamp = now;
                }
                return YES;
            }
            if (press.type == UIPressTypeMenu) {
                [self.host browserRemoteInputControllerDismissTabOverview];
                return YES;
            }
            if (press.type == UIPressTypePlayPause) {
                [self.host browserRemoteInputControllerHandleTabOverviewAlternateAction];
                return YES;
            }
            return NO;
        }
        if (press.type == UIPressTypeMenu) {
            [presentedViewController dismissViewControllerAnimated:YES completion:nil];
            return YES;
        }
        return YES;
    }

    if ([self.host browserRemoteInputControllerNewTabVisible]) {
        NSString *direction = nil;
        switch (press.type) {
            case UIPressTypeUpArrow: direction = @"up"; break;
            case UIPressTypeDownArrow: direction = @"down"; break;
            case UIPressTypeLeftArrow: direction = @"left"; break;
            case UIPressTypeRightArrow: direction = @"right"; break;
            default: break;
        }
        if (direction != nil) {
            self.awaitingSecondHorizontalPress = NO;
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(handleDeferredHorizontalPressAction) object:nil];
            [self.host browserRemoteInputControllerNavigateNewTabInDirection:direction];
            return YES;
        }
    }

    if (press.type == UIPressTypeSelect) {
        self.lastDirectSelectPressTimestamp = CACurrentMediaTime();
        [self handleSelectPressEnded];
        return YES;
    }

    if ([self.host browserRemoteInputControllerTabOverviewVisible]) {
        if (press.type == UIPressTypeMenu || press.type == UIPressTypePlayPause) {
            [self.host browserRemoteInputControllerDismissTabOverview];
            return YES;
        }
        if (press.type == UIPressTypeSelect) {
            [self.host browserRemoteInputControllerHandleTabOverviewSelectionAtPoint:self.cursorView.frame.origin];
            return YES;
        }
    }

    if (press.type == UIPressTypeMenu) {
        [self.host browserRemoteInputControllerHandleMenuPress];
        return YES;
    }
    if (press.type == UIPressTypePlayPause) {
        [self handlePlayPausePressEnded];
        return YES;
    }
    if (press.type == UIPressTypeRightArrow) {
        [self handleHorizontalPressEnded:press.type];
        return YES;
    }
    if (press.type == UIPressTypeLeftArrow) {
        [self handleHorizontalPressEnded:press.type];
        return YES;
    }
    if (press.type == UIPressTypeUpArrow || press.type == UIPressTypeDownArrow) {
        [self handleVerticalPressEnded:press.type];
        return YES;
    }
    return NO;
}

- (BOOL)handleTouchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    if ([self.host browserRemoteInputControllerTopBarFocusActive]) {
        return NO;
    }
    if ([self.host browserRemoteInputControllerTabOverviewVisible]) {
        return NO;
    }
    if (!self.cursorModeEnabled) {
        return NO;
    }
    self.lastTouchLocation = CGPointMake(-1, -1);
    return YES;
}

- (BOOL)handleTouchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if ([self.host browserRemoteInputControllerTopBarFocusActive]) {
        return NO;
    }
    if ([self.host browserRemoteInputControllerTabOverviewVisible]) {
        return NO;
    }
    if (!self.cursorModeEnabled) {
        return NO;
    }

    [self noteCursorActivity];

    for (UITouch *touch in touches) {
        UIScrollView *activeScrollView = [self.host browserRemoteInputControllerActiveScrollView];
        UIView *targetView = activeScrollView ?: self.rootView;
        CGPoint location = [touch locationInView:targetView];

        if (self.lastTouchLocation.x == -1 && self.lastTouchLocation.y == -1) {
            self.lastTouchLocation = location;
        } else {
            CGFloat xDiff = location.x - self.lastTouchLocation.x;
            CGFloat yDiff = location.y - self.lastTouchLocation.y;
            CGFloat cursorSensitivity = self.magnifierEnabled ? 0.25 : 1.0;
            xDiff *= cursorSensitivity;
            yDiff *= cursorSensitivity;
            CGRect rect = self.cursorView.frame;

            if (rect.origin.x + xDiff >= 0 && rect.origin.x + xDiff <= 1920) {
                rect.origin.x += xDiff;
            }
            if (rect.origin.y + yDiff >= 0 && rect.origin.y + yDiff <= 1080) {
                rect.origin.y += yDiff;
            }
            self.cursorView.frame = rect;
            self.lastTouchLocation = location;
        }

        self.cursorView.image = BrowserDefaultCursor();
        if ([self.host browserRemoteInputControllerTabOverviewVisible]) {
            if ([self.host browserRemoteInputControllerTabOverviewContainsPoint:self.cursorView.frame.origin]) {
                self.cursorView.image = BrowserPointerCursor();
            }
            break;
        }
        if (self.cursorModeEnabled) {
            [self requestHoverStateAtPoint:self.cursorView.frame.origin];
            [self updateMagnifierAtPoint:self.cursorView.frame.origin];
        }
        break;
    }

    return YES;
}

- (void)handleTouchesEnded {
    self.lastTouchLocation = CGPointMake(-1, -1);
}

@end
