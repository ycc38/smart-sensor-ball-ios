# Smart sensor ball iOS

This directory contains the initial iOS source project for **Smart sensor ball**.

## Scope

- SwiftUI main app UI
- CoreBluetooth scanning and connection for `SENBALL#` devices
- Telemetry parsing compatible with the Android protocol:
  - Header: `D5 5D 03`
  - Packet size: 11 bytes
  - Byte 3: packet index
  - Byte 4: data1 / battery level (`0...100`; legacy `101` charging and `102` full remain supported)
  - Byte 5: data2 / punch count
  - Byte 6: data3 / charging flag (`0` not charging, `1` charging)
  - Bytes 9-10: force in little-endian order
- Gyroscope commands:
  - Connect success: `C5 5C 04 00`
  - Training start: `C5 5C 04 01`
  - Training end/stop: `C5 5C 04 00`
- LED commands:
  - Light off: `C5 5C 07 00`
  - Light on and brightness: `C5 5C 07 01 XX` (`XX` is `0...99`; the app slider displays `0...100`)
- The first bundled punch sound is preloaded locally; the app does not request cloud sound effects.
- A local user profile is generated automatically; registration, login, and activation codes are not required.
- API base URL: `https://sensorball.86086.cn/sensorball/api/v1/`
- Chinese, English, French, and Thai UI text
- Privacy policy and user agreement assets

## Build Requirements

- macOS
- Xcode 15 or newer recommended
- iOS 15+ deployment target
- Apple Developer account for real-device signing and TestFlight

## Cloud IPA Builds

This project includes `codemagic.yaml` and a shared Xcode scheme for cloud macOS builds.

- `ios-simulator-check`: compile check without Apple signing.
- `ios-signed-ipa`: App Store signed IPA workflow. This requires Apple Developer Program membership and App Store Connect integration in Codemagic.

See `Docs/Codemagic_IPA_Build.md` for the step-by-step setup.

## App Icon Note

The brand SVG has been copied into `SmartSensorBall/Resources/Brand`. Before App Store submission, export PNG app icons from the SVG and fill the `AppIcon.appiconset`.
