#import <UIKit/UIKit.h>
#import "BrowserWebView.h"

@class BrowserPreferencesStore;

@protocol BrowserMenuCoordinatorHost <NSObject>

@property (nonatomic, readonly) BrowserWebView *browserWebView;
@property (nonatomic, copy) NSString *browserPreviousURL;
@property (nonatomic) NSUInteger browserTextFontSize;
@property (nonatomic) BOOL browserFullscreenVideoPlaybackEnabled;
@property (nonatomic) BOOL browserCursorMagnifierEnabled;

- (void)browserPresentViewController:(UIViewController *)viewController;
- (void)browserLoadHomePage;
- (void)browserEditCurrentAddress;
- (void)browserShowHints;
- (void)browserShowTabOverview;
- (void)browserUpdateTextFontSize;
- (void)browserCaptureSnapshotForCurrentTab;
- (void)browserRecreateActiveWebViewPreservingCurrentURL;
- (void)browserBringCursorToFront;
- (void)browserPlayVideoUnderCursorIfAvailable;
- (void)browserSetAdBlockEnabled:(BOOL)enabled;

@end

@interface BrowserMenuCoordinator : NSObject

- (instancetype)initWithHost:(id<BrowserMenuCoordinatorHost>)host
            preferencesStore:(BrowserPreferencesStore *)preferencesStore;
- (void)showAdvancedMenu;

@end
