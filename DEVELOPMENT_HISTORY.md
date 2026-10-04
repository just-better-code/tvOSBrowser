# Development history — tvOS Browser, just-better-code version

Detailed background for [CHANGELOG.md](CHANGELOG.md): user requests, implementation decisions, verification evidence and reversals from the fork baseline to the current development version.

## Historical context

The baseline is upstream commit `e245b8f`, dated 2026-03-08, with Xcode version 2.0.0 and build 3000. Earlier fork commits continued to carry those values until retrospective numbering was introduced on 2026-10-01. The reconstructed feature stages below are not evidence that separate binaries were published for each version.

The first eleven feature groups were combined in squash commit `ecace46` on 2026-09-29. Their catalogue order does not establish their implementation order inside that commit. The initial snapshot groups 15 substantial features and 22 logical fixes into 2.15.22. Ongoing documentation and versioning instructions are in [AGENTS.md](AGENTS.md).

Dates in the chronological account describe project discussions in Europe/Kiev. They can differ from commit dates. Shared messages in the archived video investigation and its continuation are counted once.

## Chronological account

### 2026-10-04 — built-in torrent playback on Apple TV

The user authorized work on the bedroom Apple TV, asked not to use the simulator during this task, and requested progress notes plus reusable launch findings in agent documentation. A targeted reference audit was already recorded in the [torrent plan](docs/agent/plans/torrent-client.md); the linked libtorrent remains 1.2.17 by the user's decision. The website-click path was changed to open the torrent library for ordinary links, new windows and the page-action route. Main-frame responses can also identify a torrent by BitTorrent MIME type or an attachment filename. New torrents wait for file selection before downloading payloads, and website cookies are scoped to torrent URL imports.

The first physical build could not see the paired Apple TV because sandboxed Xcode lost access to CoreSimulator and file-coordination services before compilation. Repeating the device build with host access succeeded; the recovery procedure is in the [Apple TV runbook](docs/agent/APPLE_TV_RUNBOOK.md). The signed Debug app was installed and launched. The user clicked a torrent link on the open website and saw one file in Torrents. Play Now initially waited and then showed a red Stop. Numeric logs showed AVPlayer requested two bytes and failed almost immediately with error `-11829` and underlying code `-12848`; the loader had not reported waiting for a missing piece.

The user explicitly chose embedded libVLC. Official TVVLCKit 3.7.3 was pinned as an ignored local dependency and linked into the app. A loopback HTTP range server streams only verified libtorrent pieces to VLC, allowing buffering and seek requests without giving VLC an incomplete file. The rebuilt app was installed on the TV. For a 1.7 GB selected file, the VLC log advanced from buffering to Playing after about 24 seconds, and the user reported that playback started. This establishes startup playback on that device and file; seeking, restart, background behavior and other file formats were not observed at this point. The user also requested cache removal for both deleted torrents and unlisted leftover files. The torrent library now includes a confirmation-protected Clean Cache action scoped to its own cache directory; its user interaction and space-recovery result still need device observation.

The user then reported controls that did not hide, white controls on a white focused background, repeated apparent downloading, and missing media duration. The handmade button row was replaced with compact symbol controls and an explicit high-contrast focus state, with previous/start, 10- and 30-second seeking, and next-file actions. The previous-file threshold is five seconds by user request. Auto-hide now retries after buffering instead of abandoning its timer when the player is temporarily not playing. After a device relaunch, numeric logs showed the same 1.7 GB file's reported progress move from 18% to 39% in two seconds, then from 60% to 100% over eight seconds. The rapid segment is consistent with checking cached data. Fast-resume checkpoints were added to avoid repeating the check; completed media can now open directly from its local file. The HTTP server's full and partial response headers were corrected, and suffix ranges were added for media readers. These changes compile and were installed in a Debug build, but duration, fast resume, controls, and cache behavior remain open for device observation. The user asked to keep all diagnostic scaffolding until they explicitly confirm the feature is ready.

