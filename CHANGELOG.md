# Changelog

## 2.15.23 - 2026-10-01

### Fixed

- Prevent native video diagnostics from writing object payloads containing request headers, signed URLs, page content, or detailed errors to logs ([diagnostic privacy](USER_GUIDE.md#native-video-diagnostic-privacy)).

## 2.15.22 - 2026-10-01

_Retrospective numbering for just-better-code version, without published releases or Git tags; see the [development history](DEVELOPMENT_HISTORY.md) for implementation dates, decisions, verification and reversals, and the [roadmap](ROADMAP.md) for future work._

### Changed

- Focus the domain button when opening the menu so address entry or search is immediately available ([`74c6c0c`][74c6c0c]).
- Update the in-app guide for video arrows, history buttons beside the domain, and Double Up closing a card only in the tab overview ([user guide](USER_GUIDE.md)).

### Added

- Document remote controls, custom players, tabs, history, local recovery and diagnostics in a detailed user guide ([user guide](USER_GUIDE.md)).

### Fixed

- Preserve episode selection and other state saved by websites across launches through a shared persistent WebKit data store in a writable directory ([`3cf73b8`][3cf73b8]).
- Consume every Back/Menu press phase so opening the menu or returning from an overlay does not exit to the Apple TV home screen ([`2bdb5a2`][2bdb5a2]).
- Capture tab history for URL changes without a full page load, including pushState navigation ([`2bdb5a2`][2bdb5a2]).
- Preserve Forward entries when restoring the current page or following its redirect ([`2bdb5a2`][2bdb5a2]).
- Clear the saved session after closing every ordinary tab so closed tabs do not return at launch ([`2bdb5a2`][2bdb5a2]).
- Keep history deletion and Favorite writes consistent with the backup through checked transactions and rollback on failure ([`2bdb5a2`][2bdb5a2]).
- Turn the magnifier off after 30 seconds without cursor activity and require manual reactivation ([`b843a5d`][b843a5d]).

## 2.15.0 - 2026-10-01

### Added

- Add Website Logging ON/OFF in Debug to enable website diagnostics without reloading and remember the setting across launches ([`3cf73b8`][3cf73b8]).
- Log localStorage operations and available player state inside iframes to investigate lost episode, season or playback position ([`3cf73b8`][3cf73b8]).
- Rotate the diagnostic file and record key names and lengths instead of localStorage or cookie values ([`3cf73b8`][3cf73b8]).

## 2.14.0 - 2026-10-01

### Added

- Back up the complete history, Favorites and tab navigation in a compressed local SQLite snapshot so losing the main database does not require starting over ([`2bdb5a2`][2bdb5a2]).
- Restore a missing, empty or damaged database automatically after validating the snapshot ([`2bdb5a2`][2bdb5a2]).
- Refresh the backup after writes and explicit deletion without resurrecting deleted records from an outdated snapshot ([`2bdb5a2`][2bdb5a2]).
- Respect the preferences storage budget without automatically trimming history when a new snapshot does not fit ([`2bdb5a2`][2bdb5a2]).

## 2.13.0 - 2026-10-01

### Changed

- Store the complete tab session in SQLite, including the active tab, URL/title lists and current positions, to continue navigation after relaunch ([`2bdb5a2`][2bdb5a2]).
- Synchronize each tab model with WebKit's navigation list instead of retaining only the last URL ([`2bdb5a2`][2bdb5a2]).

## 2.12.0 - 2026-09-29

### Changed

- Assign Left/Right to seeking video by 10 seconds and keep browser Back/Forward on the menu buttons beside the domain ([`7f2289c`][7f2289c]).
- Combine Back, domain and Forward in one menu control and display the compact domain until the full URL editor opens ([`7f2289c`][7f2289c]).

### Removed

- Remove the permanent top bar, its focus mode and visibility settings to give pages and video the entire screen ([`7f2289c`][7f2289c]).

### Fixed

- Seek accessible HTML video, the active iframe or the native player without immediately navigating away through browser history ([`7f2289c`][7f2289c]).
- Raise focused navigation buttons above the address field so their hover state remains visible ([`7f2289c`][7f2289c]).

## 2.11.0 - 2026-09-29

### Changed

- Open the latest 20 addresses through History in the menu and provide All History at the end ([`43f8e09`][43f8e09]).
- Open an All History row with Center and toggle its selection with Play/Pause ([`43f8e09`][43f8e09]).
- Use Center to open New Tab entries and Play/Pause for Favorite editing or history deletion ([`43f8e09`][43f8e09]).

### Added

- Add a visual guide with a remote illustration and six gesture cards to introduce browsing without a long instruction screen ([`bf4ef6b`][bf4ef6b]).
- Support cursor and arrow navigation in the guide and add Show this guide at launch ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Restore cursor visibility and movement on a new touch after arrow navigation or inactivity ([`52180be`][52180be]).
- Retain the selected New Tab section after a contextual action refreshes the page ([`43f8e09`][43f8e09]).
- Fit the complete Start Browsing button in the in-app guide ([`bf4ef6b`][bf4ef6b]).

## 2.10.0 - 2026-09-29

### Added

- Support starting and controlling custom iframe players so movies and episodes can be watched with the remote on websites where Play previously did not respond ([`bf4ef6b`][bf4ef6b]).
- Forward Center clicks into nested iframes, including cross-origin frames inside Shadow DOM, with local coordinates and pointer/mouse events ([`bf4ef6b`][bf4ef6b]).
- Forward Play/Pause and fullscreen exit between the page and player to retain remote control after expanding video ([`bf4ef6b`][bf4ef6b]).
- Expand website players in theater mode with a dimmed background and restore the original page appearance on exit ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Raise the player and its ancestor containers above other page layers so banners or site menus do not cover expanded video ([`bf4ef6b`][bf4ef6b]).

## 2.9.0 - 2026-09-29

### Added

- Add a cursor magnifier to read and accurately click small website and player controls from the sofa ([`bf4ef6b`][bf4ef6b]).
- Toggle the magnifier by holding Center for more than 0.65 seconds or using the menu and halve cursor sensitivity while it is enabled ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Refresh the magnifier every 0.25 seconds so changes after a click appear without moving the cursor ([`bf4ef6b`][bf4ef6b]).
- Center the magnified area on the cursor near screen edges so controls at the edge remain reachable ([`bf4ef6b`][bf4ef6b]).
- Distinguish a Center hold from a short press so toggling the magnifier does not accidentally click the website ([`bf4ef6b`][bf4ef6b]).

## 2.8.0 - 2026-09-29

### Added

- Add an Ad Block toggle and WebKit content rules to block advertising and tracking requests ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Remove rules on OFF across open tabs without recreating WebViews so toggling Ad Block preserves their navigation ([`bf4ef6b`][bf4ef6b]).
- Distinguish failed rule removal from successful OFF and use the available runtime fallback ([`bf4ef6b`][bf4ef6b]).

## 2.7.0 - 2026-09-29

### Changed

- Scale the entire page through WebKit instead of changing only the font, with a 50–200% range, 10% steps and Reset Zoom to 100% ([`bf4ef6b`][bf4ef6b]).
- Remember zoom across launches and keep the menu open for repeated adjustments ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Recalculate horizontal offsets on Zoom In/Out to preserve the visible page center ([`bf4ef6b`][bf4ef6b]).
- Reapply the saved zoom after a page finishes loading ([`bf4ef6b`][bf4ef6b]).

## 2.6.0 - 2026-09-29

### Added

- Edit Favorite titles and URLs or delete Favorites directly on Apple TV ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Isolate editor input from the New Tab page behind it so arrows do not move the hidden selection ([`bf4ef6b`][bf4ef6b]).
- Match editor button contrast to the glass menu so the focused action remains readable ([`bf4ef6b`][bf4ef6b]).

## 2.5.0 - 2026-09-29

### Added

- Store complete browsing history and Favorites in SQLite without age-based pruning instead of limited preferences lists ([`bf4ef6b`][bf4ef6b]).
- Add All History with selectable rows, Select All/Deselect, opening one entry and deleting selected entries ([`bf4ef6b`][bf4ef6b]).
- Add confirmed Clear History and place actions above the list to avoid scrolling through thousands of rows to find them ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Open the existing database before creating a new one so history and Favorites remain accessible after changes to directory priority ([`bf4ef6b`][bf4ef6b]).
- Make history selection reachable through the row and preserve readable text on focus ([`bf4ef6b`][bf4ef6b]).
- Show the record count in the clear confirmation and provide an accessible focus target in an empty list ([`bf4ef6b`][bf4ef6b]).

## 2.4.0 - 2026-09-29

### Changed

- Present New Tab as a separate plus button so an empty page does not occupy a saved tab slot ([`bf4ef6b`][bf4ef6b]).
- Keep a separate URL history for each tab and return from the overview to the previously active page ([`bf4ef6b`][bf4ef6b]).

### Removed

- Remove the five-tab limit to keep more useful pages open ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Select and close the correct tab after filtering temporary cards ([`bf4ef6b`][bf4ef6b]).
- Remap the active index when restoring a session without empty New Tab entries ([`bf4ef6b`][bf4ef6b]).
- Prevent one Back press from dismissing the tab overview repeatedly ([`bf4ef6b`][bf4ef6b]).

## 2.3.0 - 2026-09-29

### Added

- Add a New Tab page with search, Favorite tiles and the ten latest URLs to open familiar websites without entering their addresses ([`bf4ef6b`][bf4ef6b]).
- Navigate sections with arrows and scroll the selected entry into view ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Activate the arrow-selected entry with Center instead of the entry under the previous cursor position ([`bf4ef6b`][bf4ef6b]).
- Return from New Tab with Back to the last active tab when one is available ([`bf4ef6b`][bf4ef6b]).

## 2.2.0 - 2026-09-29

### Changed

- Replace the previous menus with a tiled side panel grouped into Quick Actions, Settings and Tools with visible ON/OFF states ([`bf4ef6b`][bf4ef6b]).
- Place zoom controls in a dedicated first row, other tiles in pairs and diagnostic options under Debug ([`bf4ef6b`][bf4ef6b]).
- Switch Mobile Site without deliberately clearing cookies or website data so changing presentation preserves site state ([`bf4ef6b`][bf4ef6b]).

### Removed

- Remove the malfunctioning Fit to Screen option and its scaling mode ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Raise the focused button above its neighbors and retain icon contrast on focus ([`bf4ef6b`][bf4ef6b]).
- Calculate zoom row widths so Zoom In does not wrap onto a separate row ([`bf4ef6b`][bf4ef6b]).

## 2.1.0 - 2026-09-29

### Changed

- Browse with one Siri Remote using touchpad movement, Center clicks and smooth Up/Down scrolling ([`bf4ef6b`][bf4ef6b]).
- Scroll continuously while holding Up/Down with gradual acceleration and stop on release ([`bf4ef6b`][bf4ef6b]).
- Use Play/Pause for video and Double Left for the tab overview ([`bf4ef6b`][bf4ef6b]).
- Hide the cursor on inactivity or arrow navigation so it does not obstruct viewing ([`bf4ef6b`][bf4ef6b]).

### Fixed

- Query hover asynchronously and transform WebView coordinates so cursor movement does not enter a nested event wait ([`bf4ef6b`][bf4ef6b]).
- Handle cancelled navigation as NSURLErrorCancelled so reaching a history boundary does not block later presses ([`bf4ef6b`][bf4ef6b]).
- Limit Clear Cache to resource caches while preserving other website data and browser history ([`bf4ef6b`][bf4ef6b]).
- Use the available cookie fallback when the asynchronous store times out ([`bf4ef6b`][bf4ef6b]).

## 2.0.0 - 2026-03-08

_Fork baseline with WebKit, tabs, a cursor, basic history and native/WebKit video paths ([`97c801a`][97c801a])._

[97c801a]: https://github.com/just-better-code/tvOSBrowser/commit/97c801a
[bf4ef6b]: https://github.com/just-better-code/tvOSBrowser/commit/bf4ef6b
[43f8e09]: https://github.com/just-better-code/tvOSBrowser/commit/43f8e09
[52180be]: https://github.com/just-better-code/tvOSBrowser/commit/52180be
[7f2289c]: https://github.com/just-better-code/tvOSBrowser/commit/7f2289c
[b843a5d]: https://github.com/just-better-code/tvOSBrowser/commit/b843a5d
[2bdb5a2]: https://github.com/just-better-code/tvOSBrowser/commit/2bdb5a2
[3cf73b8]: https://github.com/just-better-code/tvOSBrowser/commit/3cf73b8
[74c6c0c]: https://github.com/just-better-code/tvOSBrowser/commit/74c6c0c
