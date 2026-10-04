#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserPreferencesStore : NSObject

+ (NSString *)desktopUserAgent;
+ (NSString *)mobileUserAgent;
+ (BOOL)websiteLoggingEnabled;
+ (BOOL)debugEnabled;

@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic) BOOL mobileModeEnabled;
@property (nonatomic) NSUInteger textFontSize;
@property (nonatomic) NSUInteger pageZoomPercent;
@property (nonatomic) BOOL fullscreenVideoPlaybackEnabled;
@property (nonatomic) BOOL adBlockEnabled;
@property (nonatomic) BOOL cursorMagnifierEnabled;
@property (nonatomic) BOOL dontShowHintsOnLaunch;
@property (nonatomic) BOOL websiteLoggingEnabled;
@property (nonatomic) BOOL debugEnabled;
@property (nonatomic, copy) NSString *homePageURLString;

- (void)ensureUserAgentConsistency;

@end

/// Numeric torrent/background diagnostics; never pass URLs, headers, or page content.
FOUNDATION_EXPORT void BrowserDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT NSString * _Nullable BrowserDebugLastLog(void);
FOUNDATION_EXPORT NSArray<NSString *> *BrowserDebugRecentLogs(void);

NS_ASSUME_NONNULL_END
