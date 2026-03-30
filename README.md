# AIROC Connect Flutter 使用说明 / Usage Guide (中文 + English)

> 本文档基于当前示例工程 `example` 的实际实现编写，适合用于快速接入与 OTA 升级流程落地。  
> This guide is based on the current `example` app implementation and is intended for practical integration and OTA workflow setup.

Support Android, iOS  and MacOS platforms.

## notice
final String otaServiceUuid;
final String otaCharacteristicUuid;
By default, the OTA uuid needs to be passed in

## Special Note

The source code comes from @Infineon AIROC™ Bluetooth® Connect App for Android/ iOS (ex CySmart).
[1] https://github.com/Infineon/airoc-connect-android

[2] https://github.com/Infineon/airoc-connect-ios

Thank you very much for their source code

## 0）适用场景 / Use Cases

```agsl
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8
  flutter_blue_plus: ^1.35.4
  permission_handler: ^11.3.1
  file_picker: ^8.1.7
  airoc_connect_flutter: ^0.0.5
  #airoc_connect_flutter:
   # git:
    #  url: https://github.com/ArdWang/airoc-connect-flutter.git
     # ref: tags/0.0.5  # 请查看仓库的 Releases 或 Tags 页面以获取正确的标签名

```


## 1) 项目能力概览 / What This Example Provides

### 中文
- BLE 扫描与设备发现（基于 `flutter_blue_plus`）。
- 仅展示符合名称前缀规则的设备（`blue/ota/r/sc`）。
- 可读取目标设备 GATT 服务与特征 UUID。
- 支持选择 `.cyacd2` / `.cyacd` 固件并执行 OTA。
- 提供 OTA 进度、结果统计、日志展示。

### English
- BLE scan and discovery (via `flutter_blue_plus`).
- Shows only devices matching name-prefix filter (`blue/ota/r/sc`).
- Reads GATT service/characteristic UUIDs from selected device.
- Supports `.cyacd2` / `.cyacd` firmware selection and OTA upgrade.
- Displays OTA progress, result stats, and logs.

---

## 2) 目录与关键文件 / Key Files

### 中文
- `lib/main.dart`：入口 + UUID 选择流程（扫描 -> 读 UUID -> 跳转 OTA 页面）
- `lib/src/ui/device_scan_screen.dart`：选择固件、扫描设备、进入升级
- `lib/src/ui/ota_screen.dart`：执行 OTA、显示进度与结果
- `lib/src/ota/example_ota_manager.dart`：权限、文件读取、OTA 调用编排
- `lib/src/ble/airoc_ble_scanner.dart`：BLE 扫描、设备过滤、状态流
- `android/app/src/main/AndroidManifest.xml`：Android 蓝牙/定位权限
- `ios/Runner/Info.plist`：iOS 蓝牙权限说明 + 固件文件类型注册
- `macos/Runner/Info.plist` + `macos/Runner/DebugProfile.entitlements`：macOS 蓝牙与文件访问能力

### English
- `lib/main.dart`: App entry and UUID selection flow (scan -> read UUIDs -> open OTA screen).
- `lib/src/ui/device_scan_screen.dart`: Firmware selection, device scanning, and upgrade entry.
- `lib/src/ui/ota_screen.dart`: OTA execution, progress, and result display.
- `lib/src/ota/example_ota_manager.dart`: Permission handling, firmware loading, OTA orchestration.
- `lib/src/ble/airoc_ble_scanner.dart`: BLE scanning, device filtering, and stream output.
- `android/app/src/main/AndroidManifest.xml`: Android Bluetooth/location permissions.
- `ios/Runner/Info.plist`: iOS Bluetooth usage descriptions and firmware file type registration.
- `macos/Runner/Info.plist` + `macos/Runner/DebugProfile.entitlements`: macOS Bluetooth and user-selected file access capabilities.

---

## 3) 运行前准备 / Prerequisites

