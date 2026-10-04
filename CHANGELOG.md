# Changelog

## 2.17.11 - 2026-10-04

### Fixed

- Install the TVVLCKit simulator slice alongside the device slice so a clean Apple TV Simulator build can link torrent playback ([bootstrap script](scripts/bootstrap-vlc-deps.sh)).

## 2.17.10 - 2026-10-04

### Changed

- Fit the browser menu on a 1080p screen with a full-width address bar, six navigation buttons, three-column actions and a wider User Guide tile ([user guide](docs/USER_GUIDE.md#main-menu)).

## 2.17.9 - 2026-10-04

### Added

- Rewind or fast-forward continuously while holding a player seek button, with larger steps after holding the 30-second button for ten seconds ([user guide](USER_GUIDE.md#torrents)).

## 2.17.8 - 2026-10-04

### Added

- Resume each torrent media file from its saved playback position and clear that position when playback finishes or its torrent data is removed ([user guide](USER_GUIDE.md#torrents), [torrent architecture](TORRENTS.md)).

## 2.17.7 - 2026-10-04

### Fixed

- Pause torrent playback when the app becomes inactive, ignore touchpad direction gestures while player controls are hidden, and hide the status header with the controls during playback ([user guide](USER_GUIDE.md#torrents)).

## 2.17.6 - 2026-10-04

### Fixed

- Show the selected file's completion percentage while buffering or streaming, and label files and torrents Complete only when their selected bytes are fully downloaded ([user guide](USER_GUIDE.md#torrents)).

## 2.17.5 - 2026-10-04

### Fixed

- Prioritize playback and requested torrent pieces so streaming can start before the selected file finishes downloading ([torrent architecture](TORRENTS.md), [development history](DEVELOPMENT_HISTORY.md#2026-10-04--torrent-streaming-and-player-controls)).

## 2.17.4 - 2026-10-04

### Added

- Reset a torrent from its context actions by deleting its cached files and restoring its source with every file skipped ([user guide](USER_GUIDE.md#torrents)).

## 2.17.3 - 2026-10-04

### Changed

- Show a download symbol for starting all files in a torrent and move Remove into the torrent's context actions ([user guide](USER_GUIDE.md#torrents)).

### Added

- Browse torrent folders and choose an individual file or whole folder from a focusable download icon without starting playback or every file ([user guide](USER_GUIDE.md#torrents)).

## 2.17.2 - 2026-10-04

### Changed

- Move the background runtime probe result into Debug and add a master diagnostic switch with ten recent numeric log entries ([user guide](USER_GUIDE.md#torrents)).

## 2.17.1 - 2026-10-04

### Added

- Offer system-managed background refresh and processing opportunities for manually started torrents, and show a torrent-free runtime probe to measure actual execution after leaving the browser ([user guide](USER_GUIDE.md#torrents)).

## 2.17.0 - 2026-10-04

### Changed

- Show the native New Tab, History, Torrents, and playback controls with a shared tvOS page style and remote focus behavior ([user guide](USER_GUIDE.md)).
- Open newly imported torrents in the overall list with the new row focused, richer transfer details, and a saved priority order ([user guide](USER_GUIDE.md#torrents)).

### Added

- Control a focused torrent with Start, priority, and Delete icons, and purge downloaded data without removing torrent entries ([user guide](USER_GUIDE.md#torrents)).

### Removed

- Remove the manual Add Torrent and unlisted-file Clean Cache actions while keeping website link import and the cache-size hint ([user guide](USER_GUIDE.md#torrents)).

### Fixed

- Continue manually started torrent downloads while browsing websites with Torrents closed, and apply saved file choices when metadata arrives ([user guide](docs/USER_GUIDE.md#background-downloads), [development history](docs/agent/DEVELOPMENT_HISTORY.md#2026-10-04--native-tvos-pages-and-torrent-library-follow-up)).
- Return from a torrent's file list to the overall list with Back and preserve the proportions of VLC control symbols ([user guide](USER_GUIDE.md#torrents)).

## 2.16.0 - 2026-10-04

### Changed

- Wait for file selection before downloading payloads of newly imported torrents so unwanted files stay skipped ([user guide](USER_GUIDE.md#torrents), [development history](DEVELOPMENT_HISTORY.md#2026-10-04--built-in-torrent-playback-on-apple-tv)).

### Added

- Open the built-in torrent library from website magnet and `.torrent` links, including new windows and recognized torrent download responses ([user guide](USER_GUIDE.md#torrents)).
- Play selected torrent media through embedded TVVLCKit with buffering, remote controls, file navigation and direct opening of completed files ([user guide](USER_GUIDE.md#torrents), [torrent architecture](TORRENTS.md)).
- Continue manually started torrent downloads after leaving the browser with experimental Keep Alive enabled; a 2 GB torrent completed after five minutes with another video app playing on Apple TV ([user guide](docs/USER_GUIDE.md#background-downloads), [development history](docs/agent/DEVELOPMENT_HISTORY.md#2026-10-04--tvos-background-task-experiment)).
- Resume verified torrent pieces across app launches to avoid repeating full checks of cached files ([torrent architecture](TORRENTS.md)).
- Reclaim unlisted torrent cache files with a confirmation action and remove cached payloads when deleting a torrent ([user guide](USER_GUIDE.md#torrents)).

## 2.15.26 - 2026-10-04

### Fixed

- Show the saved zoom percentage on Reset Zoom and refresh it immediately after Zoom In, Zoom Out, or Reset Zoom while the menu stays open ([user guide](USER_GUIDE.md#main-menu)).

## 2.15.25 - 2026-10-02

### Fixed

- Enlarge page text and content together with WebKit view scale while keeping the page aligned from the left after zoom and relaunch ([user guide](USER_GUIDE.md#main-menu), [development history](DEVELOPMENT_HISTORY.md#2026-10-02--page-zoom-for-reading)).

## 2.15.24 - 2026-10-01

### Fixed

- Prevent Zoom Out at 50% from wrapping to 200% and discard stale horizontal offsets when restoring a tab ([development history](DEVELOPMENT_HISTORY.md#2026-10-02--page-zoom-for-reading)).

## 2.15.23 - 2026-10-01

### Fixed

- Prevent native video diagnostics from writing object payloads containing request headers, signed URLs, page content, or detailed errors to logs ([diagnostic privacy](USER_GUIDE.md#native-video-diagnostic-privacy)).

## 2.15.22 - 2026-10-01

_Retrospective numbering for tvOSofaBrowse, without published releases or Git tags; see the [development history](DEVELOPMENT_HISTORY.md) for implementation dates, decisions, verification and reversals, and the [roadmap](ROADMAP.md) for future work._

### Changed

- Focus the domain button when opening the menu so address entry or search is immediately available ([`1008e01`][1008e01]).
- Update the in-app guide for video arrows, history buttons beside the domain, and Double Up closing a card only in the tab overview ([user guide](USER_GUIDE.md)).

### Added

- Document remote controls, custom players, tabs, history, local recovery and diagnostics in a detailed user guide ([user guide](USER_GUIDE.md)).

### Fixed

- Preserve episode selection and other state saved by websites across launches through a shared persistent WebKit data store in a writable directory ([`95e6264`][95e6264]).
- Consume every Back/Menu press phase so opening the menu or returning from an overlay does not exit to the Apple TV home screen ([`d7987c2`][d7987c2]).
- Capture tab history for URL changes without a full page load, including pushState navigation ([`d7987c2`][d7987c2]).
- Preserve Forward entries when restoring the current page or following its redirect ([`d7987c2`][d7987c2]).
- Clear the saved session after closing every ordinary tab so closed tabs do not return at launch ([`d7987c2`][d7987c2]).
- Keep history deletion and Favorite writes consistent with the backup through checked transactions and rollback on failure ([`d7987c2`][d7987c2]).
- Turn the magnifier off after 30 seconds without cursor activity and require manual reactivation ([`84b0d33`][84b0d33]).

## 2.15.0 - 2026-10-01

### Added

- Add Website Logging ON/OFF in Debug to enable website diagnostics without reloading and remember the setting across launches ([`95e6264`][95e6264]).
- Log localStorage operations and available player state inside iframes to investigate lost episode, season or playback position ([`95e6264`][95e6264]).
- Rotate the diagnostic file and record key names and lengths instead of localStorage or cookie values ([`95e6264`][95e6264]).

## 2.14.0 - 2026-10-01

### Added

- Back up the complete history, Favorites and tab navigation in a compressed local SQLite snapshot so losing the main database does not require starting over ([`d7987c2`][d7987c2]).
- Restore a missing, empty or damaged database automatically after validating the snapshot ([`d7987c2`][d7987c2]).
- Refresh the backup after writes and explicit deletion without resurrecting deleted records from an outdated snapshot ([`d7987c2`][d7987c2]).
- Respect the preferences storage budget without automatically trimming history when a new snapshot does not fit ([`d7987c2`][d7987c2]).

## 2.13.0 - 2026-10-01

### Changed

- Store the complete tab session in SQLite, including the active tab, URL/title lists and current positions, to continue navigation after relaunch ([`d7987c2`][d7987c2]).
- Synchronize each tab model with WebKit's navigation list instead of retaining only the last URL ([`d7987c2`][d7987c2]).

## 2.12.0 - 2026-09-29

### Changed

- Assign Left/Right to seeking video by 10 seconds and keep browser Back/Forward on the menu buttons beside the domain ([`8ba451f`][8ba451f]).
- Combine Back, domain and Forward in one menu control and display the compact domain until the full URL editor opens ([`8ba451f`][8ba451f]).

### Removed

- Remove the permanent top bar, its focus mode and visibility settings to give pages and video the entire screen ([`8ba451f`][8ba451f]).

### Fixed

- Seek accessible HTML video, the active iframe or the native player without immediately navigating away through browser history ([`8ba451f`][8ba451f]).
- Raise focused navigation buttons above the address field so their hover state remains visible ([`8ba451f`][8ba451f]).

## 2.11.0 - 2026-09-29

### Changed

- Open the latest 20 addresses through History in the menu and provide All History at the end ([`89882fa`][89882fa]).
- Open an All History row with Center and toggle its selection with Play/Pause ([`89882fa`][89882fa]).
- Use Center to open New Tab entries and Play/Pause for Favorite editing or history deletion ([`89882fa`][89882fa]).

### Added

- Add a visual guide with a remote illustration and six gesture cards to introduce browsing without a long instruction screen ([`ecace46`][ecace46]).
- Support cursor and arrow navigation in the guide and add Show this guide at launch ([`ecace46`][ecace46]).

### Fixed

- Restore cursor visibility and movement on a new touch after arrow navigation or inactivity ([`ab11d5e`][ab11d5e]).
- Retain the selected New Tab section after a contextual action refreshes the page ([`89882fa`][89882fa]).
- Fit the complete Start Browsing button in the in-app guide ([`ecace46`][ecace46]).

## 2.10.0 - 2026-09-29

### Added

- Support starting and controlling custom iframe players so movies and episodes can be watched with the remote on websites where Play previously did not respond ([`ecace46`][ecace46]).
- Forward Center clicks into nested iframes, including cross-origin frames inside Shadow DOM, with local coordinates and pointer/mouse events ([`ecace46`][ecace46]).
- Forward Play/Pause and fullscreen exit between the page and player to retain remote control after expanding video ([`ecace46`][ecace46]).
- Expand website players in theater mode with a dimmed background and restore the original page appearance on exit ([`ecace46`][ecace46]).

### Fixed

- Raise the player and its ancestor containers above other page layers so banners or site menus do not cover expanded video ([`ecace46`][ecace46]).

## 2.9.0 - 2026-09-29

### Added

- Add a cursor magnifier to read and accurately click small website and player controls from the sofa ([`ecace46`][ecace46]).
- Toggle the magnifier by holding Center for more than 0.65 seconds or using the menu and halve cursor sensitivity while it is enabled ([`ecace46`][ecace46]).

### Fixed

- Refresh the magnifier every 0.25 seconds so changes after a click appear without moving the cursor ([`ecace46`][ecace46]).
- Center the magnified area on the cursor near screen edges so controls at the edge remain reachable ([`ecace46`][ecace46]).
- Distinguish a Center hold from a short press so toggling the magnifier does not accidentally click the website ([`ecace46`][ecace46]).

## 2.8.0 - 2026-09-29

### Added

- Add an Ad Block toggle and WebKit content rules to block advertising and tracking requests ([`ecace46`][ecace46]).

### Fixed

- Remove rules on OFF across open tabs without recreating WebViews so toggling Ad Block preserves their navigation ([`ecace46`][ecace46]).
- Distinguish failed rule removal from successful OFF and use the available runtime fallback ([`ecace46`][ecace46]).

## 2.7.0 - 2026-09-29

### Changed

- Scale the entire page through WebKit instead of changing only the font, with a 50–200% range, 10% steps and Reset Zoom to 100% ([`ecace46`][ecace46]).
- Remember zoom across launches and keep the menu open for repeated adjustments ([`ecace46`][ecace46]).

### Fixed

- Recalculate horizontal offsets on Zoom In/Out to preserve the visible page center ([`ecace46`][ecace46]).
- Reapply the saved zoom after a page finishes loading ([`ecace46`][ecace46]).

## 2.6.0 - 2026-09-29

### Added

- Edit Favorite titles and URLs or delete Favorites directly on Apple TV ([`ecace46`][ecace46]).

### Fixed

- Isolate editor input from the New Tab page behind it so arrows do not move the hidden selection ([`ecace46`][ecace46]).
- Match editor button contrast to the glass menu so the focused action remains readable ([`ecace46`][ecace46]).

## 2.5.0 - 2026-09-29

### Added

- Store complete browsing history and Favorites in SQLite without age-based pruning instead of limited preferences lists ([`ecace46`][ecace46]).
- Add All History with selectable rows, Select All/Deselect, opening one entry and deleting selected entries ([`ecace46`][ecace46]).
- Add confirmed Clear History and place actions above the list to avoid scrolling through thousands of rows to find them ([`ecace46`][ecace46]).

### Fixed

- Open the existing database before creating a new one so history and Favorites remain accessible after changes to directory priority ([`ecace46`][ecace46]).
- Make history selection reachable through the row and preserve readable text on focus ([`ecace46`][ecace46]).
- Show the record count in the clear confirmation and provide an accessible focus target in an empty list ([`ecace46`][ecace46]).

## 2.4.0 - 2026-09-29

### Changed

- Present New Tab as a separate plus button so an empty page does not occupy a saved tab slot ([`ecace46`][ecace46]).
- Keep a separate URL history for each tab and return from the overview to the previously active page ([`ecace46`][ecace46]).

### Removed

- Remove the five-tab limit to keep more useful pages open ([`ecace46`][ecace46]).

### Fixed

- Select and close the correct tab after filtering temporary cards ([`ecace46`][ecace46]).
- Remap the active index when restoring a session without empty New Tab entries ([`ecace46`][ecace46]).
- Prevent one Back press from dismissing the tab overview repeatedly ([`ecace46`][ecace46]).

## 2.3.0 - 2026-09-29

### Added

- Add a New Tab page with search, Favorite tiles and the ten latest URLs to open familiar websites without entering their addresses ([`ecace46`][ecace46]).
- Navigate sections with arrows and scroll the selected entry into view ([`ecace46`][ecace46]).

### Fixed

- Activate the arrow-selected entry with Center instead of the entry under the previous cursor position ([`ecace46`][ecace46]).
- Return from New Tab with Back to the last active tab when one is available ([`ecace46`][ecace46]).

## 2.2.0 - 2026-09-29

### Changed

- Replace the previous menus with a tiled side panel grouped into Quick Actions, Settings and Tools with visible ON/OFF states ([`ecace46`][ecace46]).
- Place zoom controls in a dedicated first row, other tiles in pairs and diagnostic options under Debug ([`ecace46`][ecace46]).
- Switch Mobile Site without deliberately clearing cookies or website data so changing presentation preserves site state ([`ecace46`][ecace46]).

### Removed

- Remove the malfunctioning Fit to Screen option and its scaling mode ([`ecace46`][ecace46]).

### Fixed

- Raise the focused button above its neighbors and retain icon contrast on focus ([`ecace46`][ecace46]).
- Calculate zoom row widths so Zoom In does not wrap onto a separate row ([`ecace46`][ecace46]).

## 2.1.0 - 2026-09-29

### Changed

- Browse with one Siri Remote using touchpad movement, Center clicks and smooth Up/Down scrolling ([`ecace46`][ecace46]).
- Scroll continuously while holding Up/Down with gradual acceleration and stop on release ([`ecace46`][ecace46]).
- Use Play/Pause for video and Double Left for the tab overview ([`ecace46`][ecace46]).
- Hide the cursor on inactivity or arrow navigation so it does not obstruct viewing ([`ecace46`][ecace46]).

### Fixed

- Query hover asynchronously and transform WebView coordinates so cursor movement does not enter a nested event wait ([`ecace46`][ecace46]).
- Handle cancelled navigation as NSURLErrorCancelled so reaching a history boundary does not block later presses ([`ecace46`][ecace46]).
- Limit Clear Cache to resource caches while preserving other website data and browser history ([`ecace46`][ecace46]).
- Use the available cookie fallback when the asynchronous store times out ([`ecace46`][ecace46]).

## 2.0.0 - 2026-03-08

_Fork baseline with WebKit, tabs, a cursor, basic history and native/WebKit video paths ([`e245b8f`][e245b8f])._

[e245b8f]: https://github.com/just-better-code/tvOSofaBrowse/commit/e245b8f
[ecace46]: https://github.com/just-better-code/tvOSofaBrowse/commit/ecace46
[89882fa]: https://github.com/just-better-code/tvOSofaBrowse/commit/89882fa
[ab11d5e]: https://github.com/just-better-code/tvOSofaBrowse/commit/ab11d5e
[8ba451f]: https://github.com/just-better-code/tvOSofaBrowse/commit/8ba451f
[84b0d33]: https://github.com/just-better-code/tvOSofaBrowse/commit/84b0d33
[d7987c2]: https://github.com/just-better-code/tvOSofaBrowse/commit/d7987c2
[95e6264]: https://github.com/just-better-code/tvOSofaBrowse/commit/95e6264
[1008e01]: https://github.com/just-better-code/tvOSofaBrowse/commit/1008e01
