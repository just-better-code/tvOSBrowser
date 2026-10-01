# Roadmap — tvOS Browser, just-better-code version

Updated from the user's decisions on **2026-10-01**. These capabilities are planned and are not included in version 2.15.22.

## Planned

### Firefox Account synchronization

**Purpose:** use personal browsing data on Apple TV and other devices without transferring it manually.

Investigate Firefox Account/Sync integration, authentication, and synchronization of Favorites, history and tabs. The exact scope and conflict resolution remain to be determined.

### Built-in torrent client with background downloading and playback while downloading

**Purpose:** open a magnet or `.torrent` link on a website, choose files and start watching on Apple TV before the download finishes, without a PC client.

- Continue the prototype from the project's torrent discussion: intercept website links, open the built-in client and select files to download or play.
- Implement background downloading using **Keep Alive through silent audio playback in the background**. An earlier branch experimented with this mechanism; sustaining an actual download remains to be verified.
- Prioritize the selected playback file and the pieces needed for startup and seeking, allowing playback while downloading.
- Integrate download management into the browser menu and keep playback inside the application. Handoff to a separate VLC app was rejected in the earlier discussion because it would take focus away from the browser.
- Later, consider an indicator listing torrent/magnet links found on the page to avoid precise cursor targeting.

A prototype exists in another branch. The complete website-click-to-background-download-and-playback flow is not implemented in the current version.

### Mobile Firefox and its WebKit integration

**Purpose:** learn how another browser manages its own interface, state and controls around WebKit as an external engine, and identify useful approaches for tvOS Browser.

Study the WebKit implementation of mobile Firefox: tab lifecycle, website data, session restoration, iframe interaction and player controls. This is a research direction; adopting its architecture or code has not been decided.

### Complete iframe interaction

**Purpose:** develop a coherent solution for pages whose players and controls live inside frames, across different websites and player implementations.

The current bridge supports some clicks and video commands. Further research covers nested and cross-origin iframes, Shadow DOM, focus, coordinate conversion, fullscreen entry/exit, remote-button routing and embedded website data. Determine the limits of custom/canvas players and evaluate the design against multiple implementations. This is a substantial design and research task.

### Fix page scaling

**Purpose:** finish the interaction checks for scaled pages.

Page and text now use one WebKit zoom factor, and zoom changes and session restoration reset horizontal position to the left edge. Visual verification on representative websites, including pravda.com.ua, remains pending. Investigate pointer/click coordinates on scaled pages and embedded players, plus any website layout or scroll restoration issues revealed by that verification.

## Rejected

- **Picture in Picture (PiP):** rejected on 2026-10-01; the earlier investigation is not a planned implementation.
- **iCloud backup/synchronization:** rejected on 2026-10-01. The implemented local database backup remains; Firefox synchronization is a separate planned direction.
