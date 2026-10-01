#import "BrowserWebView.h"
#import "BrowserPreferencesStore.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const kBrowserWebViewClassName = @"WKWebView";
static NSString * const kBrowserWebViewConfigurationClassName = @"WKWebViewConfiguration";
static NSString * const kBrowserWebsiteDataStoreClassName = @"WKWebsiteDataStore";
static NSString * const kBrowserUserContentControllerClassName = @"WKUserContentController";
static NSString * const kBrowserUserScriptClassName = @"WKUserScript";
static NSString * const kBrowserAdBlockEnabledDefaultsKey = @"AdBlockEnabled";
static NSString * const kBrowserAdBlockRuleListIdentifier = @"BrowserAdBlock-v3";
static char kBrowserNavigationURLObservationContext;

static void BrowserEnsureWebKitRuntimeLoaded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (NSClassFromString(kBrowserWebViewClassName) != Nil) {
            return;
        }

        NSArray<NSString *> *candidatePaths = @[
            @"/System/Library/Frameworks/WebKit.framework/WebKit",
            @"/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
            @"/System/Library/StagedFrameworks/Safari/WebKit.framework/WebKit",
        ];

        for (NSString *candidatePath in candidatePaths) {
            if (dlopen(candidatePath.UTF8String, RTLD_NOW | RTLD_GLOBAL) != NULL && NSClassFromString(kBrowserWebViewClassName) != Nil) {
                break;
            }
        }
    });
}

static BOOL BrowserPumpRunLoopUntil(BOOL *done) {
    static BOOL isPumpingRunLoop = NO;
    if (*done) {
        return YES;
    }
    if (isPumpingRunLoop) {
        return NO;
    }
    isPumpingRunLoop = YES;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!*done && [deadline timeIntervalSinceNow] > 0.0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    isPumpingRunLoop = NO;
    if (!*done) {
        NSLog(@"[WebKit] timed out waiting for a synchronous callback");
    }
    return *done;
}

static NSString *BrowserStringFromJavaScriptResult(id result) {
    if (result == nil || result == [NSNull null]) {
        return nil;
    }
    if ([result isKindOfClass:[NSString class]]) {
        return result;
    }
    if ([result respondsToSelector:@selector(stringValue)]) {
        return [result stringValue];
    }
    return [result description];
}