### 中文
- Flutter SDK（此示例建议使用 FVM 管理，示例里已采用 `fvm flutter ...`）。
- Android Studio / Xcode（按目标平台）。
- 实机蓝牙可用，且 OTA 目标设备可广播并可连接。
- 准备 `.cyacd2` 或 `.cyacd` 固件文件。

### English
- Flutter SDK (this example uses FVM and runs with `fvm flutter ...`).
- Android Studio / Xcode (depending on target platform).
- BLE-capable test device and OTA target hardware advertising/connectable.
- A valid `.cyacd2` or `.cyacd` firmware file.

---

## 4) 依赖与安装 / Dependency Setup

`pubspec.yaml` 中示例依赖：
Example dependencies in `pubspec.yaml`:

- `airoc_connect_flutter` (path: `../`)
- `flutter_blue_plus`
- `permission_handler`
- `file_picker`

在工程目录执行：
Run in the project directory:

```bash
cd "/Users/xxx/airoc-connect-flutter/example"
fvm flutter pub get
```

---

## 5) 平台配置要点 / Platform Configuration Notes

### 5.1 Android

**中文**
- 已声明传统蓝牙权限（兼容旧版本）和 Android 12+ 权限：
    - `BLUETOOTH`, `BLUETOOTH_ADMIN`（maxSdkVersion=30）
    - `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`
    - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- 运行时会在 `ExampleOtaManager.ensurePermissions()` 里请求：
    - `bluetoothScan`, `bluetoothConnect`, `locationWhenInUse`

**English**
- Manifest includes both legacy and Android 12+ permissions:
    - `BLUETOOTH`, `BLUETOOTH_ADMIN` (maxSdkVersion=30)
    - `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`
    - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- Runtime permissions are requested in `ExampleOtaManager.ensurePermissions()`.

### 5.2 iOS

**中文**
- `Info.plist` 已包含：
    - `NSBluetoothAlwaysUsageDescription`
    - `NSBluetoothPeripheralUsageDescription`
- 已注册 `.cyacd2` / `.cyacd` 文档类型，便于文件导入。

**English**
- `Info.plist` already includes Bluetooth usage descriptions:
    - `NSBluetoothAlwaysUsageDescription`
    - `NSBluetoothPeripheralUsageDescription`
- `.cyacd2` / `.cyacd` document types are declared for file handling.

### 5.3 macOS

**中文**
- `Info.plist` 提供蓝牙权限说明。
- `DebugProfile.entitlements` 启用了：
    - `com.apple.security.device.bluetooth`
    - `com.apple.security.files.user-selected.read-only`

**English**
- `Info.plist` contains Bluetooth usage descriptions.
- `DebugProfile.entitlements` enables:
    - `com.apple.security.device.bluetooth`
    - `com.apple.security.files.user-selected.read-only`

---

## 6) 典型使用流程（UI） / Typical UI Workflow

### 中文
1. 进入首页后，点击 **Scan Devices**。
2. 在设备列表中点击任意设备进入 OTA 升级界面。
3. **Step 1: Discover Services** - 点击 "Discover Services" 读取服务 UUID（首次连接会自动配对）
4. 选择 `Service UUID` 与 `Characteristic UUID`。
5. **Step 2: Select Firmware** - 点击 "Select Firmware File" 选择 `.cyacd2/.cyacd` 文件。
6. **Step 3: Start OTA Upgrade** - 点击 "Start OTA Upgrade" 开始升级。
7. 观察进度条、结果状态、传输字节数和日志。
8. 升级完成后 2 秒自动返回扫描界面。

### English
1. On the home screen, tap **Scan Devices**.
2. Tap any device to open the OTA upgrade screen.
3. **Step 1: Discover Services** - Tap "Discover Services" to read UUIDs (auto-pair on first connect).
4. Select `Service UUID` and `Characteristic UUID`.
5. **Step 2: Select Firmware** - Tap "Select Firmware File" and choose `.cyacd2/.cyacd`.
6. **Step 3: Start OTA Upgrade** - Tap "Start OTA Upgrade" to begin.
7. Monitor progress bar, status, bytes transferred, and logs.
8. Auto-returns to scan screen 2 seconds after completion.

