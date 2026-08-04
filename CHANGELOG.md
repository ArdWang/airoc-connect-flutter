# AIROC Connect Flutter Changelog

## 0.0.7

**OTA Workflow Redesign & Connection Stability**

**Platform Support**: Android, iOS, macOS

### New Features

- **Explicit Manual Pairing** — Added "Pair Device" as Step 1 in the OTA workflow. Users must manually pair before proceeding to service discovery and upgrade. Paired state is visually indicated (Not Paired / Pairing… / Paired ✓).
- **4-Step OTA Workflow** — Expanded from 3 steps to 4 steps for clearer operation flow:
  - **Step 1: Pair Device** — Manually pair with the device
  - **Step 2: Discover Services** — Read device service UUIDs
  - **Step 3: Select Firmware** — Choose a firmware file
  - **Step 4: Start OTA Upgrade** — Begin the firmware update
- **Colorized Debug Logging** — Terminal output now uses ANSI color coding: level-specific badges (blue=info, yellow=warning, red=error), green tags, gray timestamps, magenta TX / cyan RX hex dumps.
- **Characteristic Property Filtering** — Service discovery dropdowns now only show characteristics that support both WRITE and NOTIFY capabilities.

### Bug Fixes

- **Fixed Repeated Pairing Prompts** — Eliminated unnecessary disconnect/reconnect cycles throughout the OTA flow. A single continuous BLE connection is now maintained from pairing through OTA completion, matching iOS CoreBluetooth behavior.
- **Fixed "WRITE property not supported" Error** — Transport layer now auto-detects whether the characteristic supports `write` or `writeWithoutResponse` and uses the correct write mode.
- **Fixed Multiple `createBond()` Calls** — Removed auto-pairing logic from the transport layer. Pairing is now exclusively handled by the user-facing "Pair Device" step.

### Technical Improvements

- **Single Continuous Connection** — `FlutterBluePlusOtaTransport.connect()` no longer forces disconnect/reconnect when the device is already connected. It reuses the existing connection to avoid bond re-negotiation.
- **Transport Write Detection** — `write()` auto-falls back to `writeWithoutResponse` when the characteristic lacks WRITE property.
- **Characteristic Discovery** — `discover()` logs all characteristic properties and selects the best match with both WRITE and NOTIFY capabilities.
- **Pairing State Management** — Bond state is checked on OTA screen init to detect previously-paired devices.

### Notes

- **One Connection, One Pairing** — Following the iOS CoreBluetooth model, the app now uses a single Bluetooth connection throughout the entire OTA session. Users should only see the pairing dialog once.

---

## 0.0.6

**Version Bump**

- Update version from 0.0.5 to 0.0.6

---

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
