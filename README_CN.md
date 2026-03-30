# AIROC Connect Flutter

> 英飞凌 AIROC™ Bluetooth® OTA (空中) 固件升级 Flutter 插件

[![Version](https://img.shields.io/pub/v/airoc_connect_flutter.svg)](https://pub.dev/packages/airoc_connect_flutter)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

支持 Android、iOS 和 macOS 平台。

## 概述

本插件为英飞凌 AIROC™ Bluetooth® 设备提供蓝牙 OTA 固件升级功能。它实现了 AIROC OTA 协议，支持 `.cyacd2` 和 `.cyacd` 两种固件格式。

## 功能特性

- BLE 设备扫描和发现
- 首次连接时自动配对
- 服务和特征 UUID 发现
- `.cyacd2` 和 `.cyacd` 固件文件支持
- 实时 OTA 进度更新
- 详细的错误日志和诊断
- 基于当前状态的智能操作提示
- OTA 完成后自动返回扫描界面

## 安装

将此添加到你的 `pubspec.yaml` 文件中：

```yaml
dependencies:
  flutter:
    sdk: flutter

  airoc_connect_flutter: ^0.0.5
```

### 平台要求

- **Android**: API 21+ (Android 5.0+)
- **iOS**: iOS 13.0+
- **macOS**: macOS 10.15+

## 使用方法

### 快速开始

```dart
import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';

// 创建 OTA 管理器
final manager = ExampleOtaManager();

// 检查权限（仅 Android）
final granted = await manager.ensurePermissions();
if (!granted) {
  throw Exception('权限未授予');
}

// 开始扫描
await manager.startScan(otaOnly: false);

// 订阅设备列表
manager.scanner.devicesStream.listen((devices) {
  // 使用发现的设备更新 UI
});

// 选择固件并执行 OTA
final otaFile = await manager.pickFirmwareFile();
final result = await manager.performOta(
  device: selectedDevice,
  file: otaFile,
  onProgress: (progress) {
    print('进度：${progress.progressPercent}%');
  },
);

print('OTA 成功：${result.success}');
await manager.dispose();
```

### OTA 界面集成

插件提供即开即用的 OTA 界面组件：

```dart
// 导航到 OTA 界面
Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => OtaScreen(
      device: device,
      manager: manager,
    ),
  ),
);
```

### OTA 界面工作流程

OTA 界面实现了简化的三步工作流程：

1. **Step 1: Discover Services（发现服务）**
   - 点击 "Discover Services" 读取设备 UUID
   - 首次连接时系统会自动提示配对
   - 从下拉菜单中选择 Service UUID 和 Characteristic UUID

2. **Step 2: Select Firmware（选择固件）**
   - 点击 "Select Firmware File" 选择 `.cyacd2` 或 `.cyacd` 文件
   - 选择后显示文件详情（行数、大小）

3. **Step 3: Start OTA Upgrade（开始升级）**
   - 点击 "Start OTA Upgrade" 开始固件升级
   - 通过进度条和日志查看器监控进度
   - 完成后自动返回扫描界面

### 底部提示条

界面包含智能提示条，显示上下文相关的消息：

| 状态 | 提示消息 |
|------|--------|
| 未发现服务 | "Step 1: Tap 'Discover Services' to read device UUIDs (pairing will happen automatically on first connect)." |
| 未选择固件 | "Step 2: Tap 'Select Firmware' to choose a firmware file." |
| 准备开始 | "Ready! Note: Device may prompt for pairing again when entering bootloader mode - this is normal." |

## 配置

### Android

将以下权限添加到 `android/app/src/main/AndroidManifest.xml`：

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

将以下内容添加到 `ios/Runner/Info.plist`：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to discover AIROC devices and perform OTA firmware upgrades.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app communicates with AIROC devices over Bluetooth during OTA updates.</string>
```

### macOS

将以下内容添加到 `macos/Runner/Info.plist`：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to discover AIROC devices and perform OTA firmware upgrades.</string>
```

将授权添加到 `macos/Runner/DebugProfile.entitlements`：

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

## API 参考

### ExampleOtaManager

| 方法 | 描述 |
|------|------|
| `ensurePermissions()` | 请求运行时权限（Android） |
| `startScan({timeout, otaOnly})` | 启动 BLE 设备扫描 |
| `stopScan()` | 停止 BLE 设备扫描 |
| `pickFirmwareFile()` | 打开文件选择器并加载固件 |
| `loadFirmwareFromBytes(bytes, fileName)` | 从字节解析固件 |
| `performOta({device, file, onProgress})` | 执行 OTA 升级 |
| `cancelOta()` | 取消正在进行的 OTA 升级 |
| `isDeviceBonded(device)` | 检查设备是否已配对 |
| `pairDevice(device)` | 与设备配对 |
| `dispose()` | 释放资源 |

### AirocBleScanner

| 方法 | 描述 |
|------|------|
| `startScan({timeout, otaOnly})` | 使用可选过滤器开始扫描 |
| `stopScan()` | 停止扫描 |
| `devicesStream` | 发现设备的流 |

### AirocOtaService

| 方法 | 描述 |
|------|------|
| `performOta(file, onProgress)` | 执行 OTA 升级 |
| `cancel()` | 取消升级 |
| `dispose()` | 释放资源 |
| `progressStream` | 进度更新流 |

### OtaProgress

| 字段 | 描述 |
|------|------|
| `status` | 当前 OTA 状态 |
| `progress` | 进度百分比（0-100） |
| `bytesTransferred` | 已传输字节数 |
| `totalBytes` | 要传输的总字节数 |
| `message` | 人类可读的状态消息 |

### OtaResult

| 字段 | 描述 |
|------|------|
| `success` | 升级是否成功 |
| `status` | 最终 OTA 状态 |
| `bytesTransferred` | 传输的总字节数 |
| `duration` | 升级所用时间 |
| `errorMessage` | 错误消息（如果失败） |

## 故障排除

### 找不到设备

- 验证设备广播名称是否匹配前缀过滤器（`blue/ota/r/sc`）
- 先禁用 `otaOnly` 以隔离 OTA 服务过滤问题
- 在 Android 上，确保蓝牙和定位已启用并授权

### Apple 平台首次扫描不稳定

- BLE 适配器可能在应用启动后短暂处于未就绪状态
- 当前流程等待适配器就绪并包含短延时重试

### OTA 失败

- 确认选择的服务/特征 UUID 与设备 OTA 协议匹配
- 验证固件/设备兼容性和签名/安全约束
- 检查 OTA `errorMessage` 和日志面板获取阶段级诊断

### 重复配对提示

- 如果设备在 bootloader 模式下改变 MAC 地址，系统会将其视为新设备
- 这是预期行为，无法避免
- 用户应在出现配对提示时确认

### GATT 133 错误

- 通常由连接冲突或 GATT 缓存问题引起
- 当前实现包含自动断开和重试逻辑
- 确保 OTA 期间设备未连接到其他应用

## 固件文件格式

- **支持的格式**：`.cyacd2` 和 `.cyacd`
- **文件验证**：文件选择后验证扩展名
- **无效文件**：不支持的格式会抛出 `UnsupportedError`

## 生产环境建议

- 使名称前缀过滤可配置以适应生产命名方案
- 添加预检查（型号/版本/分区/电池阈值）
- 持久化 OTA 审计日志（开始/结束、状态、错误码、设备标识）
- 添加超时/重试/中断恢复的可观测性

## 特别说明

本源代码源自英飞凌 AIROC™ Bluetooth® Connect App for Android/iOS（前身为 CySmart）。

- [Infineon airoc-connect-android](https://github.com/Infineon/airoc-connect-android)
- [Infineon airoc-connect-ios](https://github.com/Infineon/airoc-connect-ios)

感谢英飞凌团队提供参考实现。

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 贡献

欢迎贡献！请随时提交 Pull Request。