---

## 7) 编程方式接入（核心思路） / Programmatic Integration Pattern

### 7.1 管理器能力 / Manager Capabilities (`ExampleOtaManager`)

- `ensurePermissions()`：申请/检查权限（Android 重点） / Request and validate permissions (especially on Android)
- `startScan({timeout, otaOnly})`：启动扫描 / Start BLE scanning
- `stopScan()`：停止扫描 / Stop BLE scanning
- `pickFirmwareFile()`：挑选并读取固件 / Pick and load firmware file
- `loadFirmwareFromBytes(bytes, fileName)`：解析固件（`Cyacd2Parser` / `CyacdParser`） / Parse firmware bytes (`Cyacd2Parser` / `CyacdParser`)
- `performOta({device, file, onProgress, securityKeyOverride})`：执行 OTA / Execute OTA
- `cancelOta()`：取消 OTA / Cancel OTA
- `dispose()`：释放资源 / Dispose resources

### 7.2 扫描器行为 / Scanner Behavior (`AirocBleScanner`)

- 扫描结果来源：`FlutterBluePlus.onScanResults` / Scan results come from `FlutterBluePlus.onScanResults`
- 设备过滤 / Device filtering:
    - 名称前缀：`blue/ota/r/sc` / Name prefix filter: `blue/ota/r/sc`
    - `otaOnly=true` 时要求广播里包含 OTA Service UUID / When `otaOnly=true`, advertisement must contain OTA service UUID
- 排序策略：先 OTA 能力，再按 RSSI 降序 / Sort by OTA capability first, then RSSI descending
- Apple 平台稳态处理 / Apple startup stabilization:
    - 扫描前等待适配器状态变为 `on`（短暂初始化窗口） / Wait for adapter state `on` before scanning

### 7.3 简化代码示例 / Minimal Code Example

```dart
final manager = ExampleOtaManager();

final granted = await manager.ensurePermissions();
if (!granted) {
  throw Exception('Permissions not granted');
}

await manager.startScan(otaOnly: true);
// 订阅 manager.scanner.devicesStream 获取设备列表

final otaFile = await manager.pickFirmwareFile();
if (otaFile == null) {
  throw Exception('No firmware selected');
}

final result = await manager.performOta(
  device: selectedDevice,
  file: otaFile,
  onProgress: (p) => print('progress: ${p.progressPercent}%'),
);

print('success=${result.success}, status=${result.status}');
await manager.dispose();
```

---

## 8) 固件文件规则 / Firmware Rules

### 中文
- 仅支持 `.cyacd2` 与 `.cyacd`。
- 在 iOS/macOS/Android 下，文件选择器使用 `FileType.any`，但会在代码中二次校验后缀。
- 若文件类型不匹配，会抛出 `UnsupportedError`。

### English
- Only `.cyacd2` and `.cyacd` are supported.
- On iOS/macOS/Android, picker uses `FileType.any`, then extension is validated in code.
- Unsupported extension throws `UnsupportedError`.

---

## 9) 常见问题与排错 / Troubleshooting

### 9.1 扫描不到设备 / No Devices Found

**中文**
- 检查设备广播名称是否命中前缀过滤 `blue/ota/r/sc`。
- 关闭 `otaOnly` 先看是否能发现设备，再定位 OTA service 广播问题。
- Android 确认蓝牙和定位开关均开启并已授权。

**English**
- Verify device advertisement name matches prefix filter `blue/ota/r/sc`.
- Disable `otaOnly` first to isolate OTA-service filtering issues.
- On Android, ensure Bluetooth + Location are enabled and granted.

### 9.2 Apple 平台首次扫描不稳定 / First Scan Instability on Apple

**中文**
- 可能是蓝牙适配器在 App 启动后短暂处于未就绪状态。
- 当前实现已在扫描前等待适配器 `on`，并在上层做了一次短延时重试。

**English**
- BLE adapter may briefly be non-ready right after app launch.
- Current flow waits for adapter readiness and includes a short retry on Apple.

