# User Guide — tvOS Browser, just-better-code version

Current for **2.17.0**. Button names match the application.

## Quick start

1. Open the browser. On New Tab, choose a Favorite or history entry, or press Back/Menu to open the main menu.
2. The domain/address button receives initial menu focus. Press Center to enter an address or search query.
3. Slide on the touchpad to move the pointer and press Center to click a page control.
4. Press Up/Down to scroll. Hold a direction for continuous, accelerating scrolling.

Open the visual quick guide through **Menu → Tools → User Guide**. **Show this guide at launch** controls whether it appears at startup.

## Siri Remote controls

| Action | Control |
| --- | --- |
| Move the pointer | Slide on the touchpad |
| Click a link or button | Center |
| Scroll a page | Up/Down; hold to accelerate |
| Navigate tab history | Back/Forward beside the domain in the main menu |
| Open the tab overview | Double Left |
| Close the focused overview tab | Double Up or Play/Pause |
| Toggle the magnifier on a website | Hold Center |
| Open the menu or return from an overlay | Back/Menu, depending on context |
| Play/pause supported video | Play/Pause |

On app-owned pages, arrows move selection and Center activates the focused item. Hold Center for its context actions; Play/Pause performs the page's shortcut. Website controls retain their own behavior. The pointer hides on inactivity; a new touchpad movement brings it back.

### Back/Menu behavior

- On an ordinary page, open the main menu.
- In a menu, dialog, guide or tab overview, close that screen.
- In a torrent's file list, return to the overall torrent list; from the overall list, return to the browser.
- On New Tab, return to the previously active tab when available.
- With the magnifier enabled, turn it off before opening the menu.
- In a supported fullscreen player, leave fullscreen and return to the page.

Use the menu buttons beside the domain to navigate browser history. Left/Right on a page are reserved for video and do not open another page.

## Main menu

The domain button is focused when the menu opens, so Center immediately opens address editing.

The toolbar contains **Home**, **Reload Page**, the address, **New Tab** and **Tabs**. Back/Forward beside the domain use the active tab's history.

| Section | Actions |
| --- | --- |
| Quick Actions | Zoom Out, Reset Zoom, Zoom In, Add Favorite, History, Torrents |
| Settings | Ad Block, Magnifier, Full Screen Player, Mobile Site, Keep Alive |
| Tools | Debug, User Guide, Clear Cache, Clear Cookies, Clear History |

Zoom ranges from **50% to 200%**, in **10%** steps. It scales the text and page together, starts at the left edge after a change, and remembers the chosen percentage across tabs and launches. Reset Zoom shows the current percentage, updates after each zoom action, and restores **100%** when pressed. Mobile Site changes the User Agent; presentation depends on the website. If Ad Block interferes with a page or player, try disabling it and reloading.

Remaining pointer alignment and website layout issues are tracked in the [roadmap](ROADMAP.md).

The magnifier is also available through Settings → Magnifier. It turns off after **30 seconds without cursor activity**. Moving the cursor does not re-enable it; toggle it manually. Cursor movement is half as sensitive in magnifier mode for precise targeting.

## Tabs and New Tab

- Open the overview with **Tabs** or Double Left.
- Select a tab card and press Center to open it.
- The **+** card opens New Tab; an empty New Tab does not occupy a saved tab slot.
- Play/Pause closes the focused ordinary tab in the overview.
- Hold Center on a tab card for Open and Close actions.
- Double Up also closes the focused overview tab; repeated Up presses on a page scroll it.

The native New Tab page shows **Favorites** and recent history across the available screen width. Center opens an entry. **Play/Pause or Hold Center opens the selected entry's options**: Favorite actions or recent-visit actions.

The session saves ordinary tabs, the active tab and each tab's Back/Forward list. An empty New Tab is temporary and is not restored as an ordinary page.

## Favorites

1. Open the page to save.
2. Choose **Menu → Quick Actions → Add Favorite**.
3. Review the title and address, then save.

On New Tab, select a Favorite and press Play/Pause for editing and deletion options. Favorites are stored locally.

## History

**Menu → Quick Actions → History** lists up to 20 recent addresses. Choose **All History** for the complete list.

### All History

| Action | Control |
| --- | --- |
| Open an entry | Select its row and press Center |
| Select/deselect a row | Play/Pause on the row |
| Open row actions | Hold Center on the row |
| Select every entry | Select All |
| Open one selected entry | Open; exactly one row must be selected |
| Delete selected entries | Delete |
| Clear all visits | Clear All, then confirm |
| Close the list | Done or Back/Menu |

**Clear History** in the main menu also clears visits after confirmation. History is not automatically deleted by age.

## Video

- Use Center on the player's own controls under the pointer.
- Use Play/Pause to pause or resume supported video.
- Use Left/Right to seek supported video by **10 seconds**.
- A website's fullscreen button can expand its player with a dimmed background while retaining the cursor, Play/Pause and Back.
- **Settings → Full Screen Player** enables a separate tvOS player for an accessible direct media URL. It is not needed for expanding a website's own player.
- Use Back/Menu to leave a supported fullscreen mode.

