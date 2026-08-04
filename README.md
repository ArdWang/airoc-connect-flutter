# AIROC Connect Flutter

> Infineon AIROC™ Bluetooth® OTA (Over-The-Air) Firmware Upgrade Plugin for Flutter

[![Version](https://img.shields.io/pub/v/airoc_connect_flutter.svg)](https://pub.dev/packages/airoc_connect_flutter)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Support Android, iOS and macOS platforms.

## Overview

This plugin provides Bluetooth OTA firmware upgrade capabilities for Infineon AIROC™ Bluetooth® devices. It implements the AIROC OTA protocol and supports both `.cyacd2` and `.cyacd` firmware formats.

## Features

- BLE device scanning and discovery
- **Explicit manual pairing** — pair once before upgrade, no surprise dialogs
- **Single continuous connection** — iOS-style single-connection model, no repeated reconnection
- Service and characteristic UUID discovery with property filtering
- `.cyacd2` and `.cyacd` firmware file support
- Real-time OTA progress updates
- **Color-coded debug logging** with ANSI terminal colors
- Smart operation hints based on current state
- Auto-return to scan screen after OTA completion
- **Auto-detection of write mode** (write vs writeWithoutResponse)

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter:
    sdk: flutter

  airoc_connect_flutter: ^0.0.7
```

### Platform Requirements

- **Android**: API level 21+ (Android 5.0+)
- **iOS**: iOS 13.0+
- **macOS**: macOS 10.15+

## Usage

### Quick Start

```dart
import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';

// Create OTA manager
final manager = ExampleOtaManager();

// Check permissions (Android only)
final granted = await manager.ensurePermissions();
if (!granted) {
  throw Exception('Permissions not granted');
}

// Start scanning
await manager.startScan(otaOnly: false);

// Subscribe to device list
manager.scanner.devicesStream.listen((devices) {
  // Update UI with discovered devices
});

// Pair with device before OTA
final paired = await manager.pairDevice(selectedDevice);
if (!paired) throw Exception('Pairing failed');

// Select firmware and perform OTA
final otaFile = await manager.pickFirmwareFile();
final result = await manager.performOta(
  device: selectedDevice,
  file: otaFile,
  onProgress: (progress) {
    print('Progress: ${progress.progressPercent}%');
  },
);

print('OTA Success: ${result.success}');
await manager.dispose();
```

### OTA Screen Integration

The plugin provides a ready-to-use OTA screen widget:

```dart
// Navigate to OTA screen
Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => OtaScreen(
      device: device,
      manager: manager,
    ),
  ),
);
```

### OTA Screen Workflow

The OTA screen implements a clear four-step workflow:

1. **Step 1: Pair Device**
   - Tap "Pair Device" to pair with the device
   - Device status chip shows pairing progress (Not Paired → Pairing… → Paired ✓)
   - Subsequent steps are locked until pairing succeeds

2. **Step 2: Discover Services**
   - Tap "Discover Services" to read device UUIDs
   - Only characteristics with WRITE + NOTIFY properties are shown
   - Select Service UUID and Characteristic UUID from dropdown menus

3. **Step 3: Select Firmware**
   - Tap "Select Firmware File" to choose a `.cyacd2` or `.cyacd` file
   - File details (rows, size) are displayed after selection

4. **Step 4: Start OTA Upgrade**
   - Tap "Start OTA Upgrade" to begin the firmware upgrade
   - Monitor progress via the progress bar and log viewer
   - Automatically returns to scan screen after completion

### Bottom Hint Bar

The screen includes a smart hint bar that displays context-aware messages:

| State | Hint Message |
|-------|--------------|
| Not paired | "Step 1: Tap 'Pair Device' to pair with the device first." |
| Services not discovered | "Step 2: Tap 'Discover Services' to read device UUIDs." |
| Firmware not selected | "Step 3: Tap 'Select Firmware' to choose a firmware file." |
| Ready to start | "Ready! Tap 'Start OTA Upgrade' to begin the firmware update." |

## Configuration

### Android

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
```

### iOS

