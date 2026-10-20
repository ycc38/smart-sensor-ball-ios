# TestFlight Test Plan

## Pre-Test Setup

1. Install the TestFlight build.
2. Grant Bluetooth permission when prompted.
3. Hit the training device once to wake Bluetooth, then ensure its name starts with `SENBALL#` and ends with a digit.

## Smoke Tests

1. Launch app for the first time.
2. Confirm the app prompts the user to open Settings and connect Bluetooth.
3. Open Settings.
4. Tap Scan.
5. Confirm only names beginning with `SENBALL#` and ending with a digit appear.
6. Relaunch the app and confirm it automatically scans for and reconnects to the last successfully connected device.
6. Select and connect a device.
7. Confirm connection status turns active and battery appears on the home screen.

## Training Tests

1. Tap Start.
2. Confirm the app shows `3, 2, 1, GO`.
3. Confirm iOS sends `C5 5C 04 01` after the countdown.
4. Hit the ball and confirm punch count increments from data2.
5. Let training finish or tap End.
6. Confirm iOS sends `C5 5C 04 00`.

## Regression Tests

- Disconnect while training.
- Start training without Bluetooth connected.
- Switch among Chinese, English, French, Spanish, German, Korean, and Thai.
- Open privacy policy and user agreement.