The browser forwards clicks into supported iframe players, including cross-origin frames inside web components. Point at the player's Play, episode selector or fullscreen button and press Center.

Availability depends on the player, stream format and website. A pure canvas player without accessible video does not have guaranteed seeking support. DRM and unsupported formats may prevent playback.

## Torrents

Select a magnet or `.torrent` link on a website to open **Torrents** immediately. The library focuses the imported torrent in the overall list; press Center to open its files. Its row shows selected and total size, transfer rates, peer counts, and focusable Start, Priority Up, Priority Down, and Delete icons beside the focused row. Play/Pause on a torrent row also starts all its files. Priority order is saved across launches.

New torrents start with files skipped. Center or Play/Pause on a focused playable file starts **Play Now (Priority)**. Hold Center on a file for Play Now and Download/Skip actions, or on a torrent for Open Files and Pause/Resume. The player offers MP4, M4V, MOV, MP3, M4A, MKV and AVI files. If libtorrent is checking an existing file, playback waits for that check; otherwise it starts as verified pieces arrive and may show **Buffering torrent…**. The format and codec still need to be supported by the embedded player and Apple TV hardware. The bottom panel has Close, previous/start, 10- and 30-second seek, Play/Pause, next file and progress controls. It and the file title hide during playback after inactivity; use Center or Up/Down to show them again. Previous returns to the start of the current file when more than five seconds have played, or opens the previous playable file near the start. Play/Pause toggles playback, Left/Right seek by 10 seconds while the panel is hidden, and Back/Menu returns to the library.

All new torrents wait for manual file selection or Start. Playing a file enables that file; use Hold Center and **Download File** on other files, or Start on the torrent row, to transfer them.

From a torrent's file list, choose **Skip Download** to stop requesting that file, **Pause/Resume** to control the torrent, or **Remove** to delete the torrent and request removal of its cached files. The hint beside the action shortcuts shows the total torrent cache size, which includes listed torrents. **Purge All** removes downloaded data for every torrent but keeps torrent entries at 0% for manual restart. This action does not touch browser history or website data. Torrent payloads and metadata are in tvOS's purgeable cache, so the system may remove them when space is needed. **Settings → Keep Alive** is experimental and does not guarantee background downloading.

### Episode, season and playback position

The website saves this state, for example through cookies or localStorage. Tabs share a persistent WebKit data store so the website can read its data after another launch.

There is no separate backup of player state. If the website does not save the episode selection or its data is deleted, the browser cannot reconstruct it. Page scroll restoration also depends on content loading; a reported case of failed scroll restoration remains unresolved.

## Local storage and recovery

The browser automatically saves history, Favorites and tab sessions in a local database and refreshes its compressed backup. At startup, it attempts recovery from a valid copy if the main database is missing, empty or damaged. No backup toggle is required.

- The backup includes visits, Favorites and tab navigation.
- Cookies, localStorage and player data are not included.
- Explicit history deletion updates the backup so deleted entries should not return during recovery.
- The copy is stored in application preferences. iCloud was rejected; Firefox Account synchronization is planned but unavailable.
- Removing the application also removes the local copy.
- The main database and website data store use Caches. The system can clear these files; the database backup protects history, not website data.
- If a compressed snapshot exceeds the available preferences budget, a new backup is not written. History is not automatically trimmed to make it fit.

## Clearing data

| Command | Result |
| --- | --- |
| Clear Cache | Remove WebKit resource caches and reload; do not deliberately clear other saved website data |
| Clear Cookies | Remove cookies and reload; this may sign you out |
| Clear History | Delete visits after confirmation |

## Diagnostic logging

Open **Menu → Tools → Debug → Website Logging: ON/OFF**.

- Activate the item to toggle website diagnostics.
- The choice survives relaunch; logging is initially enabled.
- The change takes effect immediately without reloading.
- OFF stops new entries from this logger; it does not delete old entries or silence all application logs.

The log helps investigate website storage and player behavior. It records localStorage key names and lengths, not localStorage or cookie values. Episode and season diagnostics depend on the information exposed by the player.

For local inspection, the application container contains `Library/Caches/BrowserWebsiteDiagnostics.log`. The rotated file has the `.previous` suffix. Debug also provides media diagnostics.

## Troubleshooting

- **A website does not open:** check the address, reload, and try Mobile Site or disabling Ad Block.
- **Video does not play:** try page playback and fullscreen; format or DRM limitations may apply.
- **Episode selection resets:** enable Website Logging, reproduce the issue and record the website, episode and restart method. Avoid clearing data before diagnosis.
- **History is missing:** recovery runs when the database opens; success depends on a valid local copy being available.

See [CHANGELOG.md](CHANGELOG.md) for versioned changes, [DEVELOPMENT_HISTORY.md](DEVELOPMENT_HISTORY.md) for detailed history and known limits, and [ROADMAP.md](ROADMAP.md) for plans.

### Native video diagnostic privacy

Native playback and extraction diagnostics omit object payloads such as URLs, headers, response bodies, and error descriptions. Events containing these values show redacted placeholders; numeric-only diagnostic events retain their values. Website logging remains controlled by its Debug menu toggle. Review any diagnostic output before sharing it publicly.
