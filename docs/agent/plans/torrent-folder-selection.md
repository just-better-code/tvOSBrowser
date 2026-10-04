# Torrent folder selection

## Purpose and acceptance

Let the user start one episode or every file in a folder while other files remain skipped. Show folder navigation in the native Torrents page and download icons for torrent-wide and per-file actions.

## Scope and context

The manager uses libtorrent 1.2 file priorities and stores skip choices in `Metadata/sources.plist`. The library previously displayed a flat file list. The user finished their background test and authorized TV installation. The debug probe and torrent diagnostics remain in place.

## Milestones and progress

- Done in code: Group files into navigable folder rows, support Download Folder and Skip Folder, and preserve direct playback on media rows.
- Done in code: Batch file-priority changes and resume after enabling a selection.
- Done in code: Replace the torrent-wide Play symbol with a download symbol.
- Done in code: Add whole-torrent Reset through the context menu and move Remove there.
- Done in code: Move the runtime probe into Debug and add a master Diagnostics switch and ten recent numeric logs.
- Done in code: Add a focusable download icon beside the focused file or folder.
- Done on TV: The final Debug build was installed and launched; the user confirmed the file list returned and the download icon worked.
- Pending observation: Folder-wide selection, Reset, context Remove, and Debug switch behavior on the TV.

## Decisions and discoveries

The official libtorrent API supports per-file priority, but its deletion flag applies to the entire torrent. Priority zero does not reclaim an already-created file. Individual payload deletion remains unavailable because directly unlinking a live file risks stale piece and resume accounting. Whole-torrent Reset waits for libtorrent's deletion alert before re-adding the saved source. A file returned by the manager was initially excluded by the folder grouping's padding filter; path-aware filtering plus a flat-list fallback restored it. See [torrent architecture](../../../TORRENTS.md).

## Validation and recovery

The first device build hit the known sandboxed Xcode service failure; a retry with host service access succeeded. Subsequent Debug builds succeeded and were installed and launched. The user reported empty file lists; an on-screen count showed one manager file and zero grouped rows. The final fallback build restored the list, and the user confirmed the file download control works. Folder navigation, selecting and skipping a whole folder, Reset, context Remove, and continued background transfer were not observed in this run. Keep existing torrent data intact if any remaining action fails.

## Outcome and remaining work

The implementation is installed on the TV. The file list and per-file download action were confirmed by the user. Folder-wide selection and Reset are implemented but unverified on the TV; individual-file payload deletion remains unsupported.
