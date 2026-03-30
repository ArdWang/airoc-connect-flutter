# AIROC Connect Flutter Changelog

## 0.0.5

**Major UI Refactor and OTA Workflow Optimization**

**Platform Support**: Android, iOS, macOS

### New Features

- **Simplified OTA Upgrade Screen** - Refactored multi-page flow into a single-page three-step process
  - **Step 1: Discover Services** - Discover device services (auto-pair on connect)
  - **Step 2: Select Firmware** - Select firmware file
  - **Step 3: Start OTA Upgrade** - Start upgrade
- **Smart Bottom Hint Bar** - Displays dynamic operation hints based on current state
- **Auto-Return After OTA** - Automatically returns to scan screen 2 seconds after upgrade completes
- **Simplified Device Scan Screen** - Removed "OTA only" toggle, scans all devices by default

### Bug Fixes

- **Fixed Pair State Check Logic** - Uses `bondState.first` to wait for stream update, avoiding repeated pairing dialogs
- **Fixed GATT 133 Error** - Disconnects existing connection before reconnecting to prevent connection conflicts
- **Fixed Unresponsive Button After Pairing** - Re-checks state after pairing to ensure UI updates correctly
- **Removed Redundant Step 1 Pair Card** - Pairing now happens automatically during service discovery

### Technical Improvements

- **BLE Connection Optimization** - Added pre-connect checks and delays in `connect()` method to avoid GATT cache conflicts
- **Optimized Pairing Timing** - Only triggers `createBond()` when device is not bonded; directly connects for bonded devices
- **Enhanced Error Logging** - Added detailed bond state logs for debugging

### Notes

- **discoverServices() is Required** - BLE requires rediscovering services after each connection; this is standard BLE protocol behavior
- **Bootloader Mode May Trigger Pairing** - If device changes MAC address after entering bootloader mode, system will treat it as a new device and request pairing

---

## 0.0.4+4

- Update document

## 0.0.3+3

- Modify uuid display error

## 0.0.3+2

- Update other

## 0.0.3+1

- Update document

## 0.0.3

- Initial release with document updates

## 0.0.1

- Initial release of airoc_connect_flutter
- Support for Infineon AIROC Bluetooth® firmware upgrades
- Android, iOS, and macOS platform support
