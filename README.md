# AIROC Connect Flutter

> Infineon AIROC™ Bluetooth® OTA (Over-The-Air) Firmware Upgrade Plugin for Flutter

[![Version](https://img.shields.io/pub/v/airoc_connect_flutter.svg)](https://pub.dev/packages/airoc_connect_flutter)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Support Android, iOS and macOS platforms.

## Overview

This plugin provides Bluetooth OTA firmware upgrade capabilities for Infineon AIROC™ Bluetooth® devices. It implements the AIROC OTA protocol and supports both `.cyacd2` and `.cyacd` firmware formats.

## Features

- BLE device scanning and discovery
- Automatic device pairing on first connection
- Service and characteristic UUID discovery
- `.cyacd2` and `.cyacd` firmware file support
- Real-time OTA progress updates
- Detailed error logging and diagnostics
- Smart operation hints based on current state
- Auto-return to scan screen after OTA completion

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter:
    sdk: flutter

  airoc_connect_flutter: ^0.0.5
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

The OTA screen implements a streamlined three-step workflow:

1. **Step 1: Discover Services**
   - Tap "Discover Services" to read device UUIDs
   - System will automatically prompt for pairing on first connect
   - Select Service UUID and Characteristic UUID from dropdown menus

2. **Step 2: Select Firmware**
   - Tap "Select Firmware File" to choose a `.cyacd2` or `.cyacd` file
   - File details (rows, size) are displayed after selection

3. **Step 3: Start OTA Upgrade**
   - Tap "Start OTA Upgrade" to begin the firmware upgrade
   - Monitor progress via the progress bar and log viewer
   - Automatically returns to scan screen after completion

### Bottom Hint Bar

The screen includes a smart hint bar that displays context-aware messages:

| State | Hint Message |
|-------|--------------|
| Services not discovered | "Step 1: Tap 'Discover Services' to read device UUIDs (pairing will happen automatically on first connect)." |
| Firmware not selected | "Step 2: Tap 'Select Firmware' to choose a firmware file." |
| Ready to start | "Ready! Note: Device may prompt for pairing again when entering bootloader mode - this is normal." |

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
| `pairDevice(device)` | Pair with device |
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

- Verify device advertisement name matches prefix filter (`blue/ota/r/sc`)
- Disable `otaOnly` first to isolate OTA-service filtering issues
- On Android, ensure Bluetooth + Location are enabled and granted

### First Scan Instability on Apple Platforms

- BLE adapter may briefly be non-ready right after app launch
- Current flow waits for adapter readiness and includes a short retry

### OTA Failed

- Confirm selected service/characteristic UUIDs match device OTA protocol
- Validate firmware/device compatibility and signing/security constraints
- Check OTA `errorMessage` and log panel for phase-level diagnostics

### Repeated Pairing Prompts

- If device changes MAC address in bootloader mode, system treats it as new device
- This is expected behavior and cannot be avoided
- User should confirm pairing prompt when it appears

### GATT 133 Error

- Usually caused by connection conflicts or GATT cache issues
- Current implementation includes automatic disconnection and retry logic
- Ensure device is not connected to other apps during OTA

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
