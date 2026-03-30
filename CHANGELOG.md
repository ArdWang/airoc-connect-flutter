
# AIROC Connect Flutter Changelog

## 0.0.5

**重大 UI 重构和 OTA 流程优化 / Major UI Refactor and OTA Workflow Optimization**

**平台支持 / Platform Support**: Android, iOS, macOS

### 新增功能 / New Features

- **简化 OTA 升级界面** - 将原有的多页面流程简化为单页面三步流程
  - **Step 1: Discover Services** - 发现设备服务（连接时自动配对）
  - **Step 2: Select Firmware** - 选择固件文件
  - **Step 3: Start OTA Upgrade** - 开始升级
- **底部智能提示条** - 根据当前状态动态显示操作提示
- **OTA 完成后自动返回** - 升级完成 2 秒后自动返回扫描界面
- **设备扫描界面简化** - 移除 "OTA only" 开关，默认扫描所有设备

### 修复问题 / Bug Fixes

- **修复配对状态检查逻辑** - 使用 `bondState.first` 等待流更新，避免重复配对弹窗
- **修复 GATT 133 错误** - 在连接前先断开现有连接，防止连接冲突
- **修复配对成功后按钮无响应** - 配对完成后重新检查状态确保 UI 正确更新
- **移除冗余的 Step 1 配对卡片** - 配对在发现服务时自动进行

### 技术改进 / Technical Improvements

- **BLE 连接优化** - 在 `connect()` 方法中增加连接前检查和延迟，避免 GATT 缓存冲突
- **配对时机优化** - 仅在设备未配对时才触发 `createBond()`，已配对设备直接连接
- **错误日志增强** - 添加详细的 bond state 日志便于调试

### 注意事项 / Notes

- **discoverServices() 是必须的** - BLE 每次连接后都必须重新发现服务，这是 BLE 协议标准行为
- ** bootloader 模式可能触发配对** - 设备进入 bootloader 后若改变 MAC 地址，系统会视为新设备要求配对

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
- Support for Infineon AIROC Bluetooth OTA firmware upgrades
- Android, iOS, and macOS platform support
