# Opportunistic torrent processing on tvOS

## Purpose and acceptance

Try the supported tvOS Background Processing capability so manually started torrents can make progress during a system-granted idle window after the user leaves the browser. The user can see whether Background App Refresh becomes available for this app. The user also requested a temporary probe that measures background runtime without needing a torrent. A heartbeat result can establish execution time, but torrent transfer success still requires an actual task launch and a positive downloaded-byte delta on the physical Apple TV; a successful build, task submission, or settings switch alone is insufficient.

## Context and constraints

`AppDelegate.m` starts the libtorrent manager at app launch. `BrowserTorrentManager.mm` restores sources and runs a 10-second checkpoint timer. `Info.plist` currently declares only the experimental audio mode. The app stores torrent payloads in purgeable Caches and saves fast-resume metadata there. Manual Start, file selections, priorities, the current Keep Alive experiment, and all numeric Debug diagnostics must remain. See [background research](../TVOS_BACKGROUND_DOWNLOADS.md) and the [Apple TV runbook](../APPLE_TV_RUNBOOK.md). The user previously authorized device work on the bedroom Apple TV and asked to avoid the simulator for this feature.

## Milestones

1. Add a manager status summary for pending manually started downloads and aggregate downloaded bytes, plus a fast-resume checkpoint request.
2. Declare `processing` and one permitted task identifier. Register the task during app launch, submit with pending work when entering background, and handle task launch, completion, and expiration. In Debug, allow one probe-only request per background transition with no torrent. Log numeric status only.
3. Add a local heartbeat while the app is inactive. Persist elapsed time, timer-covered time, and the longest gap; show the result on the Torrents page so the user can compare Keep Alive on/off without finding a torrent.
4. Build and install the Debug app on the authorized Apple TV. Observe task submission and app launch; ask the user to check the settings switch and try the probe while the browser is inactive. Compare torrent byte counts when one is available.
5. Record actual observations in this plan and `DEVELOPMENT_HISTORY.md`, and update release/user documentation only for behavior that is delivered. Keep the diagnostics until the user declares the feature ready.

## Recovery

If the system rejects task registration or submission, report the numeric error and leave ordinary foreground torrent operation intact. Do not alter cache paths, delete downloads, purge data, or change signing. If the system never grants a processing window, describe it as an unavailable or unobserved opportunity rather than a successful background download.

## Progress

- Research completed from Apple documentation and the installed tvOS SDK.
- Debug implementation built and installed on the authorized Apple TV. The compiled app contains the `processing` mode, task identifier, and BackgroundTasks linkage.
- The first device build registered and submitted a processing task, but the app did not appear in tvOS's Background App Refresh list. Adding the documented `fetch` mode and a short `BGAppRefreshTask` made it appear immediately, already enabled. Both task handlers registered successfully, and the device reported Background App Refresh available. With Keep Alive off and no pending torrent payload, the first build began the probe and tvOS accepted a probe-only processing request. This is submission evidence, not evidence that the task launched or the app kept running. The user is now observing the revised build's probe result.
- With system Background App Refresh enabled and the app's Keep Alive off, the user observed `finished`, 235 seconds elapsed, 0 seconds timer-covered activity, and a 234-second longest gap. This shows rapid suspension during that interval; it does not establish whether tvOS might grant a deferred task later.
- With Keep Alive on, the user reported about 230 seconds of timer-covered activity and a longest gap of 5 seconds. This single interval indicates continuous app execution under the audio experiment, unlike the Keep Alive-off interval. The console attachment ended before this second result, so no task launch is attributed to either mechanism.
- With the tvOS-level Background App Refresh switch off, the user returned to the app and reported 35 seconds active with a five-second longest gap. The app did not crash during that observed interval. Keep Alive was instructed to remain on; the user did not separately repeat its displayed mode or elapsed time. This supports graceful handling of the disabled system setting and is consistent with the audio mode operating independently.
