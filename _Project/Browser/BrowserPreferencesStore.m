#import "BrowserPreferencesStore.h"

static NSString * const kUserAgentDefaultsKey = @"UserAgent";
static NSString * const kMobileModeDefaultsKey = @"MobileMode";
static NSString * const kTextFontSizeDefaultsKey = @"TextFontSize";
static NSString * const kPageZoomPercentDefaultsKey = @"PageZoomPercent";
static NSString * const kEnableFullscreenVideoPlaybackDefaultsKey = @"EnableFullscreenVideoPlayback";
static NSString * const kAdBlockEnabledDefaultsKey = @"AdBlockEnabled";
static NSString * const kCursorMagnifierEnabledDefaultsKey = @"CursorMagnifierEnabled";
static NSString * const kDontShowHintsOnLaunchDefaultsKey = @"DontShowHintsOnLaunch";
static NSString * const kWebsiteLoggingEnabledDefaultsKey = @"WebsiteLoggingEnabled";
static NSString * const kHomepageDefaultsKey = @"homepage";

static NSUInteger const kDefaultTextFontSize = 100;
static NSUInteger const kMinimumTextFontSize = 50;
static NSUInteger const kMaximumTextFontSize = 200;

@implementation BrowserPreferencesStore

+ (NSString *)desktopUserAgent {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
}

+ (NSString *)mobileUserAgent {
    return @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
}

+ (BOOL)websiteLoggingEnabled {
    NSNumber *value = [NSUserDefaults.standardUserDefaults objectForKey:kWebsiteLoggingEnabledDefaultsKey];
    // Preserve existing logging until the user explicitly switches it off.
    return value == nil ? YES : value.boolValue;
}

- (BOOL)websiteLoggingEnabled {
    return BrowserPreferencesStore.websiteLoggingEnabled;
}

- (void)setWebsiteLoggingEnabled:(BOOL)enabled {
    [[self defaults] setBool:enabled forKey:kWebsiteLoggingEnabledDefaultsKey];
    [[self defaults] synchronize];
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

- (void)ensureUserAgentConsistency {
    if (self.userAgent.length > 0) {
        return;
    }
    self.userAgent = self.mobileModeEnabled ? BrowserPreferencesStore.mobileUserAgent : BrowserPreferencesStore.desktopUserAgent;
}

- (NSString *)userAgent {
    NSString *userAgent = [[self defaults] stringForKey:kUserAgentDefaultsKey];
    if (userAgent.length > 0) {
        return userAgent;
    }
    return self.mobileModeEnabled ? BrowserPreferencesStore.mobileUserAgent : BrowserPreferencesStore.desktopUserAgent;
}

- (void)setUserAgent:(NSString *)userAgent {
    [[self defaults] setObject:userAgent ?: @"" forKey:kUserAgentDefaultsKey];
    [[self defaults] synchronize];
}

- (BOOL)mobileModeEnabled {
    return [[self defaults] boolForKey:kMobileModeDefaultsKey];
}

- (void)setMobileModeEnabled:(BOOL)mobileModeEnabled {
    [[self defaults] setBool:mobileModeEnabled forKey:kMobileModeDefaultsKey];
    [[self defaults] synchronize];
}

- (NSUInteger)textFontSize {
    NSNumber *textFontSizeValue = [[self defaults] objectForKey:kTextFontSizeDefaultsKey];
    if (textFontSizeValue == nil) {
        return kDefaultTextFontSize;
    }
    NSUInteger textFontSize = textFontSizeValue.unsignedIntegerValue;
    return MIN(kMaximumTextFontSize, MAX(kMinimumTextFontSize, textFontSize));
}

- (void)setTextFontSize:(NSUInteger)textFontSize {
    textFontSize = MIN(kMaximumTextFontSize, MAX(kMinimumTextFontSize, textFontSize));
    [[self defaults] setObject:@(textFontSize) forKey:kTextFontSizeDefaultsKey];
    [[self defaults] synchronize];
}

- (NSUInteger)pageZoomPercent {
    NSNumber *storedValue = [[self defaults] objectForKey:kPageZoomPercentDefaultsKey];
    NSUInteger value = storedValue == nil ? 100 : storedValue.unsignedIntegerValue;
    return MIN((NSUInteger)200, MAX((NSUInteger)50, value));
}

- (void)setPageZoomPercent:(NSUInteger)pageZoomPercent {
    NSUInteger value = MIN((NSUInteger)200, MAX((NSUInteger)50, pageZoomPercent));
    [[self defaults] setObject:@(value) forKey:kPageZoomPercentDefaultsKey];
    [[self defaults] synchronize];
}

- (BOOL)fullscreenVideoPlaybackEnabled {
    return [[self defaults] boolForKey:kEnableFullscreenVideoPlaybackDefaultsKey];
}

- (void)setFullscreenVideoPlaybackEnabled:(BOOL)fullscreenVideoPlaybackEnabled {
    [[self defaults] setBool:fullscreenVideoPlaybackEnabled forKey:kEnableFullscreenVideoPlaybackDefaultsKey];
    [[self defaults] synchronize];
}

- (BOOL)adBlockEnabled {
    return [[self defaults] boolForKey:kAdBlockEnabledDefaultsKey];
}

- (void)setAdBlockEnabled:(BOOL)adBlockEnabled {
    [[self defaults] setBool:adBlockEnabled forKey:kAdBlockEnabledDefaultsKey];
    [[self defaults] synchronize];
}

- (BOOL)cursorMagnifierEnabled {
    return [[self defaults] boolForKey:kCursorMagnifierEnabledDefaultsKey];
}

- (void)setCursorMagnifierEnabled:(BOOL)cursorMagnifierEnabled {
    [[self defaults] setBool:cursorMagnifierEnabled forKey:kCursorMagnifierEnabledDefaultsKey];
}

- (BOOL)dontShowHintsOnLaunch {
    return [[self defaults] boolForKey:kDontShowHintsOnLaunchDefaultsKey];
}

- (void)setDontShowHintsOnLaunch:(BOOL)dontShowHintsOnLaunch {
    [[self defaults] setBool:dontShowHintsOnLaunch forKey:kDontShowHintsOnLaunchDefaultsKey];
    [[self defaults] synchronize];
}

- (NSString *)homePageURLString {
    NSString *value = [[self defaults] stringForKey:kHomepageDefaultsKey];
    return value ?: @"";
}

- (void)setHomePageURLString:(NSString *)homePageURLString {
    [[self defaults] setObject:homePageURLString ?: @"" forKey:kHomepageDefaultsKey];
    [[self defaults] synchronize];
}

@end
