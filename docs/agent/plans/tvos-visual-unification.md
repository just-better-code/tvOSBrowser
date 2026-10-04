# Native tvOS page style

Status: in progress on 2026-10-04. Follow [the style guide](../TVOS_STYLE_GUIDE.md). The user supplied a photo of tvOS Settings and clarified that the existing translucent browser menu must remain unchanged. Separate full-screen pages should use the reference's soft background and wide, translucent resting rows with a pale focused state; content should fill the safe width, without the Settings artwork column. The photo distorts color, so exact RGB sampling is inappropriate.

## Purpose and acceptance

The start page, history, tab overview, torrents, related dialogs, and VLC overlay should feel like one tvOS app. App-owned pages should use native UIKit controls and remote focus where practical. The start page must retain search, favorites, recent visits, their management actions, and existing remote shortcuts. Websites remain unchanged. On the Apple TV, the user should recognize the supplied reference in both rest and focus states and confirm legibility, transitions, and full-width content.

## Current code and constraints

- `BrowserMenuCoordinator.m` already has the menu the user likes; do not restyle it.
- `BrowserTabCoordinator.m` builds the new-tab page as HTML and JavaScript, and `ViewController.m`/`BrowserRemoteInputController.m` forward remote navigation to it. This needs a behavior-preserving native replacement.
- `BrowserHistoryViewController.m`, `BrowserTabOverviewController.m`, `BrowserTorrentLibraryViewController.m`, and `BrowserTorrentVLCPlayerViewController.m` use UIKit but had separate visual choices.
- Preserve browsing and torrent state, signing, tvOS 15.6 deployment target, and torrent diagnostic scaffolding. Do not use the simulator while the user asks to avoid it. The user has authorized the bedroom Apple TV for this project; physical observation still requires their participation.

## Milestones and progress

1. Record the visual reference and durable rules. Done: `AGENTS.md`, `docs/agent/TVOS_STYLE_GUIDE.md`; ignored local photo in `.references/tvos-settings-style.jpg`.
2. Share background, surface, focus, and glass rules across full-screen UIKit pages. Implemented in `BrowserTVAppearance.h`, history, tab overview, torrent library, and VLC controls; the menu was not changed. Visual observation is pending.
3. Replace the app-owned HTML new-tab UI with a native, full-width page. Implemented with a UIKit table, preserving search, favorites, recents, All History, Select, Play/Pause options, and cursor actions. The prior HTML UI and JavaScript navigation were removed; the underlying web view loads only blank content. The user confirmed that the corrected page shows one highlighted row and that remote movement is ideal. Search, favorites, and management actions still need direct observation.
4. Align remaining app-owned dialogs and favorites UI without changing website content. The favorite editor's ordinary actions now use the shared resting/focus surface; the broader dialog audit is pending.
5. Build and observe on the authorized Apple TV when the code is ready. A signed Debug build succeeded and was installed and launched on 2026-10-04. The user reported two simultaneous highlighted New Tab rows in the first build. Selection styling was corrected to use one selection source, then a second Debug build succeeded and was installed and launched. The user called the corrected New Tab result ideal. History, tabs, torrents, and player styling still need separate observation; compilation and launch do not prove those screens work.
6. Unify remote actions on app-owned pages. The user confirmed the History page looks right, then set Center as activate/confirm, Hold Center as context actions, and Play/Pause as a screen-specific shortcut. History Play/Pause marks; Torrents Center and Play/Pause play a focused media file. Native context menus and direct torrent playback are implemented but have not yet been observed on the TV. Website behavior and the existing menu remain unchanged.
7. Keep Torrents active while browsing, focus a newly imported torrent in the overall list, and show transfer details. Implemented with startup manager initialization, common-mode checkpointing, metadata selection application, and richer snapshots. The first attempt to route Back through the root controller still returned from the file list to the website on device. The library now catches Back directly; the user confirmed it returns to the torrent list. The user confirmed the VLC symbol proportions after fixed-size image views. Two additional single-file torrents had priority zero and stayed at Waiting; a temporary automatic selection made both transfer, but the user rejected auto Start. Manual Start is restored. Text buttons and then in-cell icons could not be focused or read over the row; the current revision puts the icons in a separate right column. Priority order is persisted. The user removed the manual Add Torrent and Clean Cache actions; website link import and the total cache-size hint remain. Purge All is separate. Website-browsing transfer, the right-side focus column, and Purge All await observation.

## Validation and recovery

Before replacing the new-tab implementation, map its current actions and selection behavior. Keep history and favorites storage unchanged. Run `git diff --check` and `graphify update .` after code edits. Build only under the project's working agreement, then have the user verify the visual result on the TV. If any visual choice obscures text or breaks remote navigation, revert that view's presentation while preserving its data and playback code.