A later Debug run showed the file at 47% when Play Now was pressed and reaching 100% more than two minutes later; the initial fast progress alone does not establish that the entire interval was a disk check. Numeric torrent state and payload rate are now logged together to distinguish checking from network transfer. The user asked Play Now to wait until an existing-file check finishes, for Play/Pause on a focused media row to start playback, and for controls to stay visible while the remote remains active. The library and player now implement those behaviors. A focused torrent row previously showed white text on a light highlight; its title and detail switch to dark text under focus. These revisions compiled and were installed on the authorized TV; visible behavior and the saved-resume reload still need the user's observation.

The next device relaunch loaded a 19 KB fast-resume checkpoint and immediately reported the same file at 100%, with seeding state and zero payload download rate. Play Now opened the local file (`local=1` in the numeric log), and VLC reported a duration of 6,422,400 ms after about 15 seconds. This confirms fast-resume reload and duration for this one cached file. Control visibility, focus contrast, remote actions, file navigation, and cache cleanup still need user-visible observation.

The user confirmed that the duration appeared, seeking worked, and the controls behaved well. They observed that the top status still said “Buffering torrent…” during playback. VLC had emitted Buffering after Playing even while its time advanced, so the label now follows actual playback progress and only reports buffering after the time stalls for more than 2.5 seconds. The corrected Debug build was installed and launched; its visible status still awaits confirmation. The user has not declared the feature ready, so diagnostics remain in place.
The user subsequently confirmed on the Apple TV that the buffering label disappears during playback. Focused-row contrast, cache cleanup, and multi-file navigation remain to be observed. The user has not declared the feature ready, so diagnostics remain in place.

### 2026-10-04 — visible zoom percentage

The user asked for the Reset Zoom tile to show the current scale. Version 2.15.26 displays the saved percentage beneath Reset Zoom and refreshes visible menu tiles after each zoom action, without dismissing the menu or moving focus. The tile's accessibility label includes the percentage. The signed Debug build was installed and launched on Apple TV on October 4. Codex did not inspect the TV screen; the user subsequently reported that the overall zoom feature was working and closed it.

### 2026-10-02 — page zoom for reading

The user narrowed the active work on October 1 to readable whole-page zoom on pravda.com.ua, with no rightward drift and a stable relaunch. The previous Zoom action combined WebKit page zoom with private text zoom and used three delayed horizontal offset corrections based on the visible center. Firefox iOS research showed a single `viewScale` per tab and host-based persistence. Fix 2.15.24 (`5151814`) removed the center corrections, discarded stale horizontal offsets on session restore and fixed Zoom Out wrapping at 50%, but retained WebKit `pageZoom` alone. Simulator testing on October 2 exposed a regression: at 140%, WebKit reduced the viewport width from 1920 to 1371 CSS pixels and the body font from 16px to about 11.43px, leaving text nearly unchanged while the page shifted. Fix 2.15.25 (`c63e081`) applies the saved global percentage through WebKit `viewScale`, as Firefox does, with a page/text zoom fallback for runtimes without that key. At 140%, the simulator showed larger text and content aligned to the left. The saved 140% preference and effective `viewScale=1.4` survived terminate and relaunch. The user called the result close to ideal. Direct device inspection and pointer alignment verification were not performed; the user later reported the zoom feature was working after a TV install.

### 2026-10-01 — restoring the browsing and viewing session

**Back still exited to the Apple TV home screen.** The user again reported that Back should behave as the browser menu. Global input handling was changed to consume all Menu/Back phases so the system would not exit after a browser action. Back closes a presented screen, returns from New Tab when possible, turns off the magnifier, or opens the menu. This continued the September 28 fixes; it was not the first introduction of menu behavior. Implementation: `d7987c2`, fix 16.

**Tab Back/Forward still failed across launches.** The user asked why tab history could not be saved in SQLite instead of repeatedly repairing preferences restoration. The complete session moved to SQLite: ordinary tabs, active index, navigation URLs/titles and each tab's current navigation position. Native WebKit history snapshots and URL/loading observation capture transitions missed by a full-load-only approach, including pushState. Restoring the current page or following its redirect preserves Forward. An empty session is saved so previously closed tabs do not reappear. Implementation: `d7987c2`, feature 2.13 and fixes 17–19. A build alone was not treated as proof of all navigation scenarios.