### 9.3 OTA 失败 / OTA Failed

**中文**
- 确认 Service/Characteristic UUID 选择与设备固件协议匹配。
- 确认固件文件版本、型号、签名策略（如设备侧有约束）一致。
- 在 OTA 页面查看 `errorMessage` 与日志区域定位失败阶段。

**English**
- Confirm selected service/characteristic UUIDs match device OTA protocol.
- Validate firmware/device compatibility and signing/security constraints.
- Check OTA `errorMessage` and log panel for phase-level diagnostics.

---

## 10) 生产落地建议 / Production Recommendations

### 中文
- 将前缀过滤改为可配置，避免硬编码影响量产设备命名策略。
- 增加 OTA 前设备信息校验（型号、版本、分区、最小电量）。
- 记录完整升级审计日志（开始/结束时间、结果、错误码、设备标识）。
- 对中断恢复、超时、重试次数设置可观测指标。

### English
- Make name-prefix filtering configurable for production naming schemes.
- Add preflight checks (model/version/partition/battery threshold).
- Persist OTA audit logs (start/end, status, error code, device identity).
- Add observability around timeout/retry/interruption recovery.

---

## 11) 快速运行命令 / Quick Run Commands

```bash
cd "/Users/xxx/airoc-connect-flutter/example"
fvm flutter pub get
fvm flutter devices
fvm flutter run -d <your-device-id>
```

如需 Android 实机（示例）：
For Android physical device (example):

```bash
cd "/Users/xxx/airoc-connect-flutter/example"
fvm flutter run -d 59221JEBF02444
```

---

## 12) 术语对照 / Glossary

- 固件升级：Firmware Upgrade
- OTA：Over-The-Air
- 服务 UUID：Service UUID
- 特征 UUID：Characteristic UUID
- 扫描过滤：Scan Filter
- 进度回调：Progress Callback
- 传输层：Transport Layer
- 升级结果：Upgrade Result

---

---

## 13) 在新项目中接入（从 0 到可运行） / Using in a New Project (From Scratch)

> 这一节专门回答“不是用 example，而是在一个全新 Flutter 项目里怎么接入”。  
> This section is specifically for integrating into a brand-new Flutter project (not reusing the `example` app directly).

### 13.1 创建项目 / Create a New Project

```bash
flutter create airoc_ota_demo
cd airoc_ota_demo
```

### 13.2 添加依赖 / Add Dependencies

`pubspec.yaml`（三选一，按你的实际来源）:
`pubspec.yaml` (choose one source based on your setup):

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.35.4
  permission_handler: ^11.3.1
  file_picker: ^8.1.7

  # Option A: 本地仓库 / Local repository (same style as this example)
  airoc_connect_flutter:
    path: ../airoc-connect-flutter

  # Option B: Git 仓库 / Git repository (replace with your real URL)
  # airoc_connect_flutter:
  #   git:
  #     url: https://your.git.repo/airoc-connect-flutter.git

  # Option C: pub.dev 版本 / pub.dev version (use actual released version)
  # airoc_connect_flutter: ^x.y.z
```

然后执行：
Then run:

```bash
flutter pub get
```

### 13.3 配置平台权限 / Configure Platform Permissions

#### Android (`android/app/src/main/AndroidManifest.xml`)

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

#### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to discover AIROC devices and perform OTA firmware upgrades.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app communicates with AIROC devices over Bluetooth during OTA updates.</string>
```

#### macOS (`macos/Runner/Info.plist` + entitlements)

`Info.plist` 需有蓝牙用途说明；`DebugProfile.entitlements` 至少包含：
`Info.plist` must include Bluetooth usage descriptions; `DebugProfile.entitlements` should include at least:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

### 13.4 新建一个 OTA 传输层 / Add an OTA Transport Implementation

`airoc_connect_flutter` 需要一个实现 `AirocOtaTransport` 的传输层。  
你可以直接复用 example 里的 `FlutterBluePlusOtaTransport` 逻辑（基于 `flutter_blue_plus`）。

