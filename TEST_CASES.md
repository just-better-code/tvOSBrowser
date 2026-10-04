# Regression test checklist

Use an isolated Simulator or disposable test data for cases that delete history or Favorites. Do not clear a user's browsing data. Record results only after checking visible behavior; a successful build alone is not a UI test.

## App launch and navigation

| ID | Steps | Expected result |
| --- | --- | --- |
| APP-01 | Launch the app after a clean start | The current or home page appears without hanging |
| APP-02 | Open and close the browser menu with Back/Menu | The menu toggles and the page is usable again |
| APP-03 | Move focus through every menu section | Each control can receive focus and be activated |
| APP-04 | Open a page, follow several links, then navigate Back and Forward | WebKit history follows the actual navigation sequence |

## Tabs and New Tab

| ID | Steps | Expected result |
| --- | --- | --- |
| TAB-01 | Open New Tab from the tab overview | The New Tab page appears without occupying a saved tab slot |
| TAB-02 | Open several pages and switch between tabs | Each tab retains its page and can be selected |
| TAB-03 | Close the focused tab with the supported remote action | The tab closes and focus moves to a valid remaining item |
| TAB-04 | Relaunch the app after opening multiple tabs | The saved session restores ordinary tabs and the active tab |
| TAB-05 | Navigate A → B → C, go Back to B, terminate and relaunch, then go Forward to C and Back to A | Each tab restores its complete navigation list and current position; both directions work |
| TAB-06 | Repeat TAB-05 with same-document links or `history.pushState` | Transitions that do not finish a page load survive relaunch |
| TAB-07 | Restore a tab whose current URL redirects, with a saved Forward entry | The current entry follows the redirect and the Forward entry remains available |

## Favorites and history

| ID | Steps | Expected result |
| --- | --- | --- |
| HIST-01 | Visit several URLs and open All History | Visits appear in the expected order with useful titles and URLs |
| HIST-02 | Select a history entry and choose Open | The history view closes and the selected URL loads |
| HIST-03 | Select and delete one entry using disposable test data | Only the selected visit is removed |
| HIST-04 | Choose Clear All, then cancel | The confirmation closes and history remains unchanged |
| HIST-05 | Clear all history using disposable test data | Visits are removed and Favorites remain |
| HIST-06 | Add, open, edit, and delete a Favorite | Each action targets the selected Favorite |
| HIST-07 | Relaunch after visiting pages | History and Favorites remain available |
| HIST-08 | Open a history list with many test entries | Scrolling and fixed actions remain usable without overlap |

## Remote and page interaction

| ID | Steps | Expected result |
| --- | --- | --- |
| INPUT-01 | Move the pointer in each direction and activate a link | The pointer moves predictably and the link opens once |
| INPUT-02 | Scroll a long page and inspect screen edges | Scrolling works and the pointer or magnifier is not incorrectly clipped |
| INPUT-03 | Use directional focus on New Tab and in menus | Focus moves to the expected neighboring control |
| INPUT-04 | Hold Center to toggle the magnifier, then move the pointer | The magnifier appears, tracks the pointer, and can be dismissed |

## Video and error handling

| ID | Steps | Expected result |
| --- | --- | --- |
| WEB-01 | Open a page with a supported video and use Full Screen Player | Playback and exit are controllable with the remote |
| WEB-02 | Open a page with an unsupported or unavailable URL | The failure is clear and browser controls remain available |
| WEB-03 | Change page zoom, reload, then reset zoom | The selected zoom is applied and reset returns to the default |

## Data safety

Before testing history deletion, use a disposable Simulator or a copy of the database. For device storage changes, inspect the target app container and back up the existing database before installing a build. Verify that new visits appear in All History and survive relaunch.

## Complete local database backup

| ID | Steps | Expected result |
| --- | --- | --- |
| BACKUP-01 | Preserve the device SQLite file, move the live file aside, then relaunch | All five tables restore from the compressed preferences snapshot, including visit IDs, favorites and tab navigation |
| BACKUP-02 | Visit a new page, open All History, then relaunch and reopen All History | The visit remains visible and the snapshot includes the updated database |
| BACKUP-03 | On disposable data, delete selected visits or clear history, then remove SQLite and relaunch | Deleted visits remain deleted; favorites and tabs remain intact |
| BACKUP-04 | On disposable data, corrupt or truncate SQLite while retaining a valid snapshot | Restore validates checksum and SQLite integrity; damaged files are preserved |
| BACKUP-05 | On disposable data, exceed the 450 KiB preferences budget or damage the snapshot | SQLite history is never pruned; an invalid snapshot cannot overwrite data, and a stale snapshot cannot resurrect explicit deletions |

The snapshot uses NSUserDefaults and protects against cache-file loss. Uninstalling the app removes this backup too. The preferences budget is finite; this is not cloud storage.