**The main database remained in Caches; a full local backup was added.** The user was concerned about system eviction and proposed Application Support. On the inspected Apple TV, that destination was not writable, so the live database was preserved rather than moved. After discussing iCloud and the lack of a paid developer account, the user chose a local backup. A complete compressed SQLite snapshot in preferences replaced limited visit arrays. It is refreshed after mutations and used automatically if the main database disappears or is damaged. Player state was deliberately excluded. A recovery comparison covered all five tables with 288 visits, 3 Favorites and 5 tabs; a new visit remained after relaunch. Implementation: `d7987c2`, feature 2.14 and fix 20.

**The episode dropdown exposed a separate website-storage failure.** On a test streaming website, the user selected an episode as the acceptance example. Selection reset after another launch, unlike the mobile browser; similar websites behaved the same way. The user explicitly requested normal website storage rather than a custom backup of the dropdown or playback position. Diagnostics found that the default WebsiteData path was not writable. localStorage appeared usable during a session but a test value did not survive another process launch. All browsing WebViews were configured with one persistent store under writable Caches. The user manually checked the result and reported success. Implementation: `95e6264`, fix 21.

**The reported page scroll offset was not fixed in the website-storage change.** The user also observed that the page position did not restore. It was useful diagnostic context but not critical to the requested player-state fix. No separate completed fix for that case was identified at the time. A full TV reboot was not independently confirmed during this work.

**Diagnostics remained available after the successful fix.** The user asked for loggers, then a clean build, then whether the loggers had been kept. A Debug toggle was added to enable/disable Website Logging immediately without reloading and persist the choice. The file records storage operations and available player state without copying localStorage or cookie values. Implementation: `95e6264`, feature 2.15.

**Menu focus moved to the domain.** The user wanted the domain active by default. This makes Center immediately open address/search entry rather than requiring movement from New Tab. Focus is requested again after the panel animation. Earlier device diagnostics reported `focused=1` and `onScreen=1`. Implementation: `1008e01`, fix 22.

**Documentation and future directions were clarified.** The user requested a changelog from the fork baseline, clarified that the third version component is the fix number, and chose 2.15.22. The initial diff catalogue was expanded using project conversations to capture purposes, failed attempts and confirmations. The final changelog uses Common Changelog; this document retains the detailed account. The user guide was updated. Physical Apple TV work was stopped at the user's request; documentation work did not perform new device checks.

The user subsequently planned Firefox Sync, an integrated torrent client with silent-audio Keep Alive and playback while downloading, investigation of mobile Firefox's WebKit integration, complete iframe interaction and a page scaling fix. PiP and iCloud were rejected. These decisions are recorded in [ROADMAP.md](ROADMAP.md), without changing the application version.

### 2026-09-29 — history, video-input conflicts and interface simplification

**Seeking was restored after unsuccessful experiments.** The user reported that Left/Right no longer sought video, although seeking had worked before the rollback. The final implementation restored ±10 seconds for accessible HTML video/iframe and the native player. The user first reported a failure, then confirmed the current implementation worked. Browser-history navigation remained disabled on those arrows. Implementation: `8ba451f`, fix 14.

**The magnifier gained a complete idle shutdown.** The user requested shutdown after 30 seconds without cursor activity, followed only by manual reactivation. A timer was added and cursor activity resets it. The user confirmed that movement must not turn it back on. The code was committed later, in `84b0d33` on October 1, as fix 15.

**The old top bar was actually removed.** Back/domain/Forward were combined in the menu and browser history was removed from remote arrows. When the user asked whether the old bar still existed, its files, storyboard connections, focus mode and visibility settings were deleted. The permanent URL and old loading indicator disappeared; core actions stayed in the menu. Focused navigation buttons were raised above the address field after a reported overlap. Implementation: `8ba451f`, feature 2.12.

**Universal canvas controls were attempted and rolled back.** The user wanted video arrows to reach the player instead of navigating history. Experiments included canvas/fullscreen detection, synthetic ArrowLeft/ArrowRight events, a MediaSession bridge and a native progress overlay. Reports of broken rendering, repeated Back navigation and cursor failure led to removing the overlay/bridge and reverting the problematic `666ec7e arrows` commit. The eventual solution kept simple accessible-video/iframe seeking and removed history from arrows altogether. A universal pure-canvas player bridge and the overlay are not current features.