static BOOL BrowserSelectorNameMatchesMediaFilter(NSString *selectorName) {
    static NSArray<NSString *> *keywords = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"mediasource",
            @"managedmediasource",
            @"sourcebuffer",
            @"media",
            @"video",
            @"inline",
            @"autoplay",
            @"fullscreen",
            @"pictureinpicture",
            @"airplay",
            @"webm",
            @"vp9",
            @"av1",
            @"hls",
            @"mse",
            @"codec",
        ];
    });

    NSString *lowercaseSelectorName = selectorName.lowercaseString;
    for (NSString *keyword in keywords) {
        if ([lowercaseSelectorName containsString:keyword]) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *BrowserFilteredSelectorNamesForClass(Class klass) {
    if (klass == Nil) {
        return @[];
    }

    NSMutableOrderedSet<NSString *> *selectorNames = [NSMutableOrderedSet orderedSet];
    for (Class currentClass = klass; currentClass != Nil && currentClass != [NSObject class]; currentClass = class_getSuperclass(currentClass)) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(currentClass, &methodCount);
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex += 1) {
            SEL selector = method_getName(methods[methodIndex]);
            NSString *selectorName = NSStringFromSelector(selector);
            if (selectorName.length > 0 && BrowserSelectorNameMatchesMediaFilter(selectorName)) {
                [selectorNames addObject:selectorName];
            }
        }
        free(methods);
    }

    return [selectorNames.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSString *BrowserGetterNameFromSetterName(NSString *setterName) {
    if (![setterName hasPrefix:@"set"] || ![setterName hasSuffix:@":"] || setterName.length <= 4) {
        return nil;
    }

    NSString *propertyStem = [setterName substringWithRange:NSMakeRange(3, setterName.length - 4)];
    if (propertyStem.length == 0) {
        return nil;
    }

    NSString *firstCharacter = [[propertyStem substringToIndex:1] lowercaseString];
    if (propertyStem.length == 1) {
        return firstCharacter;
    }

    return [firstCharacter stringByAppendingString:[propertyStem substringFromIndex:1]];
}

static NSString *BrowserBooleanValueDescriptionForObjectAndSelector(id object, NSString *selectorName) {
    if (object == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil || signature.numberOfArguments != 2) {
        return nil;
    }

    const char *returnType = signature.methodReturnType;
    if (returnType == NULL) {
        return nil;
    }

    if (returnType[0] != 'B' && returnType[0] != 'c') {
        return nil;
    }

    BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    return value ? @"YES" : @"NO";
}

static id BrowserObjectResultForGetter(id object, NSString *selectorName) {
    if (object == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil || signature.numberOfArguments != 2) {
        return nil;
    }

    const char *returnType = signature.methodReturnType;
    if (returnType == NULL || returnType[0] != '@') {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *BrowserPreviewString(NSString *string, NSUInteger maxLength) {
    if (string.length <= maxLength) {
        return string;
    }
    return [[string substringToIndex:maxLength] stringByAppendingString:@"\n…"];
}

static NSString *BrowserStringValueForKnownSelectors(id object, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        id result = BrowserObjectResultForGetter(object, selectorName);
        if (result == nil || result == [NSNull null]) {
            continue;
        }
        NSString *stringResult = nil;
        if ([result isKindOfClass:[NSString class]]) {
            stringResult = result;
        } else if ([result respondsToSelector:@selector(stringValue)]) {
            stringResult = [result stringValue];
        } else {
            stringResult = [result description];
        }

        if (stringResult.length > 0) {
            return stringResult;
        }
    }
    return nil;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *BrowserFeatureEntriesForPreferences(id preferences) {
    if (preferences == nil) {
        return @[];
    }

    NSArray<NSString *> *collectionSelectors = @[
        @"_experimentalFeatures",
        @"_internalDebugFeatures",
        @"_features",
    ];

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *entries = [NSMutableArray array];
    for (NSString *collectionSelectorName in collectionSelectors) {
        id collection = BrowserObjectResultForGetter(preferences, collectionSelectorName);
        if (![collection conformsToProtocol:@protocol(NSFastEnumeration)]) {
            continue;
        }

        for (id feature in collection) {
            NSString *name = BrowserStringValueForKnownSelectors(feature, @[@"name", @"key", @"identifier", @"title", @"details"]);
            if (name.length == 0) {
                continue;
            }

            NSString *lowercaseName = name.lowercaseString;
            if (![lowercaseName containsString:@"media"] &&
                ![lowercaseName containsString:@"source"] &&
                ![lowercaseName containsString:@"vp9"] &&
                ![lowercaseName containsString:@"av1"] &&
                ![lowercaseName containsString:@"webm"] &&
                ![lowercaseName containsString:@"video"] &&
                ![lowercaseName containsString:@"mse"] &&
                ![lowercaseName containsString:@"managed"]) {
                continue;
            }

            NSString *enabledValue = BrowserBooleanValueDescriptionForObjectAndSelector(feature, @"enabled");
            if (enabledValue == nil) {
                enabledValue = BrowserBooleanValueDescriptionForObjectAndSelector(feature, @"isEnabled");
            }
            if (enabledValue == nil) {
                enabledValue = @"unknown";
            }

            NSString *key = BrowserStringValueForKnownSelectors(feature, @[@"key", @"identifier"]);
            NSString *source = [collectionSelectorName stringByReplacingOccurrencesOfString:@"_" withString:@""];
            [entries addObject:@{
                @"source": source ?: @"features",
                @"name": name,
                @"enabled": enabledValue,
                @"key": key ?: @"",
            }];
        }
    }

    return entries;
}

static void BrowserSetBooleanSelectorIfAvailable(id object, NSString *selectorName, BOOL value) {
    if (object == nil || selectorName.length == 0) {
        return;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if ([object respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
    }
}

static void BrowserConfigurePrivateMediaPreferences(id configuration) {
    if (configuration == nil) {
        return;
    }

    SEL preferencesSelector = NSSelectorFromString(@"preferences");
    if (![configuration respondsToSelector:preferencesSelector]) {
        return;
    }

    id preferences = ((id (*)(id, SEL))objc_msgSend)(configuration, preferencesSelector);
    if (preferences == nil) {
        return;
    }

    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setMediaSourceEnabled:", YES);
    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setManagedMediaSourceEnabled:", YES);
    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setMediaCapabilityGrantsEnabled:", YES);
    BrowserSetBooleanSelectorIfAvailable(preferences, @"_setVideoQualityIncludesDisplayCompositingEnabled:", YES);
}

static NSString *BrowserYouTubeRequestCaptureScript(void) {
    return
    @"(function(){"
        "if (window.__browserYouTubeHookInstalled) { return; }"
        "window.__browserYouTubeHookInstalled = true;"
        "window.__browserYouTubeIntegrity = window.__browserYouTubeIntegrity || {};"
        "function assignIfPresent(key, value) {"
            "if (value === undefined || value === null) { return; }"
            "var stringValue = String(value || '');"
            "if (!stringValue) { return; }"
            "window.__browserYouTubeIntegrity[key] = stringValue;"
        "}"
        "function capturePayload(payload) {"
            "try {"
                "if (!payload || typeof payload !== 'object') { return; }"
                "if (payload.serviceIntegrityDimensions) {"
                    "assignIfPresent('poToken', payload.serviceIntegrityDimensions.poToken || payload.serviceIntegrityDimensions.po_token);"
                "}"
                "if (payload.context && payload.context.serviceIntegrityDimensions) {"
                    "assignIfPresent('poToken', payload.context.serviceIntegrityDimensions.poToken || payload.context.serviceIntegrityDimensions.po_token);"
                "}"
                "if (payload.context && payload.context.client) {"
                    "assignIfPresent('requestClientName', payload.context.client.clientName);"
                    "assignIfPresent('requestClientVersion', payload.context.client.clientVersion);"
                "}"
            "} catch (error) {}"
        "}"
        "function toHeaderObject(headers) {"
            "var result = {};"
            "try {"
                "if (!headers) { return result; }"
                "if (typeof Headers !== 'undefined' && headers instanceof Headers) {"
                    "headers.forEach(function(value, key) { result[String(key)] = String(value); });"
                    "return result;"
                "}"
                "if (Array.isArray(headers)) {"
                    "headers.forEach(function(entry) {"
                        "if (Array.isArray(entry) && entry.length >= 2) { result[String(entry[0])] = String(entry[1]); }"
                    "});"
                    "return result;"
                "}"
                "if (typeof headers === 'object') {"
                    "Object.keys(headers).forEach(function(key) { result[String(key)] = String(headers[key]); });"
                "}"
            "} catch (error) {}"
            "return result;"
        "}"
        "function rememberRequest(url, body, headers, transport) {"
            "try {"
                "var integrity = window.__browserYouTubeIntegrity;"
                "integrity.lastPlayerRequestURL = String(url || '');"
                "integrity.lastPlayerRequestBody = String(body || '');"
                "integrity.lastPlayerRequestHeaders = JSON.stringify(headers || {});"
                "integrity.lastPlayerRequestTransport = String(transport || '');"
                "if (!integrity.firstPlayerRequestURL) {"
                    "integrity.firstPlayerRequestURL = integrity.lastPlayerRequestURL;"
                    "integrity.firstPlayerRequestBody = integrity.lastPlayerRequestBody;"
                    "integrity.firstPlayerRequestHeaders = integrity.lastPlayerRequestHeaders;"
                    "integrity.firstPlayerRequestTransport = integrity.lastPlayerRequestTransport;"
                "}"
            "} catch (error) {}"
        "}"
        "function captureBodyStringAsync(source, bodyString, headers, transport) {"
            "try {"
                "if (bodyString && bodyString !== '[object ReadableStream]') {"
                    "rememberRequest(source.url || '', bodyString, headers || {}, transport || '');"
                    "try { capturePayload(JSON.parse(bodyString)); } catch (error) {}"
                    "return;"
                "}"
                "if (source && typeof source.clone === 'function' && typeof source.text === 'function') {"
                    "source.clone().text().then(function(text) {"
                        "rememberRequest(source.url || '', text || '', headers || {}, transport || '');"
                        "try { capturePayload(JSON.parse(text || '')); } catch (error) {}"
                    "}).catch(function(){});"
                "}"
            "} catch (error) {}"
        "}"
        "function captureRequest(input, init) {"
            "try {"
                "var url = '';"
                "if (typeof input === 'string') { url = input; }"
                "else if (input && typeof input.url === 'string') { url = input.url; }"
                "if (url.indexOf('/youtubei/v1/player') === -1) { return; }"
                "var body = (init && init.body) || (input && input.body) || null;"
                "var bodyString = '';"
                "if (typeof body === 'string') { bodyString = body; }"
                "else if (body && typeof body === 'object' && typeof body.toString === 'function') { bodyString = String(body); }"
                "var headers = toHeaderObject((init && init.headers) || (input && input.headers) || null);"
                "rememberRequest(url, bodyString, headers, 'fetch');"
                "captureBodyStringAsync((input && typeof input.clone === 'function') ? input : null, bodyString, headers, 'fetch');"
                "if (typeof bodyString !== 'string' || !bodyString || bodyString === '[object ReadableStream]') { return; }"
                "try { capturePayload(JSON.parse(bodyString)); } catch (error) {}"
            "} catch (error) {}"
        "}"
        "function captureXHRRequest(xhr, body) {"
            "try {"
                "var url = String((xhr && xhr.__browserYouTubeURL) || '');"
                "if (url.indexOf('/youtubei/v1/player') === -1) { return; }"
                "var bodyString = '';"
                "if (typeof body === 'string') { bodyString = body; }"
                "else if (body && typeof body === 'object' && typeof body.toString === 'function') { bodyString = String(body); }"
                "var headers = xhr && xhr.__browserYouTubeHeaders ? xhr.__browserYouTubeHeaders : {};"
                "rememberRequest(url, bodyString, headers, 'xhr');"
                "if (typeof bodyString !== 'string' || !bodyString) { return; }"
                "try { capturePayload(JSON.parse(bodyString)); } catch (error) {}"
            "try { capturePayload(JSON.parse(body)); } catch (error) {}"
            "} catch (error) {}"
        "}"
        "var cfg = (window.ytcfg && window.ytcfg.data_) || {};"
        "assignIfPresent('poToken', cfg.PO_TOKEN || cfg.po_token || cfg.POTOKEN);"
        "if (cfg.SERVICE_INTEGRITY_DIMENSIONS) {"
            "assignIfPresent('poToken', cfg.SERVICE_INTEGRITY_DIMENSIONS.poToken || cfg.SERVICE_INTEGRITY_DIMENSIONS.po_token);"
        "}"
        "if (cfg.WEB_PLAYER_CONTEXT_CONFIGS) {"
            "var watchConfig = cfg.WEB_PLAYER_CONTEXT_CONFIGS.WEB_PLAYER_CONTEXT_CONFIG_ID_KEVLAR_WATCH || {};"
            "if (watchConfig.serviceIntegrityDimensions) {"
                "assignIfPresent('poToken', watchConfig.serviceIntegrityDimensions.poToken || watchConfig.serviceIntegrityDimensions.po_token);"
            "}"
        "}"
        "if (window.fetch) {"
            "var originalFetch = window.fetch;"
            "window.fetch = function(input, init) {"
                "captureRequest(input, init);"
                "return originalFetch.apply(this, arguments);"
            "};"
        "}"
        "if (window.XMLHttpRequest && window.XMLHttpRequest.prototype) {"
            "var originalOpen = window.XMLHttpRequest.prototype.open;"
            "var originalSend = window.XMLHttpRequest.prototype.send;"
            "var originalSetRequestHeader = window.XMLHttpRequest.prototype.setRequestHeader;"
            "window.XMLHttpRequest.prototype.open = function(method, url) {"
                "this.__browserYouTubeURL = String(url || '');"
                "this.__browserYouTubeHeaders = {};"
                "return originalOpen.apply(this, arguments);"
            "};"
            "window.XMLHttpRequest.prototype.setRequestHeader = function(key, value) {"
                "try {"
                    "if (!this.__browserYouTubeHeaders) { this.__browserYouTubeHeaders = {}; }"
                    "this.__browserYouTubeHeaders[String(key)] = String(value);"
                "} catch (error) {}"
                "return originalSetRequestHeader.apply(this, arguments);"
            "};"
            "window.XMLHttpRequest.prototype.send = function(body) {"
                "captureXHRRequest(this, body);"
                "return originalSend.apply(this, arguments);"
            "};"
        "}"
    "})();";
}

static NSString *BrowserFrameClickBridgeScript(NSString *secret) {
    return [NSString stringWithFormat:
            @"(function(){"
                "if (window.__browserTVFrameClick) { return; }"
                "var secret = '%@';"
                "var fullscreenTarget = null;"
                "var fullscreenTargetStyle = '';"
                "var fullscreenFrame = null;"
                "var fullscreenFrameStyle = '';"
                "var theaterBackdrop = null;"
                "var raisedAncestors = [];"
                "var lastActiveFrame = null;"
                "function notifyFullscreenChange() {"
                    "try { document.dispatchEvent(new Event('fullscreenchange')); } catch (error) {}"
                    "try { document.dispatchEvent(new Event('webkitfullscreenchange')); } catch (error) {}"
                "}"
                "function sendFullscreenToParent(action) {"
                    "if (window.parent !== window) {"
                        "window.parent.postMessage({browserTVFrameFullscreen: secret, action: action}, '*');"
                    "}"
                "}"
                "function beginTheater(element) {"
                    "var body = document.body;"
                    "if (!body) { return; }"
                    "theaterBackdrop = document.createElement('div');"
                    "theaterBackdrop.style.cssText = 'position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;background:rgba(0,0,0,.88)!important;z-index:2147483645!important;opacity:0;transition:opacity .22s ease!important';"
                    "theaterBackdrop.addEventListener('click', function() { if (window.__browserTVExitFullscreen) { window.__browserTVExitFullscreen(); } });"
                    "body.appendChild(theaterBackdrop);"
                    "requestAnimationFrame(function() { if (theaterBackdrop) { theaterBackdrop.style.opacity = '1'; } });"
                    "var ancestor = element.parentElement || (element.getRootNode && element.getRootNode().host);"
                    "while (ancestor && ancestor !== body) {"
                        "raisedAncestors.push({element:ancestor, style:ancestor.style.cssText});"
                        "if (getComputedStyle(ancestor).position === 'static') { ancestor.style.setProperty('position', 'relative', 'important'); }"
                        "ancestor.style.setProperty('z-index', '2147483646', 'important');"
                        "ancestor.style.setProperty('overflow', 'visible', 'important');"
                        "ancestor = ancestor.parentElement || (ancestor.getRootNode && ancestor.getRootNode().host);"
                    "}"
                "}"
                "function endTheater() {"
                    "for (var i = raisedAncestors.length - 1; i >= 0; i--) {"
                        "raisedAncestors[i].element.style.cssText = raisedAncestors[i].style;"
                    "}"
                    "raisedAncestors = [];"
                    "if (theaterBackdrop) { theaterBackdrop.remove(); theaterBackdrop = null; }"
                "}"
                "function enterFullscreen(element) {"
                    "if (!element || fullscreenTarget) { return; }"
                    "fullscreenTarget = element;"
                    "fullscreenTargetStyle = element.style.cssText;"
                    "beginTheater(element);"
                    "element.style.cssText += ';position:fixed!important;left:0!important;top:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;z-index:2147483647!important;background:#000!important';"
                    "sendFullscreenToParent('enter');"
                    "notifyFullscreenChange();"
                "}"
                "function exitFullscreen() {"
                    "if (!fullscreenTarget) { return false; }"
                    "fullscreenTarget.style.cssText = fullscreenTargetStyle;"
                    "endTheater();"
                    "fullscreenTarget = null;"
                    "fullscreenTargetStyle = '';"
                    "sendFullscreenToParent('exit');"
                    "notifyFullscreenChange();"
                    "return true;"
                "}"
                "function toggleVideo() {"
                    "var frame = fullscreenFrame || (lastActiveFrame && lastActiveFrame.isConnected ? lastActiveFrame : null);"
                    "if (frame && frame.contentWindow) {"
                        "frame.contentWindow.postMessage({browserTVFullscreenCommand: secret, action: 'toggle'}, '*');"
                        "return true;"
                    "}"
                    "var videos = document.querySelectorAll('video');"
                    "var video = null;"
                    "var bestArea = 0;"
                    "for (var i = 0; i < videos.length; i++) {"
                        "if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }"
                        "var rect = videos[i].getBoundingClientRect();"
                        "var area = Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0)) * Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0));"
                        "if (area > bestArea) { bestArea = area; video = videos[i]; }"
                    "}"
                    "if (video) {"
                        "if (video.paused) { var result = video.play(); if (result && result.catch) { result.catch(function(){}); } }"
                        "else { video.pause(); }"
                        "return true;"
                    "}"
                    "return false;"
                "}"
                "function handleMediaHorizontalPress(direction) {"
                    "if (fullscreenFrame && fullscreenFrame.contentWindow) {"
                        "fullscreenFrame.contentWindow.postMessage({browserTVFullscreenCommand: secret, action: 'seek', direction: direction}, '*');"
                        "return true;"
                    "}"
                    "var video = fullscreenTarget && fullscreenTarget.tagName === 'VIDEO' ? fullscreenTarget :"
                        "(fullscreenTarget && fullscreenTarget.querySelector ? fullscreenTarget.querySelector('video') : null);"
                    "var videos = document.querySelectorAll('video');"
                    "if (!video) {"
                        "for (var i = 0; i < videos.length; i++) {"
                            "if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }"
                        "}"
                    "}"
                    "if (video) {"
                        "var delta = direction === 'right' ? 10 : -10;"
                        "var current = Number(video.currentTime);"
                        "var duration = Number(video.duration);"
                        "var targetTime = (isFinite(current) ? current : 0) + delta;"
                        "if (isFinite(duration) && duration > 0) { targetTime = Math.min(targetTime, Math.max(0, duration - 0.05)); }"
                        "video.currentTime = Math.max(0, targetTime);"
                        "return true;"
                    "}"
                    "if (lastActiveFrame && lastActiveFrame.isConnected && lastActiveFrame.contentWindow) {"
                        "lastActiveFrame.contentWindow.postMessage({browserTVFullscreenCommand: secret, action: 'seek', direction: direction}, '*');"
                        "return true;"
                    "}"
                    "return false;"
                "}"
                "function frameForSource(source) {"
                    "function search(root) {"
                        "var elements = root.querySelectorAll('*');"
                        "for (var i = 0; i < elements.length; i++) {"
                            "var element = elements[i];"
                            "if (element.tagName === 'IFRAME' && element.contentWindow === source) { return element; }"
                            "if (element.shadowRoot) { var nested = search(element.shadowRoot); if (nested) { return nested; } }"
                        "}"
                        "return null;"
                    "}"
                    "return search(document);"
                "}"
                "function frameAtPoint(x, y) {"
                    "var hit = document.elementFromPoint(x, y);"
                    "if (!hit) { return null; }"
                    "if (hit.tagName === 'IFRAME') { return hit; }"
                    "function search(root) {"
                        "var elements = root.querySelectorAll('*');"
                        "for (var i = elements.length - 1; i >= 0; i--) {"
                            "var element = elements[i];"
                            "if (element.shadowRoot) { var nested = search(element.shadowRoot); if (nested) { return nested; } }"
                            "if (element.tagName !== 'IFRAME') { continue; }"
                            "var rect = element.getBoundingClientRect();"
                            "if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom && rect.width > 0 && rect.height > 0) { return element; }"
                        "}"
                        "return null;"
                    "}"
                    "for (var element = hit; element; element = element.parentElement) {"
                        "if (element.shadowRoot) { var frame = search(element.shadowRoot); if (frame) { return frame; } }"
                    "}"
                    "return null;"
                "}"
                "function isFullscreenButton(element) {"
                    "if (!element || !document.querySelector('video')) { return false; }"
                    "var label = [element.id || '', element.className || '', element.getAttribute('aria-label') || '', element.getAttribute('title') || '', element.getAttribute('data-plyr') || ''].join(' ').toLowerCase();"
                    "return /full.?screen|expand|maximize|enlarge|розгорнути|повн.*екран/.test(label);"
                "}"
                "function videoContainer(element) {"
                    "var video = document.querySelector('video');"
                    "var candidate = element;"
                    "while (candidate && candidate !== document.body) {"
                        "if (candidate !== video && candidate.querySelector && candidate.querySelector('video')) { return candidate; }"
                        "candidate = candidate.parentElement;"
                    "}"
                    "return (video && video.parentElement) || element;"
                "}"
                "function clickAt(x, y) {"
                    "if (!isFinite(x) || !isFinite(y)) { return false; }"
                    "var element = document.elementFromPoint(x, y);"
                    "if (!element) { return false; }"
                    "var frame = frameAtPoint(x, y);"
                    "if (frame && frame.contentWindow) {"
                        "lastActiveFrame = frame;"
                        "var rect = frame.getBoundingClientRect();"
                        "var scaleX = rect.width ? frame.offsetWidth / rect.width : 1;"
                        "var scaleY = rect.height ? frame.offsetHeight / rect.height : 1;"
                        "frame.contentWindow.postMessage({browserTVFrameClick: secret, x: (x - rect.left) * scaleX - frame.clientLeft, y: (y - rect.top) * scaleY - frame.clientTop}, '*');"
                        "return true;"
                    "}"
                    "var target = element.closest ? (element.closest('a, button, input, label, select, [role=button], [onclick], [tabindex]') || element) : element;"
                    "if (isFullscreenButton(target) || isFullscreenButton(element)) {"
                        "if (!exitFullscreen()) { enterFullscreen(videoContainer(target)); }"
                        "return true;"
                    "}"
                    "try { if (target.focus) { target.focus(); } } catch (error) {}"
                    "function dispatch(type, constructorName) {"
                        "try {"
                            "var Constructor = window[constructorName];"
                            "if (Constructor) {"
                                "target.dispatchEvent(new Constructor(type, {bubbles:true, cancelable:true, composed:true, view:window, clientX:x, clientY:y, screenX:x, screenY:y, button:0, buttons:1, pointerType:'mouse'}));"
                                "return;"
                            "}"
                        "} catch (error) {}"
                        "var event = document.createEvent('MouseEvents');"
                        "event.initMouseEvent(type, true, true, window, 1, x, y, x, y, false, false, false, false, 0, null);"
                        "target.dispatchEvent(event);"
                    "}"
                    "dispatch('pointerdown', 'PointerEvent');"
                    "dispatch('mousedown', 'MouseEvent');"
                    "dispatch('pointerup', 'PointerEvent');"
                    "dispatch('mouseup', 'MouseEvent');"
                    "if (typeof target.click === 'function') { target.click(); }"
                    "else { dispatch('click', 'MouseEvent'); }"
                    "return true;"
                "}"
                "window.__browserTVFrameClick = clickAt;"
                "window.__browserTVFrameAtPoint = function(x, y) { return !!frameAtPoint(x, y); };"
                "window.__browserTVExitFullscreen = function() {"
                    "if (exitFullscreen()) { return true; }"
                    "if (fullscreenFrame && fullscreenFrame.contentWindow) {"
                        "fullscreenFrame.contentWindow.postMessage({browserTVFullscreenCommand: secret, action: 'exit'}, '*');"
                        "return true;"
                    "}"
                    "return false;"
                "};"
                "window.__browserTVToggleVideo = toggleVideo;"
                "window.__browserTVHandleMediaHorizontalPress = handleMediaHorizontalPress;"
                "function fullscreenElement() { return fullscreenTarget || fullscreenFrame; }"
                "try { Object.defineProperty(document, 'fullscreenElement', {configurable:true, get:fullscreenElement}); } catch (error) {}"
                "try { Object.defineProperty(document, 'webkitFullscreenElement', {configurable:true, get:fullscreenElement}); } catch (error) {}"
                "try { Object.defineProperty(document, 'webkitIsFullScreen', {configurable:true, get:function() { return !!fullscreenElement(); }}); } catch (error) {}"
                "function overrideMethod(object, name, implementation) {"
                    "try { Object.defineProperty(object, name, {configurable:true, writable:true, value:implementation}); } catch (error) {}"
                "}"
                "if (window.Element && Element.prototype) {"
                    "overrideMethod(Element.prototype, 'requestFullscreen', function() { enterFullscreen(this); return Promise.resolve(); });"
                    "overrideMethod(Element.prototype, 'webkitRequestFullscreen', function() { enterFullscreen(this); });"
                    "overrideMethod(Element.prototype, 'webkitRequestFullScreen', function() { enterFullscreen(this); });"
                "}"
                "if (window.HTMLVideoElement && HTMLVideoElement.prototype) {"
                    "overrideMethod(HTMLVideoElement.prototype, 'webkitEnterFullscreen', function() { enterFullscreen(videoContainer(this)); });"
                    "overrideMethod(HTMLVideoElement.prototype, 'webkitEnterFullScreen', function() { enterFullscreen(videoContainer(this)); });"
                "}"
                "overrideMethod(document, 'exitFullscreen', function() { exitFullscreen(); return Promise.resolve(); });"
                "overrideMethod(document, 'webkitExitFullscreen', exitFullscreen);"
                "overrideMethod(document, 'webkitCancelFullScreen', exitFullscreen);"
                "window.addEventListener('message', function(event) {"
                    "var data = event.data;"
                    "if (!data) { return; }"
                    "if (event.source === window.parent && data.browserTVFrameClick === secret) {"
                        "clickAt(Number(data.x), Number(data.y));"
                    "} else if (event.source === window.parent && data.browserTVFullscreenCommand === secret) {"
                        "if (data.action === 'exit') { window.__browserTVExitFullscreen(); }"
                        "if (data.action === 'toggle') { toggleVideo(); }"
                        "if (data.action === 'seek') { handleMediaHorizontalPress(data.direction); }"
                    "} else if (data.browserTVFrameFullscreen === secret) {"
                        "var frame = frameForSource(event.source);"
                        "if (!frame) { return; }"
                        "if (data.action === 'enter') {"
                            "fullscreenFrame = frame;"
                            "fullscreenFrameStyle = frame.style.cssText;"
                            "beginTheater(frame);"
                            "frame.style.cssText += ';position:fixed!important;left:0!important;top:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;z-index:2147483647!important;background:#000!important';"
                        "} else if (data.action === 'exit' && fullscreenFrame === frame) {"
                            "frame.style.cssText = fullscreenFrameStyle;"
                            "endTheater();"
                            "fullscreenFrame = null;"
                            "fullscreenFrameStyle = '';"
                        "}"
                        "sendFullscreenToParent(data.action);"
                    "}"
                "});"
            "})();", secret];
}

static void BrowserWriteWebsiteDiagnostic(NSDictionary *entry) {
    if (!BrowserPreferencesStore.websiteLoggingEnabled) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
    if (data == nil || data.length > 4096) return;
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *path = [[cache URLByAppendingPathComponent:@"BrowserWebsiteDiagnostics.log"] path];
    if (!path) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date,
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    NSFileManager *manager = NSFileManager.defaultManager;
    if ([[manager attributesOfItemAtPath:path error:nil][NSFileSize] unsignedIntegerValue] > 128 * 1024) {
        NSString *previous = [path stringByAppendingString:@".previous"];
        [manager removeItemAtPath:previous error:nil];
        [manager moveItemAtPath:path toPath:previous error:nil];
    }
    if (![manager fileExistsAtPath:path]) [manager createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [file seekToEndOfFile];
        [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    } @catch (NSException *exception) { NSLog(@"[WebsiteDiagnostics] Log write failed: %@", exception.name); }
}

// Shared handler avoids retaining a web view through its message controller.
@interface BrowserWebsiteDiagnosticsHandler : NSObject
- (void)userContentController:(id)controller didReceiveScriptMessage:(id)message;
@end
@implementation BrowserWebsiteDiagnosticsHandler
- (void)userContentController:(id)controller didReceiveScriptMessage:(id)message {
    if (!BrowserPreferencesStore.websiteLoggingEnabled) return;
    id body = [message valueForKey:@"body"];
    if (![body isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"event", @"origin", @"episode", @"season", @"seconds",
                            @"storageCount", @"storageError", @"key", @"length"]) {
        id value = body[key];
        if ([value isKindOfClass:NSString.class]) entry[key] = [value substringToIndex:MIN([value length], 160)];
        else if ([value isKindOfClass:NSNumber.class]) entry[key] = value;
    }
    if (entry.count) BrowserWriteWebsiteDiagnostic(entry);
}
@end

static NSString *BrowserWebsiteDiagnosticsScript(void) {
    return @"(function(){"
        "function send(e){try{e.origin=location.origin;window.webkit.messageHandlers.browserWebsiteDiagnostics.postMessage(e)}catch(x){}}"
        "try{send({event:'document',storageCount:localStorage.length})}catch(e){send({event:'document',storageError:String(e)})}"
        "try{var get=Storage.prototype.getItem,set=Storage.prototype.setItem;"
        "Storage.prototype.getItem=function(k){try{var v=get.call(this,k);send({event:'storage-get',key:String(k),length:v===null?0:v.length});return v}catch(e){send({event:'storage-get',key:String(k),storageError:String(e)});throw e}};"
        "Storage.prototype.setItem=function(k,v){try{var r=set.call(this,k,v);send({event:'storage-set',key:String(k),length:String(v).length});return r}catch(e){send({event:'storage-set',key:String(k),storageError:String(e)});throw e}}"
        "}catch(e){send({event:'storage-hook',storageError:String(e)})}"
        "var last='';function state(){try{var text=document.body?document.body.innerText:'';"
        "var episode=text.match(/Серія\\s*\\d+/),season=text.match(/Сезон\\s*\\d+/),video=document.querySelector('video');"
        "if(!episode&&!video)return;var e={event:'player',episode:episode?episode[0]:'',season:season?season[0]:''};"
        "if(video)e.seconds=Math.floor(video.currentTime/15)*15;var key=JSON.stringify(e);if(key!==last){last=key;send(e)}}catch(x){}}"
        "setInterval(state,2000);"
        "addEventListener('message',function(e){try{var d=e.data&&e.data.payload&&e.data.payload.data;"
        "if(!d||typeof d!=='object')return;var v={event:'player-info'};"
        "if(typeof d.e==='string')v.episode=d.e;if(typeof d.s==='string')v.season=d.s;if(typeof d.t==='number')v.seconds=d.t;"
        "if(v.episode||v.season||typeof v.seconds==='number')send(v)}catch(x){}});"
        "})();";
}

// tvOS denies WebKit's default Library/WebKit directory. Use one shared
// persistent store rooted in the app's writable cache directory instead.
static id BrowserPersistentWebsiteDataStore(void) {
    BrowserEnsureWebKitRuntimeLoaded();
    static id store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class storeClass = NSClassFromString(kBrowserWebsiteDataStoreClassName);
        Class configurationClass = NSClassFromString(@"_WKWebsiteDataStoreConfiguration");
        SEL directoryInitializer = NSSelectorFromString(@"initWithDirectory:");
        SEL storeFactory = NSSelectorFromString(@"_storeWithConfiguration:");
        SEL storeInitializer = NSSelectorFromString(@"_initWithConfiguration:");
        NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *directory = [cache URLByAppendingPathComponent:@"BrowserWebsiteData" isDirectory:YES];
        NSError *error = nil;
        if (directory && [configurationClass instancesRespondToSelector:directoryInitializer] &&
            ([storeClass respondsToSelector:storeFactory] || [storeClass instancesRespondToSelector:storeInitializer]) &&
            [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
            id configuration = ((id (*)(id, SEL))objc_msgSend)((id)configurationClass, @selector(alloc));
            configuration = ((id (*)(id, SEL, id))objc_msgSend)(configuration, directoryInitializer, directory);
            if ([storeClass respondsToSelector:storeFactory])
                store = ((id (*)(id, SEL, id))objc_msgSend)((id)storeClass, storeFactory, configuration);
            else {
                id allocated = ((id (*)(id, SEL))objc_msgSend)((id)storeClass, @selector(alloc));
                store = ((id (*)(id, SEL, id))objc_msgSend)(allocated, storeInitializer, configuration);
            }
            if (store) {
                NSLog(@"[WebsiteData] Persistent store at %@", directory.path);
                BrowserWriteWebsiteDiagnostic(@{@"event": @"store-start", @"directory": directory.path, @"process": @(NSProcessInfo.processInfo.processIdentifier)});
            }
        }
        if (store == nil && [storeClass respondsToSelector:NSSelectorFromString(@"defaultDataStore")]) {
            NSLog(@"[WebsiteData] Custom persistent store unavailable: %@", error);
            store = ((id (*)(id, SEL))objc_msgSend)((id)storeClass, NSSelectorFromString(@"defaultDataStore"));
        }
    });
    return store;
}

static void BrowserInstallUserScripts(id configuration) {
    if (configuration == nil) {
        return;
    }

    Class userContentControllerClass = NSClassFromString(kBrowserUserContentControllerClassName);
    Class userScriptClass = NSClassFromString(kBrowserUserScriptClassName);
    if (userContentControllerClass == Nil || userScriptClass == Nil) {
        return;
    }

    SEL userContentControllerGetter = NSSelectorFromString(@"userContentController");
    SEL setUserContentControllerSelector = NSSelectorFromString(@"setUserContentController:");
    id userContentController = nil;
    if ([configuration respondsToSelector:userContentControllerGetter]) {
        userContentController = ((id (*)(id, SEL))objc_msgSend)(configuration, userContentControllerGetter);
    }

    if (userContentController == nil && [configuration respondsToSelector:setUserContentControllerSelector]) {
        userContentController = ((id (*)(id, SEL))objc_msgSend)((id)userContentControllerClass, @selector(new));
        ((void (*)(id, SEL, id))objc_msgSend)(configuration, setUserContentControllerSelector, userContentController);
    }

    SEL addUserScriptSelector = NSSelectorFromString(@"addUserScript:");
    SEL userScriptInitializer = NSSelectorFromString(@"initWithSource:injectionTime:forMainFrameOnly:");
    if (userContentController == nil ||
        ![userContentController respondsToSelector:addUserScriptSelector] ||
        ![userScriptClass instancesRespondToSelector:userScriptInitializer]) {
        return;
    }

    SEL addHandler = NSSelectorFromString(@"addScriptMessageHandler:name:");
    if ([userContentController respondsToSelector:addHandler]) {
        static BrowserWebsiteDiagnosticsHandler *handler;
        static dispatch_once_t handlerToken;
        dispatch_once(&handlerToken, ^{ handler = [BrowserWebsiteDiagnosticsHandler new]; });
        ((void (*)(id, SEL, id, id))objc_msgSend)(userContentController, addHandler, handler, @"browserWebsiteDiagnostics");
        id diagnosticScript = ((id (*)(id, SEL))objc_msgSend)((id)userScriptClass, @selector(alloc));
        diagnosticScript = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(diagnosticScript, userScriptInitializer, BrowserWebsiteDiagnosticsScript(), 0, NO);
        if (diagnosticScript) ((void (*)(id, SEL, id))objc_msgSend)(userContentController, addUserScriptSelector, diagnosticScript);
    }

    id userScript = ((id (*)(id, SEL))objc_msgSend)((id)userScriptClass, @selector(alloc));
    userScript = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(userScript, userScriptInitializer, BrowserYouTubeRequestCaptureScript(), 0, NO);
    if (userScript != nil) {
        ((void (*)(id, SEL, id))objc_msgSend)(userContentController, addUserScriptSelector, userScript);
    }

    NSString *frameClickSecret = [NSUUID UUID].UUIDString;
    id frameClickScript = ((id (*)(id, SEL))objc_msgSend)((id)userScriptClass, @selector(alloc));
    frameClickScript = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(frameClickScript, userScriptInitializer, BrowserFrameClickBridgeScript(frameClickSecret), 0, NO);
    if (frameClickScript != nil) {
        ((void (*)(id, SEL, id))objc_msgSend)(userContentController, addUserScriptSelector, frameClickScript);
    }
}

static NSString *BrowserAdBlockRulesJSON(void) {
    NSArray<NSString *> *domains = @[
        @"2mdn.net", @"adnxs.com", @"adsrvr.org", @"amazon-adsystem.com",
        @"casalemedia.com", @"criteo.com", @"criteo.net", @"doubleclick.net",
        @"googlesyndication.com", @"googleadservices.com", @"media.net",
        @"openx.net", @"outbrain.com", @"pubmatic.com", @"rubiconproject.com",
        @"taboola.com", @"yieldmo.com"
    ];
    NSMutableArray<NSDictionary *> *rules = [NSMutableArray arrayWithCapacity:domains.count];
    for (NSString *domain in domains) {
        NSString *escapedDomain = [domain stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
        NSString *URLFilter = [NSString stringWithFormat:@"^https?://[^/]*%@/", escapedDomain];
        [rules addObject:@{
            @"trigger": @{
                @"url-filter": URLFilter,
                @"load-type": @[@"third-party"]
            },
            @"action": @{@"type": @"block"}
        }];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:rules options:0 error:nil];
    return data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

typedef void (^BrowserAdBlockRuleListCompletion)(id ruleList, NSError *error);

static void BrowserLoadAdBlockRuleList(BrowserAdBlockRuleListCompletion completion) {
    static id cachedRuleList = nil;
    static NSMutableArray *pendingCompletions = nil;
    static BOOL compiling = NO;
    if (cachedRuleList != nil) {
        completion(cachedRuleList, nil);
        return;
    }
    Class storeClass = NSClassFromString(@"WKContentRuleListStore");
    SEL customStoreSelector = NSSelectorFromString(@"storeWithURL:");
    SEL compileSelector = NSSelectorFromString(@"compileContentRuleListForIdentifier:encodedContentRuleList:completionHandler:");
    NSURL *cacheURL = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject
        URLByAppendingPathComponent:@"BrowserContentRules" isDirectory:YES];
    NSError *directoryError = nil;
    if (cacheURL != nil) {
        [[NSFileManager defaultManager] createDirectoryAtURL:cacheURL
                                  withIntermediateDirectories:YES attributes:nil error:&directoryError];
    }
    id store = cacheURL != nil && directoryError == nil && storeClass != Nil && [storeClass respondsToSelector:customStoreSelector]
        ? ((id (*)(id, SEL, NSURL *))objc_msgSend)((id)storeClass, customStoreSelector, cacheURL) : nil;
    NSString *rulesJSON = BrowserAdBlockRulesJSON();
    if (store == nil || ![store respondsToSelector:compileSelector] || rulesJSON.length == 0) {
        NSError *error = [NSError errorWithDomain:@"BrowserAdBlock" code:1
                                        userInfo:@{NSLocalizedDescriptionKey: directoryError.localizedDescription ?: @"WebKit content rule lists are unavailable on this device."}];
        completion(nil, error);
        return;
    }
    if (pendingCompletions == nil) {
        pendingCompletions = [NSMutableArray array];
    }
    [pendingCompletions addObject:[completion copy]];
    if (compiling) {
        return;
    }
    compiling = YES;
    ((void (*)(id, SEL, NSString *, NSString *, void (^)(id, NSError *)))objc_msgSend)(
        store, compileSelector, kBrowserAdBlockRuleListIdentifier, rulesJSON, ^(id ruleList, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                cachedRuleList = ruleList;
                compiling = NO;
                NSArray *callbacks = [pendingCompletions copy];
                [pendingCompletions removeAllObjects];
                for (id callbackObject in callbacks) {
                    BrowserAdBlockRuleListCompletion callback = callbackObject;
                    callback(ruleList, error);
                }
            });
        });
}

@interface BrowserWebView ()

@property (nullable, nonatomic, strong) id runtimeWebView;
@property (nullable, nonatomic, strong) NSURLRequest *lastRequest;
@property (nullable, nonatomic, copy) NSString *lastTitle;
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) id userContentController;
@property (nonatomic, strong) id appliedAdBlockRuleList;
@property (nonatomic, readwrite) BOOL adBlockEnabled;
@property (nonatomic, readwrite, copy) NSString *adBlockStatus;
@property (nonatomic) CGFloat lastAppliedPageZoom;
@property (nonatomic) CGFloat lastAppliedTextZoom;

@end

@implementation BrowserWebView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithUserAgent:nil allowsInlineMediaPlayback:YES];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInitWithUserAgent:nil allowsInlineMediaPlayback:YES];
    }
    return self;
}