`airoc_connect_flutter` requires a transport implementation of `AirocOtaTransport`.  
You can directly reuse the example's `FlutterBluePlusOtaTransport` logic (based on `flutter_blue_plus`).

建议在新项目创建：`lib/ota/flutter_blue_plus_ota_transport.dart`。
Recommended file path in a new project: `lib/ota/flutter_blue_plus_ota_transport.dart`.

核心职责：
- `connect()`：连接 BLE 设备
- `discover()`：查找 OTA service/characteristic
- `enableNotifications()`：打开通知
- `write()`：写入 OTA 数据包
- `notifications`：接收设备响应
- `disconnect()`：收尾断开

Core responsibilities:
- `connect()`: connect to BLE device
- `discover()`: find OTA service/characteristic
- `enableNotifications()`: enable notifications
- `write()`: write OTA packets
- `notifications`: receive device responses
- `disconnect()`: disconnect and clean up

### 13.5 最小可用流程代码 / Minimal Working Flow

下面代码展示“权限 -> 扫描 -> 选文件 -> OTA”主链路（可放在页面逻辑里）：
The following snippet shows the main path "permissions -> scan -> pick file -> OTA".

```dart
import 'dart:io';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> runOtaFlow(BluetoothDevice device) async {
  // 1) Android runtime permissions
  if (Platform.isAndroid) {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final ok = (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothConnect]?.isGranted ?? false) &&
        (statuses[Permission.locationWhenInUse]?.isGranted ?? false);
    if (!ok) {
      throw Exception('Bluetooth permissions not granted');
    }
  }

  // 2) Select firmware
  final picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  if (picked == null || picked.files.isEmpty) {
    throw Exception('No firmware selected');
  }
  final f = picked.files.single;
  final name = f.name.toLowerCase();
  final bytes = f.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw Exception('Firmware file bytes are empty');
  }

  final OtaFile otaFile;
  if (name.endsWith('.cyacd2')) {
    otaFile = Cyacd2Parser.parse(bytes, fileName: f.name);
  } else if (name.endsWith('.cyacd')) {
    otaFile = CyacdParser.parse(bytes, fileName: f.name);
  } else {
    throw UnsupportedError('Only .cyacd2 / .cyacd are supported');
  }

  // 3) Build OTA service and execute
  final transport = FlutterBluePlusOtaTransport(device);
  final ota = AirocOtaService(transport: transport);
  final result = await ota.performOta(
    otaFile,
    onProgress: (p) {
      // Update UI here
      // e.g. print('${p.status.name} ${p.progressPercent}%');
    },
  );

  await ota.dispose();

  if (!result.success) {
    throw Exception('OTA failed: ${result.errorMessage ?? result.status.name}');
  }
}
```

### 13.6 扫描设备建议 / Device Scan Recommendations

**中文**
- 如果你照搬 example 的扫描器，默认会过滤名称前缀 `blue/ota/r/sc`。
- 新项目若设备命名不同，请去掉或改成可配置，否则会出现“搜不到设备”。

**English**
- If you copy the example scanner, it filters by name prefix `blue/ota/r/sc`.
- In a new project, remove or make this configurable if your device naming differs.

### 13.7 首次接入自检清单 / First-Integration Checklist

- [*] `pubspec.yaml` 中 `airoc_connect_flutter` 来源配置正确（path/git/pub） / `airoc_connect_flutter` source in `pubspec.yaml` is correct (path/git/pub)
- [*] Android/iOS/macOS 权限声明完整 / Android/iOS/macOS permissions are fully declared
- [*] Android 运行时权限已请求并放行 / Android runtime permissions are requested and granted
- [*] 目标设备 OTA Service/Characteristic UUID 与代码一致 / OTA service/characteristic UUIDs match target device
- [*] 固件格式是 `.cyacd2` 或 `.cyacd` / Firmware format is `.cyacd2` or `.cyacd`
- [*] OTA 过程中有进度与错误日志输出 / OTA flow has progress and error logs