**Center opens; Play/Pause performs an option.** The user defined this model for screens other than browsing. Menu Recents became History, listing 20 recent addresses and All History at the end. In All History, Center opens and Play/Pause selects. On New Tab, Center opens and Play/Pause handles Favorite editing or visit deletion. This replaced inconsistent activation paths and an extra History Actions popup. Implementation: `89882fa`, fixes 10–12.

**Cursor movement recovered after arrow navigation.** The remote could click but no longer move the cursor. Unfinished arrow changes were removed; a new touch/move clears the directional hidden state. The user reported recovery. The final fix did not replace the input mechanism with a new pan recognizer. Implementation: `ab11d5e`, fix 13.

**History had become inaccessible, not erased.** After storage changes, the user reported that history stopped recording and appeared empty. Device inspection found the existing database in Caches with existing visits and Favorites. Restoring discovery of that file restored writes; later checks confirmed new visits were recorded with existing Favorites retained. The user asked to remove automatic cleanup completely and add Clear History alongside Cache/Cookies. Explicit clearing gained confirmation, and live-container inspection was documented as a safeguard. This work is part of `ecace46`.

**The first tab-history persistence attempt was incomplete.** Earlier that day, tab URL lists and positions were stored in models/preferences, Clear Cache was narrowed, Recents used the last active week, and history older than a month was pruned while retaining 100 entries. A page restored locally, but full UI Back/Forward was not confirmed. Age cleanup was then removed at the user's request; the October 1 SQLite session replaced the initial persistence approach. These intermediate decisions explain later work and are not current settings.

**New Tab gained activation of the arrow-selected entry.** The user asked for Center as Enter and Back to the last active tab. DOM focus/Enter handling and previous-tab tracking were added. Earlier Play/Pause-as-open behavior was later replaced by contextual options, leaving Center as activation.

### 2026-09-28 — making website players usable

**The first decisive result was delivering a click into a custom iframe player.** Work started with a question about the browser supporting few video containers. The saved `test.html` example showed that Play did not receive a click: the browser clicked the outer iframe instead of the control inside it. A frame bridge with local coordinates was added. The user reported success, then identified the next blocker: all remote control disappeared after expanding the video. The focus shifted from codec investigation to interaction with website players. Included in `ecace46`, feature 2.10 and fix 02.

**Fullscreen retained remote input.** Expansion used a page-managed mode rather than handing control to an unsupported system fullscreen path. The user initially saw black video and later clarified that this happened during advertising; the main video subsequently appeared. Cursor, Play/Pause and Menu were confirmed afterward. The old upstream fullscreen branch was inspected but not imported: its private memory-offset hook was older and disabled in the current baseline.

**A second player required Shadow DOM traversal.** A simple iframe query missed the player structure in `test2.html`. The user emphasized supporting a technology rather than hard-coding one website. Frame discovery was extended through nested web components, and the user confirmed playback. The example used HLS with MPEG-TS, H.264 and AAC; the failure was click delivery, not the media container. Included in feature 2.10.

**Theater mode kept expanded video above the page.** Expansion already worked, but page elements could overlap it. A dark backdrop and raised ancestor layers were added, with original styles restored on exit. The cursor began fading after about 3 seconds without movement so it would not obstruct viewing.

**Remote controls stopped requiring constant mode changes.** Up/Down gained scrolling, abrupt steps were reduced, and conflicting double actions were removed. Play/Pause stopped opening a menu and controlled video; the user confirmed it. Cancelled navigation `-999` stopped breaking later input at history boundaries. Hover moved away from synchronous JavaScript waiting that could nest `sendEvent:` calls. Included in feature 2.1 and fixes 01/06.

**Scrolling became smooth and continuous.** Short Up/Down presses first used native UIScrollView animation. Holding then gained continuous movement until release, followed by gradual acceleration. The user confirmed each stage, including the absence of a sudden speed jump. Double Up closes a tab only in the overview, avoiding conflicts with repeated page scrolling.

