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

## History storage safeguards

Before changing database paths, fallback order, or history retention, inspect the actual app data container on the target device and copy the existing `BrowserHistory.sqlite` database. Do not infer its live location from simulator behavior or source-code preferences.

```sh
xcrun devicectl device info files --device <COREDEVICE_ID> --domain-type appDataContainer --domain-identifier <APP_BUNDLE_ID> --filter "Name CONTAINS 'BrowserHistory.sqlite'"
xcrun devicectl device copy from --device <COREDEVICE_ID> --domain-type appDataContainer --domain-identifier <APP_BUNDLE_ID> --source <DATABASE_PATH_FROM_DEVICE> --destination /private/tmp/tvosbrowser-history-before-change.sqlite
```

After installing a history change, visit a new page on the device and verify that it appears in **All History** and remains after relaunch. Check database row counts before and after if the UI is ambiguous. Do not add automatic age-based deletion; history is cleared only through an explicit user action. Any move to durable storage must preserve and verify the existing database on the device.
