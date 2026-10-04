# tvOSofaBrowse

A personal-use web browser for Apple TV, built around `WKWebView` and the Siri Remote. This fork extends the [upstream tvOS Browser](https://github.com/jvanakker/tvOSBrowser) to make ordinary websites, embedded video, and torrent media practical to use from a sofa. There is no prebuilt app or App Store release.

**A touchpad-equipped remote is required. The browser cannot be used without a touchpad.**

## Why this fork

- **Mouse-like control with a TV remote:** slide on the touchpad to move a pointer, press Center to click website controls, and use Up/Down for smooth scrolling. A cursor magnifier helps target small controls.
- **Custom video players in iframes:** interact with supported player controls inside embedded frames, including some cross-origin frames and Shadow DOM, using the pointer and remote playback buttons.
- **Torrent streaming:** open magnet and `.torrent` links from websites, choose files or folders, and play selected media through TVVLCKit as verified pieces arrive, before the whole file finishes downloading.
- **Ad blocking:** turn WebKit content rules on or off from the browser menu to block advertising and tracking requests.
- **Comfortable reading:** scale the whole page and its text from 50% to 200% in 10% steps, with a saved zoom level and an easy reset to 100%.
- **A menu made for Apple TV:** use a tiled panel for address entry, tabs, history, Favorites, Torrents, zoom, settings, and data-clearing actions without a desktop-style toolbar covering the page.

The browser also restores tabs and their Back/Forward navigation, shows Favorites and recent visits on a native New Tab page, and keeps full local history without automatic age-based deletion. A compressed local backup can recover history, Favorites, and tab navigation if the main database is missing or damaged.

Playback and website interaction depend on each site's player, format, codec, and DRM. Torrent downloads may pause when tvOS suspends the app; Background App Refresh and the experimental Keep Alive setting do not guarantee continuous background transfers. Website cookies and storage are separate from the browser database backup.

## Build for personal use

Open [`_Project/Browser.xcodeproj`](_Project/Browser.xcodeproj) in Xcode and select the `Browser` scheme. The Apple TV Simulator is the easiest starting point. For a physical Apple TV, use your own local automatic-signing settings by copying `_Project/Browser/Config/Signing.local.xcconfig.example` to `Signing.local.xcconfig` and filling in your development team and bundle identifier. The local file is ignored by Git. A paid Apple Developer membership and App Store publication are not part of this project.

The torrent feature needs the pinned dependencies installed by `scripts/bootstrap-torrent-deps.sh` and `scripts/bootstrap-vlc-deps.sh` before building. These install libtorrent, Boost, and TVVLCKit into ignored `.deps/` with pinned checksums. Preserve their upstream licenses when distributing source or binaries.

The app uses private tvOS and WebKit APIs and is intended for personal development and sideloading.

## Using the remote

Slide on the touchpad to move the pointer, press Center to click, and use Up/Down to scroll. Back/Menu opens the browser menu. The menu provides address entry, tabs, Favorites, history, Torrents, zoom, settings, and data-clearing actions. App-owned pages use tvOS focus: Center activates, holding Center opens context actions, and Play/Pause performs the page's shortcut.

The visual quick guide is available in the app's Tools menu. On New Tab, Center opens a Favorite or recent visit; Play/Pause opens its actions. In All History, Center opens a row and Play/Pause marks it for selection. In Torrents, Center or Play/Pause plays a focused media file, while the download icon selects it without playback. Hold Center on app-owned rows for more actions.

## Project status

Current source version: **2.17.9**. The version number describes the current source state; this personal-use fork has no corresponding published releases or Git tags. Detailed development notes, changelog, roadmap, and user guide are kept locally under the ignored `docs/agent/` directory.