**Ad Block gained verified rule removal.** After adding blocking, the user noticed that ads did not return at OFF. Runtime removal and diagnostic approaches were tried. The final approach modifies rules on existing WebViews without recreating them and losing internal history. A temporary device rule showed On → active and Off → inactive, then the test rule and diagnostic action were removed. Ads remaining absent did not prove the browser's rules remained active. Feature 2.8.

**New Tab replaced repeated address entry.** Search, Favorite tiles and a history list gained arrow navigation; the user approved the first layout. Editing Favorites, deleting visits, All History and SQLite followed. When Documents rejected database writes, using writable Caches restored old entries and new writes, confirmed by the user. Features 2.3/2.5/2.6.

**Tabs and long history lists became usable from the sofa.** Empty New Tab stopped consuming a slot, the large plus button returned, and the five-tab limit was removed. White-on-white focus was corrected across New Tab, All History and the Favorite editor. Actions moved above the list instead of below thousands of rows; selection became part of reachable rows. Empty-state focus, Deselect and confirmation counts were subsequently refined. Features 2.4/2.5 and fixes 07–09.

**A custom magnifier made small controls reachable.** System Zoom made the browser cursor awkward to use, so a circular application magnifier was added. User feedback led to cursor anchoring, lower sensitivity, a larger visible area and periodic refresh without movement. At screen edges the lens is partly clipped but the pointer can still reach the edge. Double Play/Pause was removed from activation to avoid interfering with video; holding Center toggles the magnifier. Feature 2.9. Idle shutdown followed the next day.

**Rows of buttons evolved into the tiled menu.** Iterations included icons instead of labels, readable focused icons, smaller focus scaling and a domain rather than the full URL. The user then requested short-label tiles, moving the second row into the grid and gathering diagnostics under Debug. Zoom controls received their own first row, and Zoom In wrapping was corrected. Fit to Screen was removed after negative feedback. Features 2.2/2.7. The permanently hidden top bar still existed until its actual deletion on September 29.

**Back behavior and the guide followed the user's expectations.** Back initially opened tabs; it later opened the menu and a second Back closed it. Overview dismissal should restore the previously active page. The user confirmed these paths, but a renewed system exit on October 1 prompted fix 16. The long guide became a remote illustration and six cards; Start Browsing was resized, cursor/arrow control added, and launch visibility made configurable. Feature 2.11.

### 2026-03-08 — fork baseline

Upstream `e245b8f` already contained WebKit browsing, cursor input, tabs, basic Favorites/history and native/WebKit media paths. Its existing video path did not make the required custom players receive remote input. Those inherited capabilities are the comparison baseline rather than new fork features.

## Implementation detail

### Custom players, iframe input and fullscreen

This was the key usability change: opening a movie or episode, pressing the website's own Play button, expanding it, and retaining remote control.

- A user script is installed in every frame, not just the main page.
- Parent/frame `postMessage` commands use a bridge secret and verify message sources.
- Click coordinates are converted to each frame's local system, accounting for scale and border offsets, and forwarded recursively through nested frames.
- Frame discovery traverses accessible Shadow DOM to find embedded controls.
- Click delivery includes pointerdown, mousedown, pointerup, mouseup and click, with coordinates and composed/bubbling events.
- Play/Pause targets an accessible HTML video or expanded iframe; ordinary video selection prefers playing video, then the largest visible candidate.
- Fullscreen compatibility covers requestFullscreen and WebKit variants, updates document fullscreen state and dispatches fullscreen-change events.
- Theater mode dims the page, raises player ancestors and restores original styles on exit.
- Later seeking uses video currentTime or a seek command to the active/expanded iframe; native playback uses skipByInterval.

The native Full Screen Player setting is separate from page-managed theater expansion. It needs an accessible direct media URL; it is not necessary to expand the website player itself. Native AVPlayer and media URL discovery predate the fork changes. Pure canvas decoding without an accessible video/API has no universal seeking guarantee; the rolled-back synthetic-key/MediaSession overlay is not claimed as implemented. No decoder, universal DRM support, PiP or background video was added by the frame bridge.

