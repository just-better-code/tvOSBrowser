#import <UIKit/UIKit.h>
#import <string.h>
#import <objc/message.h>
#import <objc/runtime.h>

static void (*BrowserOriginalConfigurePlayerViewController)(id self, SEL _cmd, void *fullscreenInterface) = NULL;
static const ptrdiff_t kBrowserPlayerControllerHostOffset = 0x20;
static const ptrdiff_t kBrowserFullscreenInterfacePlayerLayerViewOffset = 0x58;
static const void *kBrowserFullscreenHackAssociatedViewsKey = &kBrowserFullscreenHackAssociatedViewsKey;

@interface BrowserFullscreenPlayerLayerView : UIView

@property (nonatomic, strong) id pixelBufferAttributes;
@property (nonatomic, strong) id playerController;
@property (nonatomic, copy) NSString *videoGravity;
@property (nonatomic, assign) UIEdgeInsets legibleContentInsets;

- (id)playerLayer;
- (void)transferVideoViewTo:(UIView *)view;
- (BOOL)avkit_isVisible;
- (UIWindow *)avkit_window;
- (CGRect)avkit_videoRectInWindow;

@end

@implementation BrowserFullscreenPlayerLayerView

- (id)playerLayer {
    return self;
}

- (void)transferVideoViewTo:(UIView *)view {
    if (view == nil || view == self) {
        return;
    }

    self.frame = view.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    if (self.superview != view) {
        [self removeFromSuperview];
        [view addSubview:self];
    }
}

- (BOOL)avkit_isVisible {
    if (self.hidden || self.alpha <= 0.0) {
        return NO;
    }

    return self.window != nil || self.superview != nil;
}

- (UIWindow *)avkit_window {
    return self.window;
}

- (CGRect)avkit_videoRectInWindow {
    UIWindow *window = self.window;
    if (window == nil) {
        return CGRectZero;
    }

    return [self convertRect:self.bounds toView:window];
}

@end