Add the following to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to discover AIROC devices and perform OTA firmware upgrades.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app communicates with AIROC devices over Bluetooth during OTA updates.</string>
```

### macOS

Add the following to `macos/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to discover AIROC devices and perform OTA firmware upgrades.</string>
```

Add entitlements to `macos/Runner/DebugProfile.entitlements`:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

## API Reference

### ExampleOtaManager

| Method | Description |
|--------|-------------|
| `ensurePermissions()` | Request runtime permissions (Android) |
| `startScan({timeout, otaOnly})` | Start BLE device scanning |
| `stopScan()` | Stop BLE device scanning |
| `pickFirmwareFile()` | Open file picker and load firmware |
| `loadFirmwareFromBytes(bytes, fileName)` | Parse firmware from bytes |
| `performOta({device, file, onProgress})` | Execute OTA upgrade |
| `cancelOta()` | Cancel ongoing OTA upgrade |
| `isDeviceBonded(device)` | Check if device is paired |
| `pairDevice(device)` | Pair (bond) with the device |
| `getDeviceBondState(device)` | Get current bond state string |
| `dispose()` | Release resources |

### AirocBleScanner

| Method | Description |
|--------|-------------|
| `startScan({timeout, otaOnly})` | Start scanning with optional filters |
| `stopScan()` | Stop scanning |
| `devicesStream` | Stream of discovered devices |

### AirocOtaService

| Method | Description |
|--------|-------------|
| `performOta(file, onProgress)` | Execute OTA upgrade |
| `cancel()` | Cancel upgrade |
| `dispose()` | Release resources |
| `progressStream` | Stream of progress updates |

### OtaProgress

| Field | Description |
|-------|-------------|
| `status` | Current OTA status |
| `progress` | Progress percentage (0-100) |
| `bytesTransferred` | Bytes transferred so far |
| `totalBytes` | Total bytes to transfer |
| `message` | Human-readable status message |

### OtaResult

| Field | Description |
|-------|-------------|
| `success` | Whether upgrade succeeded |
| `status` | Final OTA status |
| `bytesTransferred` | Total bytes transferred |
| `duration` | Time taken for upgrade |
| `errorMessage` | Error message (if failed) |

## Troubleshooting

### No Devices Found

- Verify device advertisement name matches prefix filter (`blue/ota/r/sc/upg`)
- Disable `otaOnly` first to isolate OTA-service filtering issues
- On Android, ensure Bluetooth + Location are enabled and granted

### First Scan Instability on Apple Platforms

- BLE adapter may briefly be non-ready right after app launch
- Current flow waits for adapter readiness and includes a short retry

### OTA Failed

- Confirm selected service/characteristic UUIDs match device OTA protocol
- Validate firmware/device compatibility and signing/security constraints
- Check OTA `errorMessage` and log panel for phase-level diagnostics
- Verify the characteristic supports WRITE + NOTIFY properties (Step 2 only shows valid ones)

### "WRITE property not supported" Error

- The plugin now auto-detects write mode — verify your characteristic has either `write` or `writeWithoutResponse` property
- Step 2 dropdown only shows characteristics with valid write properties

### "Device is not paired" Error

- Make sure you complete Step 1 (Pair Device) before starting the upgrade
- If the device was previously paired, the app will detect it automatically on init
- On Android, ensure the device accepts the pairing request

## Firmware File Format

- **Supported formats**: `.cyacd2` and `.cyacd`
- **File validation**: Extension is validated after file selection
- **Invalid files**: Throws `UnsupportedError` for unsupported formats

## Production Recommendations

- Make name-prefix filtering configurable for production naming schemes
- Add preflight checks (model/version/partition/battery threshold)
- Persist OTA audit logs (start/end, status, error code, device identity)
- Add observability around timeout/retry/interruption recovery

## Special Note

This source code is derived from Infineon AIROC™ Bluetooth® Connect App for Android/iOS (formerly CySmart).

- [Infineon airoc-connect-android](https://github.com/Infineon/airoc-connect-android)
- [Infineon airoc-connect-ios](https://github.com/Infineon/airoc-connect-ios)

Thank you to the Infineon team for providing the reference implementation.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
