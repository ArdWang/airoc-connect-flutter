# AIROC Connect Flutter 更新日志

## 0.0.7

**OTA 工作流程重新设计 & 连接稳定性优化**

**平台支持**：Android、iOS、macOS

### 新增功能

- **OTA 完成后自动取消配对** - 升级完成后自动取消配对以清理配对状态：Android 调用 `removeBond()`，iOS/macOS 断开连接（CoreBluetooth 无编程式取消配对接口）。
- **显式手动配对** — 在 OTA 工作流程中添加"配对设备"作为步骤 1。用户必须先手动配对才能继续服务发现和升级。配对状态有视觉化指示（未配对 / 配对中… / 已配对 ✓）。
- **四步 OTA 工作流程** — 从三步扩展为四步，操作流程更清晰：
  - **步骤 1: 配对设备 (Pair Device)** — 手动与设备配对
  - **步骤 2: 发现服务 (Discover Services)** — 读取设备服务 UUID
  - **步骤 3: 选择固件 (Select Firmware)** — 选择固件文件
  - **步骤 4: 开始升级 (Start OTA Upgrade)** — 开始固件更新
- **彩色调试日志** — 终端输出现在使用 ANSI 颜色编码：级别徽章（蓝=信息、黄=警告、红=错误）、绿色标签、灰色时间戳、品红色 TX / 青色 RX 十六进制数据。
- **特征值属性过滤** — 服务发现下拉菜单现在只显示同时支持 WRITE 和 NOTIFY 能力的特征值。

### 修复问题

- **修复 macOS 配对 "android-only" 报错** — 配对和 OTA 不再在 macOS/iOS 上抛出 `android-only`。示例 App 此前在所有平台无条件调用 `flutter_blue_plus` 中仅 Android 支持的 API（`createBond()`、`bondState`），现已用 `Platform.isAndroid` 进行守卫。iOS/macOS（CoreBluetooth）没有给 App 的编程式配对接口，`pairDevice()` 仅建立连接，配对由系统在访问加密特征值时隐式触发；`isDeviceBonded()` / `isBonded` 回退到连接状态判定。Android 保持原有显式 `createBond()` 流程不变。
- **修复重复配对弹窗** — 消除了整个 OTA 流程中不必要的断开/重连循环。现在从配对到 OTA 完成维护一个连续的 BLE 连接，匹配 iOS CoreBluetooth 的行为。
- **修复 "WRITE property not supported" 错误** — 传输层现在自动检测特征值支持 `write` 还是 `writeWithoutResponse`，并使用正确的写入模式。
- **修复多次 `createBond()` 调用** — 从传输层移除了自动配对逻辑。配对现在完全由用户操作的"配对设备"步骤处理。

### 技术改进

- **单一连续连接** — `FlutterBluePlusOtaTransport.connect()` 在设备已连接时不再强制断开/重连，而是复用现有连接以避免绑定重新协商。
- **传输层写入检测** — `write()` 在特征值缺少 WRITE 属性时自动回退到 `writeWithoutResponse`。
- **特征值发现增强** — `discover()` 记录所有特征值属性，并选择同时具有 WRITE 和 NOTIFY 能力的最佳匹配。
- **配对状态管理** — OTA 界面初始化时检查绑定状态以识别已配对的设备。

### 注意事项

- **一次连接，一次配对** — 遵循 iOS CoreBluetooth 模型，应用现在在整个 OTA 会话中使用单一的蓝牙连接。用户应该只会看到一次配对弹窗。

---

## 0.0.6

**版本更新**

- 版本号从 0.0.5 更新到 0.0.6

---

## 0.0.5

**重大 UI 重构和 OTA 流程优化**

**平台支持**：Android、iOS、macOS

### 新增功能

- **简化 OTA 升级界面** - 将原有的多页面流程简化为单页面三步流程
  - **Step 1: Discover Services** - 发现设备服务（连接时自动配对）
  - **Step 2: Select Firmware** - 选择固件文件
  - **Step 3: Start OTA Upgrade** - 开始升级
- **底部智能提示条** - 根据当前状态动态显示操作提示
- **OTA 完成后自动返回** - 升级完成 2 秒后自动返回扫描界面
- **设备扫描界面简化** - 移除 "OTA only" 开关，默认扫描所有设备

### 修复问题

- **修复配对状态检查逻辑** - 使用 `bondState.first` 等待流更新，避免重复配对弹窗
- **修复 GATT 133 错误** - 在连接前先断开现有连接，防止连接冲突
- **修复配对成功后按钮无响应** - 配对完成后重新检查状态确保 UI 正确更新
- **移除冗余的 Step 1 配对卡片** - 配对在发现服务时自动进行

### 技术改进

- **BLE 连接优化** - 在 `connect()` 方法中增加连接前检查和延迟，避免 GATT 缓存冲突
- **配对时机优化** - 仅在设备未配对时才触发 `createBond()`，已配对设备直接连接
- **错误日志增强** - 添加详细的 bond state 日志便于调试

### 注意事项

- **discoverServices() 是必须的** - BLE 每次连接后都必须重新发现服务，这是 BLE 协议标准行为
- **Bootloader 模式可能触发配对** - 设备进入 bootloader 后若改变 MAC 地址，系统会视为新设备要求配对

---

## 0.0.4+4

- 更新文档

## 0.0.3+3

- 修复 UUID 显示错误

## 0.0.3+2

- 其他更新

## 0.0.3+1

- 更新文档

## 0.0.3

- 初始版本发布，包含文档更新

## 0.0.1

- airoc_connect_flutter 初始版本发布
- 支持英飞凌 AIROC Bluetooth® 固件 OTA 升级
- 支持 Android、iOS 和 macOS 平台
