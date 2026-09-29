# Torrents on Apple TV

The browser embeds libtorrent. Open **Torrents** from the menu to paste a magnet link or an HTTP(S) `.torrent` URL. Clicking either kind of link on a page also adds it. Select a torrent, then a supported media file to play while pieces arrive. Torrent data lives in `Library/Caches/BrowserTorrents`; tvOS may purge it between app launches.

Run `scripts/bootstrap-torrent-deps.sh` once before building. It downloads the tvOS device and simulator libtorrent 1.2.17 binaries and Boost 1.69 headers into ignored `.deps/`. The script pins SHA-256 checksums. The libtorrent binary is from [libtorrent-Apple](https://github.com/danylokos/libtorrent-Apple), built from [libtorrent](https://github.com/arvidn/libtorrent), which uses the BSD license. Boost uses the [Boost Software License](https://www.boost.org/users/license.html).

The **Keep Alive** menu toggle loops silent audio as an experiment while the app is in the background. tvOS may still suspend the app. Leave it off unless testing background downloads. Playback uses AVPlayer and currently accepts MP4, M4V, MOV, MP3, and M4A; other containers need an additional decoder. Torrents resume by rechecking cached files when the library is reopened.
