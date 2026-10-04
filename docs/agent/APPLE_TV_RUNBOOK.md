# Apple TV runbook

Use the Apple TV Simulator by default. Use this physical-device procedure only with the user’s permission for device work. Resolve identifiers at runtime; do not record personal device names, UUIDs, account identifiers, or copied app data in repository documentation.

## Building and running on Apple TV

The Xcode project is `_Project/Browser.xcodeproj`, and the scheme is `Browser`. Preserve the project's existing automatic signing and development-team settings.

1. Find the connected device and tvOS destination:

   ```sh
   xcrun devicectl list devices
   xcodebuild -project _Project/Browser.xcodeproj -scheme Browser -showdestinations
   ```

2. Build a signed Debug app. Replace `<XCODE_DEVICE_ID>` with the tvOS destination ID reported by Xcode:

   ```sh
   xcodebuild -project _Project/Browser.xcodeproj -scheme Browser -configuration Debug -destination 'platform=tvOS,id=<XCODE_DEVICE_ID>' -derivedDataPath /private/tmp/tvosbrowser-device-build -allowProvisioningUpdates build CODE_SIGN_STYLE=Automatic
   ```

3. Install and launch it. Replace `<COREDEVICE_ID>` with the CoreDevice identifier and `<APP_BUNDLE_ID>` with the bundle identifier configured in the Xcode target:

   ```sh
   xcrun devicectl device install app --device <COREDEVICE_ID> /private/tmp/tvosbrowser-device-build/Build/Products/Debug-appletvos/Browser.app
   xcrun devicectl device process launch --device <COREDEVICE_ID> <APP_BUNDLE_ID>
   ```

A successful build or launch does not confirm that an interaction bug is fixed. Verify the behavior on the device.

If `devicectl` and `xcodebuild -showdestinations` see the paired Apple TV but a sandboxed `xcodebuild` later reports that the destination is unavailable, inspect the build log for `CoreSimulatorService connection became invalid` or `filecoordinationd crashed`. This occurred on 2026-10-04 before compilation; rerunning the same physical-device build with host access succeeded. Xcode may contact CoreSimulator services even for a tvOS device destination. This does not require launching or using a simulator.

For an authorized torrent playback investigation, attach the app's standard output while relaunching it. Filter to the safe numeric torrent loader and player events before displaying or saving output; other app logs may contain personal browsing details:

```sh
xcrun devicectl device process launch --device <COREDEVICE_ID> --terminate-existing --console <APP_BUNDLE_ID> 2>&1 | rg --line-buffered '\[TorrentHTTP\]|\[TorrentVLC\]|\[TorrentState\]|\[TorrentLoader\]|\[NativeVideoPlayer\]'
```

Wait for the user to reproduce the playback issue on the TV. Do not copy an unfiltered console transcript into tracked files.

When a cached torrent appears to download again after launch, compare `[TorrentState]` progress with elapsed time and the library's state and download rate. On 2026-10-04, a 1.7 GB file advanced from 18% to 39% in two seconds, then 60% to 100% in eight seconds: it was being checked on disk after restart. The manager now writes `.fastresume` checkpoints beside torrent metadata and logs `resume saved`/`resume loaded`; verify those events before treating a percentage reset as network redownloading. tvOS can purge torrent cache data, in which case missing pieces genuinely need downloading.

## History storage safeguards

Before changing database paths, fallback order, or history retention, inspect the actual app data container on the target device and copy the existing `BrowserHistory.sqlite` database. Do not infer its live location from simulator behavior or source-code preferences.

```sh
xcrun devicectl device info files --device <COREDEVICE_ID> --domain-type appDataContainer --domain-identifier <APP_BUNDLE_ID> --filter "Name CONTAINS 'BrowserHistory.sqlite'"
xcrun devicectl device copy from --device <COREDEVICE_ID> --domain-type appDataContainer --domain-identifier <APP_BUNDLE_ID> --source <DATABASE_PATH_FROM_DEVICE> --destination /private/tmp/tvosbrowser-history-before-change.sqlite
```

After installing a history change, visit a new page on the device and verify that it appears in **All History** and remains after relaunch. Check database row counts before and after if the UI is ambiguous. Do not add automatic age-based deletion; history is cleared only through an explicit user action. Any move to durable storage must preserve and verify the existing database on the device.