static UIView *BrowserViewForObject(id object) {
    if (object == nil || ![object respondsToSelector:@selector(view)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, @selector(view));
}

static void BrowserStoreRetainedHackView(id owner, UIView *view) {
    if (owner == nil || view == nil) {
        return;
    }

    NSMutableArray *views = objc_getAssociatedObject(owner, kBrowserFullscreenHackAssociatedViewsKey);
    if (views == nil) {
        views = [NSMutableArray array];
        objc_setAssociatedObject(owner, kBrowserFullscreenHackAssociatedViewsKey, views, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [views addObject:view];
}

static BOOL BrowserIsPotentialPlayerControllerHost(id object) {
    if (object == nil) {
        return NO;
    }

    return [object respondsToSelector:@selector(view)] &&
           [object respondsToSelector:NSSelectorFromString(@"videoGravity")] &&
           [object respondsToSelector:NSSelectorFromString(@"playerLayerView")] &&
           [object respondsToSelector:NSSelectorFromString(@"setPlayerLayerView:")] &&
	           [object respondsToSelector:NSSelectorFromString(@"pixelBufferAttributes")];
}

static id BrowserPlayerControllerHostFromKnownOffset(id fullscreenController) {
    if (fullscreenController == nil) {
        return nil;
    }

    uint8_t *bytes = (uint8_t *)(__bridge void *)fullscreenController;
    __unsafe_unretained id playerControllerHost = nil;
    memcpy(&playerControllerHost, bytes + kBrowserPlayerControllerHostOffset, sizeof(playerControllerHost));
    return playerControllerHost;
}

static UIView *BrowserPlayerLayerViewFromFullscreenInterface(void *fullscreenInterface) {
    if (fullscreenInterface == NULL) {
        return nil;
    }

    __unsafe_unretained UIView *playerLayerView = nil;
    memcpy(&playerLayerView,
           ((uint8_t *)fullscreenInterface) + kBrowserFullscreenInterfacePlayerLayerViewOffset,
           sizeof(playerLayerView));
    return playerLayerView;
}

static void BrowserSetPlayerLayerViewOnFullscreenInterface(void *fullscreenInterface, UIView *playerLayerView) {
    if (fullscreenInterface == NULL || playerLayerView == nil) {
        return;
    }

    __unsafe_unretained UIView *unretainedPlayerLayerView = playerLayerView;
    memcpy(((uint8_t *)fullscreenInterface) + kBrowserFullscreenInterfacePlayerLayerViewOffset,
           &unretainedPlayerLayerView,
           sizeof(unretainedPlayerLayerView));
}

static id BrowserFindPlayerControllerHost(id fullscreenController) {
    for (Class currentClass = [fullscreenController class];
         currentClass != Nil && currentClass != [NSObject class];
         currentClass = class_getSuperclass(currentClass)) {
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(currentClass, &ivarCount);
        for (unsigned int index = 0; index < ivarCount; index++) {
            Ivar ivar = ivars[index];
            const char *typeEncoding = ivar_getTypeEncoding(ivar);
            if (typeEncoding == NULL || typeEncoding[0] != '@') {
                continue;
            }

            id value = object_getIvar(fullscreenController, ivar);
            if (BrowserIsPotentialPlayerControllerHost(value)) {
                free(ivars);
                return value;
            }
        }
        free(ivars);
    }
    return nil;
}

static void BrowserEnsureFullscreenContainerSubview(id fullscreenController) {
    id playerControllerHost = BrowserPlayerControllerHostFromKnownOffset(fullscreenController);
    if (!BrowserIsPotentialPlayerControllerHost(playerControllerHost)) {
        playerControllerHost = BrowserFindPlayerControllerHost(fullscreenController);
    }

    UIView *playerControllerView = BrowserViewForObject(playerControllerHost);
    if (playerControllerView == nil || playerControllerView.subviews.count > 0) {
        return;
    }

    UIView *containerView = [[UIView alloc] initWithFrame:playerControllerView.bounds];
    containerView.backgroundColor = UIColor.clearColor;
    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [playerControllerView addSubview:containerView];
    BrowserStoreRetainedHackView(fullscreenController, containerView);
}

static void BrowserEnsurePlayerLayerView(void *fullscreenInterface, id fullscreenController) {
    if (BrowserPlayerLayerViewFromFullscreenInterface(fullscreenInterface) != nil) {
        return;
    }

    id playerControllerHost = BrowserPlayerControllerHostFromKnownOffset(fullscreenController);
    if (!BrowserIsPotentialPlayerControllerHost(playerControllerHost)) {
        playerControllerHost = BrowserFindPlayerControllerHost(fullscreenController);
    }

    UIView *playerControllerView = BrowserViewForObject(playerControllerHost);
    CGRect frame = playerControllerView != nil ? playerControllerView.bounds : CGRectZero;
    BrowserFullscreenPlayerLayerView *playerLayerView = [[BrowserFullscreenPlayerLayerView alloc] initWithFrame:frame];
    playerLayerView.backgroundColor = UIColor.clearColor;
    playerLayerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    BrowserSetPlayerLayerViewOnFullscreenInterface(fullscreenInterface, playerLayerView);
    BrowserStoreRetainedHackView(fullscreenController, playerLayerView);
}

static void BrowserConfigurePlayerViewControllerReplacement(id self, SEL _cmd, void *fullscreenInterface) {
    BrowserEnsurePlayerLayerView(fullscreenInterface, self);
    BrowserEnsureFullscreenContainerSubview(self);

    if (BrowserOriginalConfigurePlayerViewController != NULL) {
        BrowserOriginalConfigurePlayerViewController(self, _cmd, fullscreenInterface);
    }
}

@interface BrowserFullscreenSubviewHack : NSObject
@end

@implementation BrowserFullscreenSubviewHack

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class playerViewControllerClass = objc_getClass("WebAVPlayerViewController");
        if (playerViewControllerClass == Nil) {
            return;
        }

        SEL selector = NSSelectorFromString(@"configurePlayerViewControllerWithFullscreenInterface:");
        Method method = class_getInstanceMethod(playerViewControllerClass, selector);
        if (method == NULL) {
            return;
        }

        BrowserOriginalConfigurePlayerViewController = (void (*)(id, SEL, void *))method_getImplementation(method);
        method_setImplementation(method, (IMP)BrowserConfigurePlayerViewControllerReplacement);
    });
}

@end
