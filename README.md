# tvOS Browser

**Compared with the [upstream project](https://github.com/jvanakker/tvOSBrowser), this fork adds a redesigned Siri Remote interface, a tiled browser menu, a New Tab page with Favorites and recent visits, and expanded local history management.**

[Read the upstream project’s README](https://github.com/jvanakker/tvOSBrowser/blob/master/README.mdown).

A web browser for Apple TV, built with `WKWebView` and designed for the Siri Remote. There is no prebuilt binary; build and sign the app with Xcode for your own device.

> This project uses private tvOS and WebKit APIs and is intended for personal development and sideloading. App Store distribution is not supported.

## Build

Open [`_Project/Browser.xcodeproj`](_Project/Browser.xcodeproj) in Xcode, select the `Browser` scheme, then build for an Apple TV Simulator or a paired Apple TV. Keep the project’s existing signing settings for device builds.

## User guide

![The in-app Siri Remote guide](screenshots/user-guide.png)

Open the guide from the browser menu.

![The tiled browser menu](screenshots/menu.png)

## Features and limits

- Multiple tabs with session restoration
- Local Favorites and browsing history
- Pointer navigation, smooth scrolling, and a cursor magnifier
- Content blocking and page zoom
- Full-screen video playback through tvOS WebKit and AVPlayer

Video playback depends on the source format, codecs, delivery method, DRM, and the website’s player. Full-screen mode cannot make an unsupported stream playable.