Key files: `BrowserWebView.m`, `BrowserDOMInteractionService.m`, `BrowserPageActionCoordinator.m`, `BrowserRemoteInputController.m`, `ViewController.m`.

### Session persistence

The SQLite session stores active-tab metadata, ordered tabs, ordered navigation URLs/titles and navigation indices. WebKit snapshots are used for ordinary navigation; restored models preserve their own list until restoration is reconciled. URL/loading observation catches same-document changes. Redirects replace the restored current entry instead of discarding the Forward stack. Saving zero ordinary tabs clears stale session rows transactionally.

The earlier preferences implementation was a useful first step but did not resolve every reported restart case. Empty about:blank/New Tab entries are filtered, active indices remapped, and overview display indices resolved through actual tab objects rather than assumed to equal model indices.

Key files: `BrowserHistoryStore.h/.m`, `BrowserSessionStore.m`, `BrowserTabViewModel.m`, `BrowserTabCoordinator.h/.m`, `BrowserWebView.h/.m`.

### Complete local backup

- Create a consistent SQLite snapshot with sqlite3_backup and sqlite3_serialize.
- Compress with zlib and store it in preferences under `BrowserDatabaseBackupV1`.
- Include all five tables: visits, favorites, browser_session, session_tabs and tab_navigation.
- Refresh after visits, Favorites, session writes and explicit deletions, and when opening a healthy database.
- Recover when the file is absent, zero length or fails integrity validation.
- Validate format version, declared size, CRC32, PRAGMA quick_check and required tables before replacing the working file.
- Restore through a staging file and retain damaged database/journal files under separate names for possible manual recovery.
- Track an unfinished mutation to prevent recovery from a snapshot that could resurrect explicitly deleted data.
- Check a 450 KiB combined preferences budget before saving; history is not pruned when a new backup does not fit.
- Limit decompressed snapshots to 64 MiB; this is a backup guard, not a history deletion policy.

The sample compressed backup was approximately 16 KiB; size changes with stored data. Earlier visit-only arrays held up to 2000 and 200 records. The full backup replaces those limits for recovery. It does not protect cookies, localStorage or player state, and application removal also removes its preferences copy.

Deletion checks transaction start, prepared statements, each DELETE and COMMIT. Failure rolls back and refreshes the backup from actual database state; Favorite writes also check COMMIT and use ROLLBACK.

### Website persistence and controlled diagnostics

The inspected Apple TV denied writes to the default `Library/WebKit/WebsiteData` directory. The configured shared persistent store uses `Library/Caches/BrowserWebsiteData`. Browsing, cookie access and cache/cookie clearing use the same store. Runtime checks fall back to the default store when the required private configuration APIs are unavailable.

The website owns episode/season/timecode persistence. No dropdown-specific preferences backup was added. This fixes the storage path available to the website rather than synthesizing its state.

`Library/Caches/BrowserWebsiteDiagnostics.log` records sanitized storage operations, available player state and store setup information. It rotates at roughly 128 KiB, retaining `.previous`. The saved Website Logging preference defaults to ON to retain the earlier logger behavior. OFF immediately stops this file's new records without deleting earlier logs or disabling unrelated NSLog output. Episode detection depends on what DOM/player messages expose.

### Remote, magnifier and menu refinements

- Short Up/Down uses animated UIScrollView movement; successive taps accumulate their steps.
- Holding scrolls continuously until release and accelerates gradually over approximately 2.4 seconds.
- Current cursor sensitivity is 0.75, or 0.375 with the magnifier; the earlier 50%/25% trial was revised.
- The cursor fades after roughly 3 seconds without activity and hides on directional navigation; a new touch restores it.
- A Center hold exceeding 0.65 seconds toggles the magnifier without also clicking; double Play/Pause remains two media presses.
- The lens refreshes every 0.25 seconds, follows the cursor and clips naturally at screen edges.
- Magnifier activity resets its 30-second shutdown timer; movement after shutdown does not reactivate it.
- Menu sections are Quick Actions, Settings and Tools; zoom controls occupy one first row and other tiles use pairs.
- Focus raises buttons above neighbors, keeps icons readable and uses modest enlargement.
- Address editing exposes the complete URL although the inactive menu shows only the domain.
- Mobile Site changes User Agent and reopens the active tab without deliberately clearing site data.
- Page zoom ranges from 50–200%, in 10% steps. Version 2.15.24 removed the center-based horizontal offset recalculation; version 2.15.25 uses WebKit `viewScale` for the whole rendered page. Zoom changes and restored sessions start at the left edge; loaded pages reapply the saved percentage. Cursor alignment remains planned.
- Ad Block changes rules across existing WebViews, preserves their history and exposes removal failure separately from successful OFF.
- Clear Cache removes cache types rather than all non-cookie website data.