- (instancetype)initWithUserAgent:(NSString *)userAgent allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        [self commonInitWithUserAgent:userAgent allowsInlineMediaPlayback:allowsInlineMediaPlayback];
    }
    return self;
}

- (void)commonInitWithUserAgent:(NSString *)userAgent allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback {
    BrowserEnsureWebKitRuntimeLoaded();

    self.backgroundColor = UIColor.blackColor;
    self.userAgent = userAgent;
    self.pageZoomFactor = 1.0;
    self.textZoomFactor = 1.0;

    Class configurationClass = NSClassFromString(kBrowserWebViewConfigurationClassName);
    Class webViewClass = NSClassFromString(kBrowserWebViewClassName);
    if (configurationClass == Nil || webViewClass == Nil) {
        return;
    }

    id configuration = ((id (*)(id, SEL))objc_msgSend)((id)configurationClass, @selector(new));
    SEL allowsInlineMediaPlaybackSelector = NSSelectorFromString(@"setAllowsInlineMediaPlayback:");
    if (configuration != nil && [configuration respondsToSelector:allowsInlineMediaPlaybackSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, allowsInlineMediaPlaybackSelector, allowsInlineMediaPlayback);
    }
    SEL dataStoreSetter = NSSelectorFromString(@"setWebsiteDataStore:");
    id dataStore = BrowserPersistentWebsiteDataStore();
    if (dataStore && [configuration respondsToSelector:dataStoreSetter])
        ((void (*)(id, SEL, id))objc_msgSend)(configuration, dataStoreSetter, dataStore);
    BrowserConfigurePrivateMediaPreferences(configuration);
    BrowserInstallUserScripts(configuration);
    SEL userContentControllerSelector = NSSelectorFromString(@"userContentController");
    if ([configuration respondsToSelector:userContentControllerSelector]) {
        self.userContentController = ((id (*)(id, SEL))objc_msgSend)(configuration, userContentControllerSelector);
    }

    id webViewObject = ((id (*)(id, SEL))objc_msgSend)((id)webViewClass, @selector(alloc));
    SEL initializer = NSSelectorFromString(@"initWithFrame:configuration:");
    webViewObject = ((id (*)(id, SEL, CGRect, id))objc_msgSend)(webViewObject, initializer, self.bounds, configuration);
    if (webViewObject == nil) {
        return;
    }

    self.runtimeWebView = webViewObject;
    [webViewObject addObserver:self forKeyPath:@"URL" options:0 context:&kBrowserNavigationURLObservationContext];
    [webViewObject addObserver:self forKeyPath:@"loading" options:0 context:&kBrowserNavigationURLObservationContext];
    UIView *runtimeView = (UIView *)webViewObject;
    runtimeView.frame = self.bounds;
    runtimeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    runtimeView.backgroundColor = UIColor.blackColor;

    SEL navigationDelegateSelector = NSSelectorFromString(@"setNavigationDelegate:");
    if ([webViewObject respondsToSelector:navigationDelegateSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(webViewObject, navigationDelegateSelector, self);
    }

    SEL UIDelegateSelector = NSSelectorFromString(@"setUIDelegate:");
    if ([webViewObject respondsToSelector:UIDelegateSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(webViewObject, UIDelegateSelector, self);
    }

    [self addSubview:runtimeView];
    [self setUserAgent:userAgent];
    [self setAdBlockEnabled:[[NSUserDefaults standardUserDefaults] boolForKey:kBrowserAdBlockEnabledDefaultsKey]];
}

- (void)setAdBlockEnabled:(BOOL)enabled {
    _adBlockEnabled = enabled;
    if (!enabled) {
        id ruleList = self.appliedAdBlockRuleList;
        SEL removeSelector = NSSelectorFromString(@"removeContentRuleList:");
        SEL removeAllSelector = NSSelectorFromString(@"removeAllContentRuleLists");
        if (ruleList != nil) {
            if ([self.userContentController respondsToSelector:removeAllSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(self.userContentController, removeAllSelector);
            } else if ([self.userContentController respondsToSelector:removeSelector]) {
                ((void (*)(id, SEL, id))objc_msgSend)(self.userContentController, removeSelector, ruleList);
            } else {
                self.adBlockStatus = @"removal-unavailable";
                NSLog(@"[AdBlock] cannot remove content rules from this WebKit view");
                return;
            }
            self.appliedAdBlockRuleList = nil;
            if (self.request != nil) {
                [self reload];
            }
        }
        self.adBlockStatus = @"off";
        return;
    }

    self.adBlockStatus = @"loading";
    __weak typeof(self) weakSelf = self;
    BrowserLoadAdBlockRuleList(^(id ruleList, NSError *error) {
        BrowserWebView *strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf.adBlockEnabled) {
            return;
        }
        SEL addSelector = NSSelectorFromString(@"addContentRuleList:");
        if (ruleList == nil || ![strongSelf.userContentController respondsToSelector:addSelector]) {
            strongSelf.adBlockStatus = @"unavailable";
            NSLog(@"[AdBlock] unavailable: %@", error ?: @"WKUserContentController cannot install rule lists");
            return;
        }
        if (strongSelf.appliedAdBlockRuleList == ruleList) {
            strongSelf.adBlockStatus = @"on";
            return;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(strongSelf.userContentController, addSelector, ruleList);
        strongSelf.appliedAdBlockRuleList = ruleList;
        strongSelf.adBlockStatus = @"on";
        if (strongSelf.request != nil) {
            [strongSelf reload];
        }
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    ((UIView *)self.runtimeWebView).frame = self.bounds;
    [self applyPageScalingIfNeeded];
}

- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled {
    [super setUserInteractionEnabled:userInteractionEnabled];

    UIView *runtimeView = (UIView *)self.runtimeWebView;
    runtimeView.userInteractionEnabled = userInteractionEnabled;

    UIScrollView *scrollView = [self scrollView];
    scrollView.userInteractionEnabled = userInteractionEnabled;
}

- (UIScrollView *)scrollView {
    SEL selector = NSSelectorFromString(@"scrollView");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
}

- (NSURL *)currentURL {
    SEL selector = NSSelectorFromString(@"URL");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
}

- (NSURLRequest *)request {
    NSURL *currentURL = [self currentURL];
    if (currentURL != nil) {
        return [NSURLRequest requestWithURL:currentURL];
    }
    return self.lastRequest;
}

- (NSString *)title {
    SEL selector = NSSelectorFromString(@"title");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        return self.lastTitle;
    }
    NSString *title = ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    return title ?: self.lastTitle;
}

- (void)dealloc {
    [self.runtimeWebView removeObserver:self forKeyPath:@"URL" context:&kBrowserNavigationURLObservationContext];
    [self.runtimeWebView removeObserver:self forKeyPath:@"loading" context:&kBrowserNavigationURLObservationContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                      change:(NSDictionary *)change context:(void *)context {
    if (context != &kBrowserNavigationURLObservationContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BrowserWebView *webView = weakSelf;
        SEL loadingSelector = NSSelectorFromString(@"isLoading");
        if (webView == nil || webView.loading ||
            ([webView.runtimeWebView respondsToSelector:loadingSelector] &&
             ((BOOL (*)(id, SEL))objc_msgSend)(webView.runtimeWebView, loadingSelector))) return;
        if ([webView.delegate respondsToSelector:@selector(webViewDidChangeNavigationHistory:)]) {
            [webView.delegate webViewDidChangeNavigationHistory:webView];
        }
    });
}

- (NSDictionary *)navigationHistorySnapshot {
    SEL listSelector = NSSelectorFromString(@"backForwardList");
    if (![self.runtimeWebView respondsToSelector:listSelector]) return nil;
    id list = ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, listSelector);
    SEL backSelector = NSSelectorFromString(@"backList");
    SEL currentSelector = NSSelectorFromString(@"currentItem");
    SEL forwardSelector = NSSelectorFromString(@"forwardList");
    if (![list respondsToSelector:backSelector] || ![list respondsToSelector:currentSelector] ||
        ![list respondsToSelector:forwardSelector]) return nil;
    id current = ((id (*)(id, SEL))objc_msgSend)(list, currentSelector);
    if (current == nil) return nil;
    NSMutableArray *items = [NSMutableArray arrayWithArray:((id (*)(id, SEL))objc_msgSend)(list, backSelector)];
    [items addObject:current];
    [items addObjectsFromArray:((id (*)(id, SEL))objc_msgSend)(list, forwardSelector)];
    NSMutableArray *URLs = [NSMutableArray array];
    NSInteger index = NSNotFound;
    for (id item in items) {
        SEL URLSelector = NSSelectorFromString(@"URL");
        if (![item respondsToSelector:URLSelector]) continue;
        NSURL *URL = ((id (*)(id, SEL))objc_msgSend)(item, URLSelector);
        if (URL.host.length == 0 || ![@[@"http", @"https"] containsObject:URL.scheme.lowercaseString]) continue;
        if (item == current) index = URLs.count;
        [URLs addObject:URL.absoluteString];
    }
    if (index == NSNotFound) return nil;
    return @{@"navigationURLs": URLs, @"navigationIndex": @(index)};
}

- (BOOL)canGoBack {
    SEL selector = NSSelectorFromString(@"canGoBack");
    return self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector) : NO;
}

- (BOOL)canGoForward {
    SEL selector = NSSelectorFromString(@"canGoForward");
    return self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector] ? ((BOOL (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector) : NO;
}

- (NSString *)URLStringForHistoryItemSelector:(SEL)itemSelector {
    SEL listSelector = NSSelectorFromString(@"backForwardList");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:listSelector]) return nil;
    id list = ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, listSelector);
    if (![list respondsToSelector:itemSelector]) return nil;
    id item = ((id (*)(id, SEL))objc_msgSend)(list, itemSelector);
    SEL URLSelector = NSSelectorFromString(@"URL");
    if (![item respondsToSelector:URLSelector]) return nil;
    NSURL *URL = ((id (*)(id, SEL))objc_msgSend)(item, URLSelector);
    return URL.absoluteString;
}

- (NSString *)backURLString {
    return [self URLStringForHistoryItemSelector:NSSelectorFromString(@"backItem")];
}

- (NSString *)forwardURLString {
    return [self URLStringForHistoryItemSelector:NSSelectorFromString(@"forwardItem")];
}

- (void)loadRequest:(NSURLRequest *)request {
    if (request == nil || self.runtimeWebView == nil) {
        return;
    }
    self.lastRequest = request;
    SEL selector = NSSelectorFromString(@"loadRequest:");
    if ([self.runtimeWebView respondsToSelector:selector]) {
        ((id (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, selector, request);
    }
}

- (void)loadHTMLString:(NSString *)HTMLString {
    if (self.runtimeWebView == nil || HTMLString.length == 0) {
        return;
    }
    SEL selector = NSSelectorFromString(@"loadHTMLString:baseURL:");
    if ([self.runtimeWebView respondsToSelector:selector]) {
        self.lastRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]];
        ((id (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, selector, HTMLString, nil);
    }
}

- (void)reload {
    SEL selector = NSSelectorFromString(@"reload");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    }
}

- (void)goBack {
    SEL selector = NSSelectorFromString(@"goBack");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    }
}

- (void)goForward {
    SEL selector = NSSelectorFromString(@"goForward");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((id (*)(id, SEL))objc_msgSend)(self.runtimeWebView, selector);
    }
}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    if (script.length == 0 || self.runtimeWebView == nil) {
        return nil;
    }

    SEL selector = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if (![self.runtimeWebView respondsToSelector:selector]) {
        return nil;
    }

    __block id evaluationResult = nil;
    __block NSError *evaluationError = nil;
    __block BOOL finished = NO;
    ((void (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, selector, script, ^(id result, NSError *error) {
        evaluationResult = result;
        evaluationError = error;
        finished = YES;
    });
    if (!BrowserPumpRunLoopUntil(&finished)) {
        return nil;
    }

    if (evaluationError != nil) {
        return nil;
    }
    return BrowserStringFromJavaScriptResult(evaluationResult);
}

- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(NSString *result))completion {
    SEL selector = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if (script.length == 0 || self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }

    ((void (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, selector, script, ^(id result, NSError *error) {
        if (completion != nil) {
            completion(error == nil ? BrowserStringFromJavaScriptResult(result) : nil);
        }
    });
}

- (void)pauseAllMediaPlayback {
    if (self.runtimeWebView == nil) {
        return;
    }

    // Prefer WebKit's internal media pause APIs when available.
    SEL pauseWithCompletionHandlerSelector = NSSelectorFromString(@"pauseAllMediaPlaybackWithCompletionHandler:");
    if ([self.runtimeWebView respondsToSelector:pauseWithCompletionHandlerSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, pauseWithCompletionHandlerSelector, nil);
    } else {
        SEL pauseSelector = NSSelectorFromString(@"pauseAllMediaPlayback:");
        if ([self.runtimeWebView respondsToSelector:pauseSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, pauseSelector, nil);
        } else {
            SEL privatePauseSelector = NSSelectorFromString(@"_pauseAllMediaPlayback");
            if ([self.runtimeWebView respondsToSelector:privatePauseSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(self.runtimeWebView, privatePauseSelector);
            }
        }
    }

    // JS fallback for page media elements and common iframe-based players.
    NSString *pauseScript =
        @"(function(){"
            "function safe(fn){ try { fn(); } catch (error) {} }"
            "var media = document.querySelectorAll('video,audio');"
            "for (var i = 0; i < media.length; i++) {"
                "var element = media[i];"
                "safe(function(){ element.pause(); });"
                "safe(function(){ element.autoplay = false; });"
                "safe(function(){ element.removeAttribute('autoplay'); });"
            "}"
            "var iframePlayers = document.querySelectorAll('iframe');"
            "for (var j = 0; j < iframePlayers.length; j++) {"
                "var frame = iframePlayers[j];"
                "var src = String(frame.src || '').toLowerCase();"
                "if (!src) { continue; }"
                "safe(function(){"
                    "if (src.indexOf('youtube.com') !== -1 || src.indexOf('youtube-nocookie.com') !== -1) {"
                        "frame.contentWindow.postMessage(JSON.stringify({event:'command',func:'pauseVideo',args:''}), '*');"
                    "}"
                "});"
                "safe(function(){"
                    "if (src.indexOf('vimeo.com') !== -1) {"
                        "frame.contentWindow.postMessage(JSON.stringify({method:'pause'}), '*');"
                    "}"
                "});"
            "}"
        "})();";
    [self stringByEvaluatingJavaScriptFromString:pauseScript];
}

- (NSString *)runtimeMediaPreferenceReport {
    if (self.runtimeWebView == nil) {
        return @"Runtime web view unavailable.";
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *objectSelectors = @[
        @{@"label": @"WKWebView", @"selector": @""},
        @{@"label": @"Configuration", @"selector": @"configuration"},
        @{@"label": @"Configuration._preferences", @"selector": @"configuration._preferences"},
        @{@"label": @"Configuration.preferences", @"selector": @"configuration.preferences"},
        @{@"label": @"Configuration.defaultWebpagePreferences", @"selector": @"configuration.defaultWebpagePreferences"},
        @{@"label": @"Configuration.websiteDataStore", @"selector": @"configuration.websiteDataStore"},
        @{@"label": @"WKWebView._configuration", @"selector": @"_configuration"},
        @{@"label": @"WKWebView._page", @"selector": @"_page"},
    ];

    NSMutableDictionary<NSValue *, NSString *> *seenObjects = [NSMutableDictionary dictionary];
    NSMutableString *report = [NSMutableString string];

    for (NSDictionary<NSString *, NSString *> *entry in objectSelectors) {
        NSString *label = entry[@"label"] ?: @"Object";
        NSString *selectorPath = entry[@"selector"] ?: @"";
        id currentObject = self.runtimeWebView;

        if (selectorPath.length > 0) {
            NSArray<NSString *> *components = [selectorPath componentsSeparatedByString:@"."];
            for (NSString *component in components) {
                currentObject = BrowserObjectResultForGetter(currentObject, component);
                if (currentObject == nil) {
                    break;
                }
            }
        }

        if (currentObject == nil) {
            [report appendFormat:@"[%@] unavailable\n\n", label];
            continue;
        }

        NSValue *objectKey = [NSValue valueWithNonretainedObject:currentObject];
        NSString *previousLabel = seenObjects[objectKey];
        if (previousLabel != nil) {
            [report appendFormat:@"[%@] same object as %@ (%@)\n\n", label, previousLabel, NSStringFromClass([currentObject class])];
            continue;
        }
        seenObjects[objectKey] = label;

        NSArray<NSString *> *selectorNames = BrowserFilteredSelectorNamesForClass([currentObject class]);
        NSMutableArray<NSString *> *booleanLines = [NSMutableArray array];
        for (NSString *selectorName in selectorNames) {
            NSString *getterName = nil;
            if ([selectorName hasPrefix:@"set"] && [selectorName hasSuffix:@":"]) {
                getterName = BrowserGetterNameFromSetterName(selectorName);
            } else {
                getterName = selectorName;
            }

            NSString *valueDescription = BrowserBooleanValueDescriptionForObjectAndSelector(currentObject, getterName);
            if (valueDescription != nil) {
                [booleanLines addObject:[NSString stringWithFormat:@"%@ = %@", getterName, valueDescription]];
            }
        }

        [report appendFormat:@"[%@] %@\n", label, NSStringFromClass([currentObject class])];
        if (booleanLines.count > 0) {
            [report appendString:@"Boolean getters:\n"];
            for (NSString *line in booleanLines) {
                [report appendFormat:@"- %@\n", line];
            }
        } else {
            [report appendString:@"Boolean getters:\n- none resolved\n"];
        }

        [report appendString:@"Matching selectors:\n"];
        if (selectorNames.count == 0) {
            [report appendString:@"- none\n\n"];
            continue;
        }

        for (NSString *selectorName in selectorNames) {
            [report appendFormat:@"- %@\n", selectorName];
        }

        if ([label isEqualToString:@"Configuration.preferences"]) {
            NSArray<NSDictionary<NSString *, NSString *> *> *featureEntries = BrowserFeatureEntriesForPreferences(currentObject);
            [report appendString:@"Feature entries:\n"];
            if (featureEntries.count == 0) {
                [report appendString:@"- none\n"];
            } else {
                for (NSDictionary<NSString *, NSString *> *featureEntry in featureEntries) {
                    NSString *featureSource = featureEntry[@"source"] ?: @"features";
                    NSString *featureName = featureEntry[@"name"] ?: @"Unknown";
                    NSString *featureEnabled = featureEntry[@"enabled"] ?: @"unknown";
                    NSString *featureKey = featureEntry[@"key"];
                    if (featureKey.length > 0) {
                        [report appendFormat:@"- [%@] %@ (%@) = %@\n", featureSource, featureName, featureKey, featureEnabled];
                    } else {
                        [report appendFormat:@"- [%@] %@ = %@\n", featureSource, featureName, featureEnabled];
                    }
                }
            }
        }
        [report appendString:@"\n"];
    }

    return BrowserPreviewString(report, 24000);
}

- (void)installYouTubeRequestCaptureHook {
    [self evaluateJavaScript:BrowserYouTubeRequestCaptureScript() completion:^(__unused NSString *result) {}];
}

- (void)setUserAgent:(NSString *)userAgent {
    _userAgent = [userAgent copy];
    SEL selector = NSSelectorFromString(@"setCustomUserAgent:");
    if (self.runtimeWebView != nil && [self.runtimeWebView respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.runtimeWebView, selector, _userAgent);
    }
}

- (void)setPageZoomFactor:(CGFloat)pageZoomFactor {
    CGFloat nextFactor = MIN(2.0, MAX(0.5, pageZoomFactor));
    if (fabs(_pageZoomFactor - nextFactor) < 0.001) {
        return;
    }
    _pageZoomFactor = nextFactor;
    [self applyPageScalingIfNeeded];
}

- (void)setTextZoomFactor:(CGFloat)textZoomFactor {
    CGFloat nextFactor = MIN(2.0, MAX(0.5, textZoomFactor));
    if (fabs(_textZoomFactor - nextFactor) < 0.001) {
        return;
    }
    _textZoomFactor = nextFactor;
    [self applyTextZoomIfNeeded];
}

- (void)applyTextZoomIfNeeded {
    if (self.runtimeWebView == nil || fabs(self.lastAppliedTextZoom - self.textZoomFactor) < 0.001) {
        return;
    }
    SEL setter = NSSelectorFromString(@"_setTextZoomFactor:");
    SEL supportQuery = NSSelectorFromString(@"_supportsTextZoom");
    BOOL hasSetter = [self.runtimeWebView respondsToSelector:setter];
    BOOL supportsTextZoom = ![self.runtimeWebView respondsToSelector:supportQuery] ||
        ((BOOL (*)(id, SEL))objc_msgSend)(self.runtimeWebView, supportQuery);
    if (!hasSetter || !supportsTextZoom) {
        return;
    }
    self.lastAppliedTextZoom = self.textZoomFactor;
    ((void (*)(id, SEL, double))objc_msgSend)(self.runtimeWebView, setter, self.textZoomFactor);
}

- (void)applyPageScalingIfNeeded {
    if (self.runtimeWebView == nil) {
        return;
    }

    UIScrollView *scrollView = [self scrollView];
    if (scrollView == nil || CGRectIsEmpty(scrollView.bounds)) {
        return;
    }

    CGFloat zoomValue = self.pageZoomFactor;

    if (fabs(self.lastAppliedPageZoom - zoomValue) < 0.001) {
        return;
    }
    SEL pageZoomSelector = NSSelectorFromString(@"setPageZoom:");
    if ([self.runtimeWebView respondsToSelector:pageZoomSelector]) {
        ((void (*)(id, SEL, double))objc_msgSend)(self.runtimeWebView, pageZoomSelector, zoomValue);
        self.lastAppliedPageZoom = zoomValue;
    }
}

- (void)captureSnapshotWithCompletion:(void (^)(UIImage *snapshot))completion {
    SEL selector = NSSelectorFromString(@"takeSnapshotWithConfiguration:completionHandler:");
    if (self.runtimeWebView == nil || ![self.runtimeWebView respondsToSelector:selector]) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }
    ((void (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, selector, nil, ^(UIImage *snapshot, NSError *error) {
        if (completion != nil) {
            completion(error == nil ? snapshot : nil);
        }
    });
}

- (void)captureSnapshotInRect:(CGRect)rect
                       width:(CGFloat)width
                  completion:(void (^)(UIImage *snapshot))completion {
    SEL snapshotSelector = NSSelectorFromString(@"takeSnapshotWithConfiguration:completionHandler:");
    Class configurationClass = NSClassFromString(@"WKSnapshotConfiguration");
    if (self.runtimeWebView == nil || configurationClass == Nil ||
        ![self.runtimeWebView respondsToSelector:snapshotSelector]) {
        if (completion != nil) { completion(nil); }
        return;
    }
    id configuration = ((id (*)(id, SEL))objc_msgSend)((id)configurationClass, @selector(new));
    SEL rectSelector = NSSelectorFromString(@"setRect:");
    SEL widthSelector = NSSelectorFromString(@"setSnapshotWidth:");
    if (![configuration respondsToSelector:rectSelector] || ![configuration respondsToSelector:widthSelector]) {
        if (completion != nil) { completion(nil); }
        return;
    }
    ((void (*)(id, SEL, CGRect))objc_msgSend)(configuration, rectSelector, rect);
    ((void (*)(id, SEL, id))objc_msgSend)(configuration, widthSelector, @(width));
    ((id (*)(id, SEL, id, id))objc_msgSend)(self.runtimeWebView, snapshotSelector, configuration,
        ^(UIImage *snapshot, NSError *error) {
            if (completion != nil) {
                completion(error == nil ? snapshot : nil);
            }
        });
}

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    self.loading = YES;
    if ([self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.delegate webViewDidStartLoad:self];
    }
}

- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    self.loading = NO;
    self.lastTitle = [self title];
    self.lastRequest = [self request];
    [self installYouTubeRequestCaptureHook];
    self.lastAppliedPageZoom = 0.0;
    self.lastAppliedTextZoom = 0.0;
    [self applyPageScalingIfNeeded];
    [self applyTextZoomIfNeeded];
    if ([self.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.delegate webViewDidFinishLoad:self];
    }
}

- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    self.loading = NO;
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    self.loading = NO;
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

- (void)webViewWebContentProcessDidTerminate:(id)webView {
    self.loading = NO;
}

- (NSURLRequest *)requestFromNavigationAction:(id)navigationAction {
    if (navigationAction == nil) {
        return nil;
    }
    SEL requestSelector = NSSelectorFromString(@"request");
    if (![navigationAction respondsToSelector:requestSelector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(navigationAction, requestSelector);
}

- (NSInteger)navigationTypeFromNavigationAction:(id)navigationAction {
    if (navigationAction == nil) {
        return 0;
    }
    SEL navigationTypeSelector = NSSelectorFromString(@"navigationType");
    if (![navigationAction respondsToSelector:navigationTypeSelector]) {
        return 0;
    }
    return ((NSInteger (*)(id, SEL))objc_msgSend)(navigationAction, navigationTypeSelector);
}

- (void)webView:(id)webView decidePolicyForNavigationAction:(id)navigationAction decisionHandler:(void (^)(NSInteger policy))decisionHandler {
    NSURLRequest *request = [self requestFromNavigationAction:navigationAction];
    NSInteger navigationType = [self navigationTypeFromNavigationAction:navigationAction];
    BOOL isMainFrameRequest = YES;

    SEL targetFrameSelector = NSSelectorFromString(@"targetFrame");
    if ([navigationAction respondsToSelector:targetFrameSelector]) {
        id targetFrame = ((id (*)(id, SEL))objc_msgSend)(navigationAction, targetFrameSelector);
        SEL mainFrameSelector = NSSelectorFromString(@"isMainFrame");
        if (targetFrame != nil && [targetFrame respondsToSelector:mainFrameSelector]) {
            isMainFrameRequest = ((BOOL (*)(id, SEL))objc_msgSend)(targetFrame, mainFrameSelector);
        }
    }

    BOOL shouldAllow = YES;
    if ([self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        shouldAllow = [self.delegate webView:self shouldStartLoadWithRequest:request navigationType:navigationType];
    }

    if (shouldAllow && isMainFrameRequest && request != nil) {
        self.lastRequest = request;
    }

    if (decisionHandler != nil) {
        decisionHandler(shouldAllow ? 1 : 0);
    }
}

- (id)webView:(id)webView
createWebViewWithConfiguration:(id)configuration
forNavigationAction:(id)navigationAction
windowFeatures:(id)windowFeatures {
    (void)webView;
    (void)configuration;
    (void)windowFeatures;

    NSURLRequest *request = [self requestFromNavigationAction:navigationAction];
    NSInteger navigationType = [self navigationTypeFromNavigationAction:navigationAction];

    BOOL delegateHandlesNewTabRequests = [self.delegate respondsToSelector:@selector(webView:shouldCreateNewTabWithRequest:navigationType:)];
    BOOL handledInTab = NO;
    if (delegateHandlesNewTabRequests) {
        handledInTab = [self.delegate webView:self shouldCreateNewTabWithRequest:request navigationType:navigationType];
    }

    if (!delegateHandlesNewTabRequests && !handledInTab && request != nil) {
        BOOL shouldAllow = YES;
        if ([self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
            shouldAllow = [self.delegate webView:self shouldStartLoadWithRequest:request navigationType:navigationType];
        }
        if (shouldAllow) {
            [self loadRequest:request];
        }
    }

    return nil;
}

+ (id)defaultWebsiteDataStore {
    return BrowserPersistentWebsiteDataStore();
}

+ (id)defaultCookieStore {
    id dataStore = [self defaultWebsiteDataStore];
    SEL selector = NSSelectorFromString(@"httpCookieStore");
    if (dataStore == nil || ![dataStore respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(dataStore, selector);
}

+ (NSArray<NSHTTPCookie *> *)allCookies {
    id cookieStore = [self defaultCookieStore];
    SEL selector = NSSelectorFromString(@"getAllCookies:");
    if (cookieStore == nil || ![cookieStore respondsToSelector:selector]) {
        return NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies ?: @[];
    }

    __block NSArray<NSHTTPCookie *> *cookies = nil;
    __block BOOL finished = NO;
    ((void (*)(id, SEL, id))objc_msgSend)(cookieStore, selector, ^(NSArray<NSHTTPCookie *> *fetchedCookies) {
        cookies = fetchedCookies;
        finished = YES;
    });
    if (!BrowserPumpRunLoopUntil(&finished)) {
        return NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies ?: @[];
    }
    return cookies ?: @[];
}

+ (NSData *)cookieDataRepresentation {
    NSArray<NSHTTPCookie *> *cookies = [self allCookies];
    NSError *error = nil;
    NSData *cookieData = [NSKeyedArchiver archivedDataWithRootObject:cookies requiringSecureCoding:NO error:&error];
    return error == nil ? cookieData : nil;
}

+ (void)restoreCookiesFromData:(NSData *)cookieData {
    if (cookieData.length == 0) {
        return;
    }

    NSError *error = nil;
    NSSet *allowedClasses = [NSSet setWithObjects:[NSArray class], [NSHTTPCookie class], nil];
    NSArray<NSHTTPCookie *> *cookies = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses fromData:cookieData error:&error];
    if (![cookies isKindOfClass:[NSArray class]]) {
        return;
    }

    id cookieStore = [self defaultCookieStore];
    SEL selector = NSSelectorFromString(@"setCookie:completionHandler:");
    if (cookieStore == nil || ![cookieStore respondsToSelector:selector]) {
        for (NSHTTPCookie *cookie in cookies) {
            [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookie:cookie];
        }
        return;
    }

    __block NSInteger remainingCount = cookies.count;
    __block BOOL finished = cookies.count == 0;
    for (NSHTTPCookie *cookie in cookies) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(cookieStore, selector, cookie, ^{
            remainingCount -= 1;
            finished = remainingCount == 0;
        });
    }
    BrowserPumpRunLoopUntil(&finished);
}

+ (NSSet<NSString *> *)allWebsiteDataTypes {
    Class dataStoreClass = NSClassFromString(kBrowserWebsiteDataStoreClassName);
    SEL selector = NSSelectorFromString(@"allWebsiteDataTypes");
    if (dataStoreClass == Nil || ![dataStoreClass respondsToSelector:selector]) {
        return [NSSet set];
    }
    return ((id (*)(id, SEL))objc_msgSend)((id)dataStoreClass, selector);
}

+ (void)removeWebsiteDataTypes:(NSSet<NSString *> *)websiteDataTypes completion:(void (^)(void))completion {
    id dataStore = [self defaultWebsiteDataStore];
    SEL selector = NSSelectorFromString(@"removeDataOfTypes:modifiedSince:completionHandler:");
    if (dataStore == nil || ![dataStore respondsToSelector:selector]) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    NSDate *beginningOfTime = [NSDate dateWithTimeIntervalSince1970:0];
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(dataStore, selector, websiteDataTypes, beginningOfTime, ^{
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

+ (void)clearCachedDataWithCompletion:(void (^)(void))completion {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSMutableSet<NSString *> *websiteDataTypes = [NSMutableSet set];
    for (NSString *dataType in [self allWebsiteDataTypes]) {
        if ([dataType.lowercaseString containsString:@"cache"]) {
            [websiteDataTypes addObject:dataType];
        }
    }

    [self removeWebsiteDataTypes:websiteDataTypes completion:completion];
}

+ (void)clearCookiesWithCompletion:(void (^)(void))completion {
    id cookieStore = [self defaultCookieStore];
    SEL getAllCookiesSelector = NSSelectorFromString(@"getAllCookies:");
    SEL deleteCookieSelector = NSSelectorFromString(@"deleteCookie:completionHandler:");
    if (cookieStore == nil || ![cookieStore respondsToSelector:getAllCookiesSelector] || ![cookieStore respondsToSelector:deleteCookieSelector]) {
        NSHTTPCookieStorage *storage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        for (NSHTTPCookie *cookie in storage.cookies) {
            [storage deleteCookie:cookie];
        }
        if (completion != nil) {
            completion();
        }
        return;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(cookieStore, getAllCookiesSelector, ^(NSArray<NSHTTPCookie *> *cookies) {
        if (cookies.count == 0) {
            if (completion != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion();
                });
            }
            return;
        }

        __block NSInteger remainingCount = cookies.count;
        for (NSHTTPCookie *cookie in cookies) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(cookieStore, deleteCookieSelector, cookie, ^{
                remainingCount -= 1;
                if (remainingCount == 0 && completion != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion();
                    });
                }
            });
        }
    });
}

+ (void)resetWebsiteDataWithCompletion:(void (^)(void))completion {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [self removeWebsiteDataTypes:[self allWebsiteDataTypes] completion:completion];
}

@end
