# Roadmap — tvOS Browser, just-better-code version

Updated on **2026-10-04**. These entries describe work still planned after version 2.16.0.

## Planned

### Firefox Account synchronization

**Purpose:** use personal browsing data on Apple TV and other devices without transferring it manually.

Investigate Firefox Account/Sync integration, authentication, and synchronization of Favorites, history and tabs. The exact scope and conflict resolution remain to be determined.

### Extend the built-in torrent client

**Purpose:** open a magnet or `.torrent` link on a website, choose files and start watching on Apple TV before the download finishes, without a PC client.

- Implement background downloading using **Keep Alive through silent audio playback in the background**. An earlier branch experimented with this mechanism; sustaining an actual download remains to be verified.
- Verify seeking, restart, torrent removal and cache cleanup on the physical Apple TV, and address any issues observed.
- Review manager concurrency and resume persistence beyond the current saved file selection.
- Later, consider an indicator listing torrent/magnet links found on the page to avoid precise cursor targeting.

Version 2.16.0 opens website torrent links in the library and plays a selected file through embedded VLC while pieces download. A physical Apple TV playback start was observed; background downloading and the checks above remain. The [torrent-client plan and reference map](docs/agent/plans/torrent-client.md) records the relevant sources and remaining work.

### Mobile Firefox and its WebKit integration

**Purpose:** learn how another browser manages its own interface, state and controls around WebKit as an external engine, and identify useful approaches for tvOS Browser.

Study the WebKit implementation of mobile Firefox: tab lifecycle, website data, session restoration, iframe interaction and player controls. This is a research direction; adopting its architecture or code has not been decided.

### Complete iframe interaction

**Purpose:** develop a coherent solution for pages whose players and controls live inside frames, across different websites and player implementations.

The current bridge supports some clicks and video commands. Further research covers nested and cross-origin iframes, Shadow DOM, focus, coordinate conversion, fullscreen entry/exit, remote-button routing and embedded website data. Determine the limits of custom/canvas players and evaluate the design against multiple implementations. This is a substantial design and research task.

### Fix page scaling

**Purpose:** finish the interaction checks for scaled pages.

Page and text now use one WebKit view scale, and zoom changes and session restoration reset horizontal position to the left edge. The layout and relaunch were checked on pravda.com.ua in the tvOS 18.2 Simulator. Investigate pointer/click coordinates on scaled pages and embedded players, plus any website layout or scroll restoration issues found on other sites.

## Rejected

- **Picture in Picture (PiP):** rejected on 2026-10-01; the earlier investigation is not a planned implementation.
- **iCloud backup/synchronization:** rejected on 2026-10-01. The implemented local database backup remains; Firefox synchronization is a separate planned direction.