### History and Favorites UX

New Tab currently shows ten recent URLs, not the earlier most-visited or last-active-week proposals. Arrow selection receives DOM focus and Enter handling; Center activates that entry instead of stale pointer targeting. Contextual refresh attempts to retain the selected section. Presented editors do not pass arrow input to the page behind them.

All History actions sit above the list. Center opens; Play/Pause selects/deselects. Select All becomes Deselect when appropriate. Open requires one selected entry; Delete handles selected entries; Clear All confirms the count. Empty lists expose an appropriate focus target. Favorites remain separate from visit clearing. Glass styling and readable focused text address white-on-white reports.

No automatic age cleanup remains. The database discovery order considers Application Support, Documents and Caches but prefers an existing database before creating a new one. The observed live file was in Caches; moving it to Application Support was not completed.

## Retrospective catalogue

| Feature stage | User-facing purpose | Main source |
| --- | --- | --- |
| 2.1.0 | Browse with one remote using pointer, smooth scrolling and contextual input | `ecace46` |
| 2.2.0 | Find actions quickly in a tiled menu with readable focus and toggle state | `ecace46` |
| 2.3.0 | Open familiar pages through search, Favorites and recent visits on New Tab | `ecace46` |
| 2.4.0 | Keep more than five useful tabs without saving empty New Tab slots | `ecace46` |
| 2.5.0 | Retain full visits/Favorites and manage long lists through SQLite/All History | `ecace46` |
| 2.6.0 | Edit or delete Favorites directly on TV | `ecace46` |
| 2.7.0 | Make whole pages readable through adjustable zoom | `ecace46` |
| 2.8.0 | Block selected advertising/tracking requests and turn blocking off reliably | `ecace46` |
| 2.9.0 | Reach small controls accurately with a cursor magnifier | `ecace46` |
| 2.10.0 | Start and control custom website players through iframe/Shadow DOM bridging | `ecace46` |
| 2.11.0 | Learn remote gestures through the visual guide | `ecace46` |
| 2.12.0 | Give pages the whole screen and consolidate actions in the menu | `8ba451f` |
| 2.13.0 | Restore complete tab Back/Forward navigation from SQLite | `d7987c2` |
| 2.14.0 | Recover history, Favorites and tabs from a complete local backup | `d7987c2` |
| 2.15.0 | Enable website diagnostics when investigating persistent-state problems | `95e6264` |

| Historical fix ID | Result | Source |
| --- | --- | --- |
| 01 | Correct hover coordinates and avoid synchronous event-loop waiting | `ecace46` |
| 02 | Deliver clicks into nested iframe/Shadow DOM players | `ecace46` |
| 03 | Use cookie fallback on asynchronous-store timeout | `ecace46` |
| 04 | Preserve non-cache data on Clear Cache | `ecace46` |
| 05 | Reapply saved zoom after navigation | `ecace46` |
| 06 | Treat cancelled navigation as NSURLErrorCancelled rather than positive 999 | `ecace46` |
| 07 | Resolve filtered overview cards to the correct real tab | `ecace46` |
| 08 | Remap the restored active index after filtering transient tabs | `ecace46` |
| 09 | Guard repeated overview dismissal with dismissalInProgress | `ecace46` |
| 10 | Open with Center and select with Play/Pause in All History | `89882fa` |
| 11 | Provide recent-20 History and All History in the menu | `89882fa` |
| 12 | Provide New Tab contextual options and retain selected sections | `89882fa` |
| 13 | Restore cursor state on touch after arrows/inactivity | `ab11d5e` |
| 14 | Seek video without a following history transition | `8ba451f` |
| 15 | Turn off the magnifier after 30 seconds idle | `84b0d33` |
| 16 | Consume Back/Menu phases instead of exiting the app | `d7987c2` |
| 17 | Capture same-document tab navigation | `d7987c2` |
| 18 | Preserve Forward across restoration and redirects | `d7987c2` |
| 19 | Save an empty session to clear stale tabs | `d7987c2` |
| 20 | Keep explicit mutations and backup state consistent | `d7987c2` |
| 21 | Make persistent website data writable across launches | `95e6264` |
| 22 | Give initial menu focus to the domain button | `1008e01` |

