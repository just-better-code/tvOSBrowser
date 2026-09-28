#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserPreferencesStore : NSObject

+ (NSString *)desktopUserAgent;
+ (NSString *)mobileUserAgent;

@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic) BOOL mobileModeEnabled;
@property (nonatomic) BOOL topNavigationBarVisible;
@property (nonatomic) NSUInteger textFontSize;
@property (nonatomic) NSUInteger pageZoomPercent;
@property (nonatomic) BOOL fullscreenVideoPlaybackEnabled;
@property (nonatomic) BOOL adBlockEnabled;
@property (nonatomic) BOOL cursorMagnifierEnabled;
@property (nonatomic) BOOL dontShowHintsOnLaunch;
@property (nonatomic, copy) NSString *homePageURLString;

- (void)ensureUserAgentConsistency;

@end

NS_ASSUME_NONNULL_END
