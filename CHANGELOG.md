# Changelog

## 2.15.23 - 2026-10-01

### Fixed

- Prevent native video diagnostics from writing object payloads containing request headers, signed URLs, page content, or detailed errors to logs ([diagnostic privacy](USER_GUIDE.md#native-video-diagnostic-privacy)).

## 2.15.22 - 2026-10-01

_Retrospective numbering for just-better-code version, without published releases or Git tags; see the [development history](DEVELOPMENT_HISTORY.md) for implementation dates, decisions, verification and reversals, and the [roadmap](ROADMAP.md) for future work._

### Changed

- Focus the domain button when opening the menu so address entry or search is immediately available ([`a4e3b21`][a4e3b21]).
- Update the in-app guide for video arrows, history buttons beside the domain, and Double Up closing a card only in the tab overview ([user guide](USER_GUIDE.md)).

### Added

- Document remote controls, custom players, tabs, history, local recovery and diagnostics in a detailed user guide ([user guide](USER_GUIDE.md)).

### Fixed

- Preserve episode selection and other state saved by websites across launches through a shared persistent WebKit data store in a writable directory ([`595c1f9`][595c1f9]).
- Consume every Back/Menu press phase so opening the menu or returning from an overlay does not exit to the Apple TV home screen ([`cdee449`][cdee449]).
- Capture tab history for URL changes without a full page load, including pushState navigation ([`cdee449`][cdee449]).
- Preserve Forward entries when restoring the current page or following its redirect ([`cdee449`][cdee449]).
- Clear the saved session after closing every ordinary tab so closed tabs do not return at launch ([`cdee449`][cdee449]).
- Keep history deletion and Favorite writes consistent with the backup through checked transactions and rollback on failure ([`cdee449`][cdee449]).
- Turn the magnifier off after 30 seconds without cursor activity and require manual reactivation ([`bdda665`][bdda665]).

## 2.15.0 - 2026-10-01

### Added

- Add Website Logging ON/OFF in Debug to enable website diagnostics without reloading and remember the setting across launches ([`595c1f9`][595c1f9]).
- Log localStorage operations and available player state inside iframes to investigate lost episode, season or playback position ([`595c1f9`][595c1f9]).
- Rotate the diagnostic file and record key names and lengths instead of localStorage or cookie values ([`595c1f9`][595c1f9]).

## 2.14.0 - 2026-10-01

### Added

- Back up the complete history, Favorites and tab navigation in a compressed local SQLite snapshot so losing the main database does not require starting over ([`cdee449`][cdee449]).
- Restore a missing, empty or damaged database automatically after validating the snapshot ([`cdee449`][cdee449]).
- Refresh the backup after writes and explicit deletion without resurrecting deleted records from an outdated snapshot ([`cdee449`][cdee449]).
- Respect the preferences storage budget without automatically trimming history when a new snapshot does not fit ([`cdee449`][cdee449]).

## 2.13.0 - 2026-10-01

### Changed

- Store the complete tab session in SQLite, including the active tab, URL/title lists and current positions, to continue navigation after relaunch ([`cdee449`][cdee449]).
- Synchronize each tab model with WebKit's navigation list instead of retaining only the last URL ([`cdee449`][cdee449]).

## 2.12.0 - 2026-09-29

### Changed

- Assign Left/Right to seeking video by 10 seconds and keep browser Back/Forward on the menu buttons beside the domain ([`95e289a`][95e289a]).
- Combine Back, domain and Forward in one menu control and display the compact domain until the full URL editor opens ([`95e289a`][95e289a]).

### Removed

- Remove the permanent top bar, its focus mode and visibility settings to give pages and video the entire screen ([`95e289a`][95e289a]).

### Fixed

- Seek accessible HTML video, the active iframe or the native player without immediately navigating away through browser history ([`95e289a`][95e289a]).
- Raise focused navigation buttons above the address field so their hover state remains visible ([`95e289a`][95e289a]).

## 2.11.0 - 2026-09-29

### Changed

- Open the latest 20 addresses through History in the menu and provide All History at the end ([`d2a7bdb`][d2a7bdb]).
- Open an All History row with Center and toggle its selection with Play/Pause ([`d2a7bdb`][d2a7bdb]).
- Use Center to open New Tab entries and Play/Pause for Favorite editing or history deletion ([`d2a7bdb`][d2a7bdb]).

### Added

- Add a visual guide with a remote illustration and six gesture cards to introduce browsing without a long instruction screen ([`0e1d6b5`][0e1d6b5]).
- Support cursor and arrow navigation in the guide and add Show this guide at launch ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Restore cursor visibility and movement on a new touch after arrow navigation or inactivity ([`eca1e02`][eca1e02]).
- Retain the selected New Tab section after a contextual action refreshes the page ([`d2a7bdb`][d2a7bdb]).
- Fit the complete Start Browsing button in the in-app guide ([`0e1d6b5`][0e1d6b5]).

## 2.10.0 - 2026-09-29

### Added

- Support starting and controlling custom iframe players so movies and episodes can be watched with the remote on websites where Play previously did not respond ([`0e1d6b5`][0e1d6b5]).
- Forward Center clicks into nested iframes, including cross-origin frames inside Shadow DOM, with local coordinates and pointer/mouse events ([`0e1d6b5`][0e1d6b5]).
- Forward Play/Pause and fullscreen exit between the page and player to retain remote control after expanding video ([`0e1d6b5`][0e1d6b5]).
- Expand website players in theater mode with a dimmed background and restore the original page appearance on exit ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Raise the player and its ancestor containers above other page layers so banners or site menus do not cover expanded video ([`0e1d6b5`][0e1d6b5]).

## 2.9.0 - 2026-09-29

### Added

- Add a cursor magnifier to read and accurately click small website and player controls from the sofa ([`0e1d6b5`][0e1d6b5]).
- Toggle the magnifier by holding Center for more than 0.65 seconds or using the menu and halve cursor sensitivity while it is enabled ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Refresh the magnifier every 0.25 seconds so changes after a click appear without moving the cursor ([`0e1d6b5`][0e1d6b5]).
- Center the magnified area on the cursor near screen edges so controls at the edge remain reachable ([`0e1d6b5`][0e1d6b5]).
- Distinguish a Center hold from a short press so toggling the magnifier does not accidentally click the website ([`0e1d6b5`][0e1d6b5]).

## 2.8.0 - 2026-09-29

### Added

- Add an Ad Block toggle and WebKit content rules to block advertising and tracking requests ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Remove rules on OFF across open tabs without recreating WebViews so toggling Ad Block preserves their navigation ([`0e1d6b5`][0e1d6b5]).
- Distinguish failed rule removal from successful OFF and use the available runtime fallback ([`0e1d6b5`][0e1d6b5]).

## 2.7.0 - 2026-09-29

### Changed

- Scale the entire page through WebKit instead of changing only the font, with a 50–200% range, 10% steps and Reset Zoom to 100% ([`0e1d6b5`][0e1d6b5]).
- Remember zoom across launches and keep the menu open for repeated adjustments ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Recalculate horizontal offsets on Zoom In/Out to preserve the visible page center ([`0e1d6b5`][0e1d6b5]).
- Reapply the saved zoom after a page finishes loading ([`0e1d6b5`][0e1d6b5]).

## 2.6.0 - 2026-09-29

### Added

- Edit Favorite titles and URLs or delete Favorites directly on Apple TV ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Isolate editor input from the New Tab page behind it so arrows do not move the hidden selection ([`0e1d6b5`][0e1d6b5]).
- Match editor button contrast to the glass menu so the focused action remains readable ([`0e1d6b5`][0e1d6b5]).

## 2.5.0 - 2026-09-29

### Added

- Store complete browsing history and Favorites in SQLite without age-based pruning instead of limited preferences lists ([`0e1d6b5`][0e1d6b5]).
- Add All History with selectable rows, Select All/Deselect, opening one entry and deleting selected entries ([`0e1d6b5`][0e1d6b5]).
- Add confirmed Clear History and place actions above the list to avoid scrolling through thousands of rows to find them ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Open the existing database before creating a new one so history and Favorites remain accessible after changes to directory priority ([`0e1d6b5`][0e1d6b5]).
- Make history selection reachable through the row and preserve readable text on focus ([`0e1d6b5`][0e1d6b5]).
- Show the record count in the clear confirmation and provide an accessible focus target in an empty list ([`0e1d6b5`][0e1d6b5]).

## 2.4.0 - 2026-09-29

### Changed

- Present New Tab as a separate plus button so an empty page does not occupy a saved tab slot ([`0e1d6b5`][0e1d6b5]).
- Keep a separate URL history for each tab and return from the overview to the previously active page ([`0e1d6b5`][0e1d6b5]).

### Removed

- Remove the five-tab limit to keep more useful pages open ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Select and close the correct tab after filtering temporary cards ([`0e1d6b5`][0e1d6b5]).
- Remap the active index when restoring a session without empty New Tab entries ([`0e1d6b5`][0e1d6b5]).
- Prevent one Back press from dismissing the tab overview repeatedly ([`0e1d6b5`][0e1d6b5]).

## 2.3.0 - 2026-09-29

### Added

- Add a New Tab page with search, Favorite tiles and the ten latest URLs to open familiar websites without entering their addresses ([`0e1d6b5`][0e1d6b5]).
- Navigate sections with arrows and scroll the selected entry into view ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Activate the arrow-selected entry with Center instead of the entry under the previous cursor position ([`0e1d6b5`][0e1d6b5]).
- Return from New Tab with Back to the last active tab when one is available ([`0e1d6b5`][0e1d6b5]).

## 2.2.0 - 2026-09-29

### Changed

- Replace the previous menus with a tiled side panel grouped into Quick Actions, Settings and Tools with visible ON/OFF states ([`0e1d6b5`][0e1d6b5]).
- Place zoom controls in a dedicated first row, other tiles in pairs and diagnostic options under Debug ([`0e1d6b5`][0e1d6b5]).
- Switch Mobile Site without deliberately clearing cookies or website data so changing presentation preserves site state ([`0e1d6b5`][0e1d6b5]).

### Removed

- Remove the malfunctioning Fit to Screen option and its scaling mode ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Raise the focused button above its neighbors and retain icon contrast on focus ([`0e1d6b5`][0e1d6b5]).
- Calculate zoom row widths so Zoom In does not wrap onto a separate row ([`0e1d6b5`][0e1d6b5]).

## 2.1.0 - 2026-09-29

### Changed

- Browse with one Siri Remote using touchpad movement, Center clicks and smooth Up/Down scrolling ([`0e1d6b5`][0e1d6b5]).
- Scroll continuously while holding Up/Down with gradual acceleration and stop on release ([`0e1d6b5`][0e1d6b5]).
- Use Play/Pause for video and Double Left for the tab overview ([`0e1d6b5`][0e1d6b5]).
- Hide the cursor on inactivity or arrow navigation so it does not obstruct viewing ([`0e1d6b5`][0e1d6b5]).

### Fixed

- Query hover asynchronously and transform WebView coordinates so cursor movement does not enter a nested event wait ([`0e1d6b5`][0e1d6b5]).
- Handle cancelled navigation as NSURLErrorCancelled so reaching a history boundary does not block later presses ([`0e1d6b5`][0e1d6b5]).
- Limit Clear Cache to resource caches while preserving other website data and browser history ([`0e1d6b5`][0e1d6b5]).
- Use the available cookie fallback when the asynchronous store times out ([`0e1d6b5`][0e1d6b5]).

## 2.0.0 - 2026-03-08

_Fork baseline with WebKit, tabs, a cursor, basic history and native/WebKit video paths ([`9b90e0e`][9b90e0e])._

[9b90e0e]: https://github.com/just-better-code/tvOSBrowser/commit/9b90e0e
[0e1d6b5]: https://github.com/just-better-code/tvOSBrowser/commit/0e1d6b5
[d2a7bdb]: https://github.com/just-better-code/tvOSBrowser/commit/d2a7bdb
[eca1e02]: https://github.com/just-better-code/tvOSBrowser/commit/eca1e02
[95e289a]: https://github.com/just-better-code/tvOSBrowser/commit/95e289a
[bdda665]: https://github.com/just-better-code/tvOSBrowser/commit/bdda665
[cdee449]: https://github.com/just-better-code/tvOSBrowser/commit/cdee449
[595c1f9]: https://github.com/just-better-code/tvOSBrowser/commit/595c1f9
[a4e3b21]: https://github.com/just-better-code/tvOSBrowser/commit/a4e3b21