## Verification evidence and remaining limits

- Player click delivery was exercised with the saved test.html and test2.html examples. The user confirmed playback after frame/Shadow DOM changes and confirmed cursor, Play/Pause and Menu after the main video appeared.
- A temporary Ad Block rule reported On → active and Off → inactive inside the device WebView. The diagnostic rule/action was subsequently removed.
- The live history database contained existing visits and Favorites before discovery was repaired; later checks confirmed new visits were recorded with Favorites intact.
- Local history checks described in the project discussion exercised 1533 entries, selective deletion and Favorite retention after full visit clearing; a complete remote-driven UI pass was blocked by Simulator input routing.
- Complete backup recovery compared all five tables with 288 visits, 3 Favorites and 5 tabs. New visits appeared in All History and survived relaunch.
- The user confirmed test-site episode selection after website-store changes. That confirmation is not a claim of universal website behavior or a separately verified full TV reboot.
- Earlier domain-focus diagnostics reported focused=1 and onScreen=1. No fresh physical TV checks were performed while writing these documents.
- General page scroll restoration has a reported unresolved case. The 2.15.24 zoom change resets horizontal restoration while retaining the saved vertical offset; the 2.15.25 rendering fix was visually checked on pravda.com.ua at 140% in the tvOS 18.2 Simulator, while pointer and other site layouts remain pending.
- Main history and website files remain in Caches and can be evicted; preferences backup protects the database, not site state.
- The torrent/Keep Alive prototype exists in another branch and is absent from the current feature/canvas-fix tree.
- Pure canvas players, closed player APIs, codecs and DRM are not universally supported. PiP and iCloud were rejected; Firefox Sync and background torrent downloading remain planned.

These observations describe the state reported at the time. They do not imply that every scenario was rerun against the final documentation snapshot.

## Sources

Code was compared from `e245b8f` through the current tree and each fork package: `ecace46`, `7684637`, `89882fa`, `ab11d5e`, `8ba451f`, `84b0d33`, `d7987c2`, `95e6264` and `1008e01`. Commit links are provided in [CHANGELOG.md](CHANGELOG.md).

`7684637` updated the README and screenshots. SQLite and later zlib linking support the storage features. Development instructions, regression checklists and graph integration were also added, without being counted as user-facing minor features.

| Project discussion | Evidence used |
| --- | --- |
| Video investigation and its continuation | Initial event-loop failure, iframe/Shadow DOM click delivery, fullscreen input, theater mode, magnifier and early menu/history iterations |
| Tiled menu review | History selection/readability, actions above long lists, dedicated zoom row, removal of Fit to Screen and UI verification limits |
| Initial tab-history persistence | Preferences session, Clear Cache preservation, later-abandoned Recents/pruning behavior |
| Missing history investigation | Existing Caches database, discovery repair, removal of age cleanup, Center activation and return from New Tab |
| History navigation and remote refinements | Center/options model, seeking/history conflicts, canvas/overlay reversals, cursor recovery and magnifier timeout |
| Current Back/menu and persistence discussion | Global Back handling, SQLite session, local backup, episode persistence, logging and domain focus |
| Background media investigation | PiP/background possibilities investigated without a completed current implementation |
| Torrent prototype discussion | Separate-branch download/playback prototype, file selection, Keep Alive idea and rejected external VLC handoff |
| Fork remote setup | Baseline and Git configuration, not a user-facing feature |

Proposals and stale TODOs in UI_UX_SUGGESTIONS.md or AGENTS.local.md were not used as proof of implemented features.
