# Android 14 → Android 17 Framework：屏幕、电源、功耗与 PMS/CMPS 源码级比较

## 0. 范围与结论先行

本文聚焦 Android Framework 中与屏幕、电源、功耗、显示图层直接相关的业务链路，并覆盖 PackageManagerService（PMS）及车载场景常写作 **CPMS** 的 CarPowerManagementService。若项目内部将"CMPS"用于 Component/Configuration Management，本文第 6 节也给出对应的 ATMS/WMS/PMS 拆分；AOSP 并不存在一个统一命名为"CMPS"的通用核心服务。

比较基线：Android 14（API 34）与 Android 17（API 37，AOSP `android-17.0.0_r1`）。本文区分三种变化：

1. **Framework 源码结构变化**：类、服务、线程、Binder、状态机和策略位置变化。
2. **系统行为变化**：即使应用不重新编译也可能受到影响。
3. **公开 API/targetSdk 行为变化**：需要应用或系统应用迁移。

Android 17 中的 Memory Limiter、mmd、PMGD、ION 淘汰、Audio Managed SCO 等属于平台/设备实现要求，不应误写成全部设备默认开启的 SDK API。[AOSP Android 17 发布说明](https://source.android.com/docs/whatsnew/android-17-release)

## 1. 源码树和核心调用链

### 1.1 关键目录

| 领域 | 主要源码目录（AOSP） | 关键类/服务 |
|---|---|---|
| 公共 Framework API | `frameworks/base/core/java/android/` | `PowerManager`、`Display`、`WindowManager`、`ActivityOptions` |
| system_server 服务 | `frameworks/base/services/core/java/com/android/server/` | `PowerManagerService`、`DisplayManagerService`、`WindowManagerService`、`ActivityManagerService` |
| Activity/任务与配置 | `frameworks/base/services/core/java/com/android/server/wm/` | `ActivityTaskManagerService`、`ActivityRecord`、`DisplayContent`、`RootWindowContainer` |
| 包与组件 | `frameworks/base/services/core/java/com/android/server/pm/` | `PackageManagerService`、`PackageInstallerService`、`Computer` |
| 显示合成 | `frameworks/native/services/surfaceflinger/` | `SurfaceFlinger`、Scheduler、Layer、CompositionEngine |
| 电源 HAL | `hardware/interfaces/power/`、`hardware/interfaces/thermal/` | Power HAL、Thermal HAL |
| 内存与低内存 | `system/memory/lmkd/`、Android 17 相关 memory limiter/mmd/PMGD | lmkd、cgroup v2、ZRAM 管理 |

### 1.2 屏幕点亮链路

```text
应用/系统 UI
  → PowerManager.wakeUp()/goToSleep()
  → PowerManagerService（PMS）
  → DisplayPowerController / DisplayManagerService（DMS）
  → DisplayPowerState / PhotonicModulator
  → SurfaceFlinger、HWC、Display HAL
  → 屏幕面板
```

PMS 负责"是否应该亮、亮度/Doze/锁屏等电源策略"；DMS 负责"显示设备状态如何实现"；SurfaceFlinger 负责"图层如何合成并提交到硬件"。

### 1.3 Activity 配置与窗口链路

```text
PMS 扫描 APK manifest
  → ActivityTaskManagerService（ATMS）解析 Activity/Task
  → WindowManagerService（WMS）创建 WindowToken/WindowState
  → DisplayContent 管理显示屏和 Insets
  → SurfaceControl.Transaction
  → SurfaceFlinger Layer 树
```

因此，屏幕旋转、宽高比、Activity 重建、桌面窗口和图层可见性，不能只看 WMS；它们同时受 PMS 的 manifest 信息、ATMS 的配置策略和 SurfaceFlinger 的合成策略影响。

## 2. PowerManagerService：电源状态机源码拆分

### 2.1 模块职责

`PowerManagerService`（PMS）运行在 `system_server`，通过 Binder 暴露 `IPowerManager`，集中处理：

- `wakeLock` 生命周期、WorkSource 归因和超时；
- `wakeUp`、`goToSleep`、用户活动和屏幕关闭原因；
- Dream/Doze、屏保、手动亮度和自动亮度策略；
- 电池状态、插拔、热状态和低电量策略；
- 与 DisplayManagerService、ActivityManagerService、WindowManagerPolicy、Power HAL 的协作。

源码上可按四层阅读：

1. **Binder 入口**：`PowerManagerService` 的 `acquireWakeLockInternal`、`releaseWakeLockInternal`、`wakeUpInternal`。
2. **状态汇聚**：用户活动、WakeLock、Dream、车载/外接屏等输入汇聚为 `PowerGroup`/显示电源请求。
3. **策略计算**：根据 Interactive、Doze、UserActivity、Proximity、低电量和亮度限制计算 DisplayPowerRequest。
4. **异步执行**：Handler/Policy 线程向 DMS 和 Power HAL 下发状态，避免 Binder 调用阻塞主线程。

### 2.2 Android 14 基线

Android 14 的电源侧重点是后台执行约束：精确闹钟默认不再普遍预授予，前台服务必须声明类型，JobScheduler 超时会触发更严格的 ANR，缓存进程和后台广播受到限制。[Android 14 变更列表](https://developer.android.google.cn/about/versions/14/summary?hl=en)

这类策略并未把 PMS 重写为"功耗管理器"，而是通过 AMS/JobScheduler/AlarmManager 减少唤醒源，再由 PMS 处理最终的交互状态和 WakeLock。

### 2.3 Android 17 变化

- **更严格的后台资源边界**：应用内存限制按设备 RAM 计算并在运行时执行，后台进程的存活和功耗结果更可预测。
- **精确闹钟监听器能力增强**：`setExactAndAllowWhileIdle(OnAlarmListener)` 可减少不必要的 PendingIntent/WakeLock 组合。
- **后台音频与电源策略联动**：不可见应用或无合法前台服务时，音频播放、焦点和音量请求可能直接失败，避免"后台音频长期保持唤醒"。[Android 17 功能总表](https://developer.android.com/about/versions/17/summary)
- **设备侧内存治理**：Memory Limiter、mmd 和 PMGD 与 lmkd/cgroup v2 协作，对每进程内存和 ZRAM 进行更主动的限制。[AOSP Android 17 发布说明](https://source.android.com/docs/whatsnew/android-17-release)

### 2.4 功耗影响分析

Android 14 的功耗优化主要是"减少进入唤醒路径的机会"；Android 17 增加了"即使进程仍存活，也限制其资源预算"的机制。功耗调试应同时观察：

```text
dumpsys power
dumpsys batterystats
dumpsys alarm
dumpsys jobscheduler
dumpsys deviceidle
dumpsys meminfo <package>
```

## 3. DisplayManagerService 与屏幕电源实现

### 3.1 模块职责

DMS 管理 Logical Display/Physical Display、DisplayDevice、显示模式、亮度和显示电源状态。典型路径是：

```text
PowerManagerService
  → DisplayManagerInternal.requestPowerState()
  → DisplayPowerController.requestPowerState()
  → DisplayPowerState
  → DisplayDevice.setState()/setBrightness()
  → SurfaceFlinger/HWC
```

`DisplayPowerController` 负责策略平滑、亮度动画、自动亮度、Doze 和 proximity；`DisplayDevice`/SurfaceFlinger 负责把状态落到物理显示设备。

### 3.2 Android 14 基线

- 支持更丰富的 HDR/Ultra HDR 显示路径；
- Graphics API 增加 Path 查询与插值、Custom Mesh、`HardwareBufferRenderer`；
- 预测性返回和大屏配置覆盖推动 WMS/DMS 处理更多动态配置；
- 外接屏、折叠屏和多窗口场景继续增加 Display 组合。

### 3.3 Android 17 变化

1. **每显示屏桌面窗口**：可按 Display 启用 desktop windowing，DMS 的 DisplayContent、WMS 的 RootWindowContainer 和 SystemUI 的装饰需要共同支持。[AOSP Android 17 发布说明](https://source.android.com/docs/whatsnew/android-17-release)
2. **大屏适配强制化**：`sw >= 600dp` 且 target 37 的应用不能再绕过方向、宽高比和 resizeable 约束。[Android 17 发布说明](https://developer.android.com/about/versions/17/release-notes)
3. **WebGPU 与 Vulkan 路径**：图形框架增加面向 WebGPU 的能力，底层仍依赖 Vulkan/GPU 驱动。[Android 17 功能与 API](https://developer.android.com/about/versions/17/features)
4. **配置变化处理更动态**：多屏、桌面和窗口尺寸变化增多，Activity 不应假定每次配置变化都会销毁重建。

### 3.4 OEM 关注点

- Display HAL 是否支持目标 mode、刷新率和亮度接口；
- HWC2 是否正确处理多 Display 和 composition type；
- SurfaceFlinger 的 Scheduler 是否能在多屏场景维持帧率；
- SystemUI 是否为每个 Display 创建正确的状态栏、导航栏和桌面装饰；
- 自动亮度、Doze、AOD 和车载屏幕是否与 Power HAL 一致。

## 4. SurfaceFlinger、Layer 与显示图层

### 4.1 源码职责拆分

SurfaceFlinger 位于 `frameworks/native`，与 Java Framework 的边界主要是 SurfaceControl/BufferQueue：

1. **应用侧**：ViewRootImpl/RenderThread 生产 GraphicBuffer。
2. **窗口侧**：WMS 通过 SurfaceControl 创建和排序窗口 Surface。
3. **合成侧**：SurfaceFlinger 将 Layer 树、Buffer、Transform、Crop、Alpha、色彩空间合并。
4. **硬件侧**：CompositionEngine 选择 GPU 或 HWC 合成，提交 Present。

### 4.2 Android 14 → 17

Android 14 重点是渲染能力扩展：Path 插值、Mesh Shader、HardwareBufferRenderer 和 Ultra HDR。Android 17 重点转向多显示屏桌面窗口、WebGPU 和更复杂的窗口装饰协同。换言之，Layer 本身的基本模型没有被替换，但 Layer 树的来源从单屏任务栈扩展到多 Display、桌面窗口和跨设备连续性。

### 4.3 图层问题定位

```text
dumpsys SurfaceFlinger --list
dumpsys SurfaceFlinger
dumpsys window windows
dumpsys display
atrace gfx view wm sched freq idle
```

常见故障映射：

| 现象 | 优先检查 |
|---|---|
| 黑屏但系统已唤醒 | PMS/DMS 电源状态、DisplayDevice、HWC |
| 有 Layer 无内容 | BufferQueue、Fence、RenderThread、SurfaceFlinger |
| 图层顺序错误 | WMS z-order、SurfaceControl Transaction |
| 旋转后窗口错位 | Configuration、DisplayContent、Insets、Transform |
| 多屏掉帧 | SurfaceFlinger Scheduler、HWC 合成能力、Power HAL 频点 |

## 5. PMS：APK、组件与屏幕行为的上游输入

### 5.1 模块职责

PackageManagerService 负责 APK 解析、组件注册、权限、签名、包可见性和 manifest 配置。对于显示业务，PMS 提供的上游信息包括：

- Activity 的 `screenOrientation`、`resizeableActivity`、`minAspectRatio`、`maxAspectRatio`；
- Activity 是否属于 Game；
- 组件导出属性、权限和启动能力；
- 应用 targetSdk、screen support 和窗口相关 manifest 属性。

PMS 将包信息写入 Settings/PackageState，由 ATMS/WMS 在启动 Activity 和计算窗口配置时读取。

### 5.2 Android 14 基线

- target API 低于 23 的 APK 禁止安装；
- PackageInstaller 增加应用商店相关 API和应用元数据包；
- 动态代码加载文件只读，Zip Path Traversal 防护；
- 隐式 Intent、PendingIntent 和后台 Activity 启动约束增强。

### 5.3 Android 17 变化

- PQC APK 签名支持；
- target 17 访问 NPU 必须声明 `android.hardware.npu`；
- Native DCL 安全检查继续加强；
- 大屏场景下，WMS/ATMS 对 manifest 方向和宽高比约束不再允许 target 17 应用退出。

这里的关键变化是：Android 14 主要在 PMS 的"安装和安全校验"路径收紧；Android 17 通过 PMS 提供的包元数据，进一步影响 WMS/ATMS 的窗口策略。

## 6. CMPS（组件/配置管理策略）实际源码拆分

由于 AOSP 没有名为 CMPS 的单一核心服务，建议按以下可验证的源码责任拆分：

### 6.1 组件管理：PMS → ATMS

```text
PackageManagerService
  → Package/ActivityInfo
  → ActivityTaskManagerService.startActivity()
  → ActivityRecord
```

PMS 决定"组件是什么、是否可导出、声明了什么配置"；ATMS 决定"何时启动、放入哪个 Task、属于哪个 Display"。

### 6.2 配置管理：ConfigurationController → ActivityRecord

配置来源包括 Display 尺寸、旋转、density、字体、夜间模式、窗口边界和用户设置。Android 17 多屏/桌面窗口使配置不再只由"设备全局 Display"决定，而是更频繁地按 Display、Task、Window 传播。

### 6.3 窗口策略：WMS/WindowManagerPolicy

WMS 计算窗口层级、Insets、旋转和可见性；WindowManagerPolicy 处理锁屏、状态栏、导航栏和按键策略。Android 17 的大屏强制适配和 per-display desktop windowing，主要落在这一层，而不是 PMS 单独完成。

## 7. 车载 CPMS（CarPowerManagementService）源码级拆分

如果用户所称 CMPS 实际指 **CPMS/CarPowerManagementService**，它位于 Car Service，而不是 `frameworks/base` 的通用 `PowerManagerService`。典型目录为 `packages/services/Car/service/src/com/android/car/power/`，核心对象包括 `CarPowerManagementService`、`PowerComponentHandler`、`CarPowerPolicy` 和与 VHAL 交互的电源接口。

### 7.1 职责与调用链

```text
Vehicle HAL（AP_POWER_STATE_REQ / 状态变化）
  → CarPowerManagementService
  → PowerComponentHandler / CarPowerPolicy
  → PowerManager.setPowerSaveMode()/wakeUp()/goToSleep()
  → DisplayPowerController / WMS / SystemUI
```

CPMS 处理车载电源状态机（On、Suspend、Shutdown 等）、电源策略组件（音频、屏幕、网络、投影等）和关机准备回调；PMS 则负责 Android 通用电源状态和 WakeLock。二者通过 Car Service、PowerManager API 及 VHAL 事件协同，不能混为一个服务。

### 7.2 Android 14 基线

- 车载电源状态由 Car Power Policy 和 VHAL 请求驱动；
- CPMS 负责向各 Car Service 组件广播电源策略，协调屏幕、音频、网络和用户体验；
- 屏幕最终亮灭仍由 PMS/DMS/Display HAL 执行，CPMS 只负责车载域的策略和时序。

### 7.3 Android 17 变化

- AOSP Android 17 引入 **Software Defined Vehicle（SDV）** 方向，要求车载系统把车辆功能、显示和电源策略作为可软件更新的平台能力；
- **Scalable UI/高级窗口**支持多面板、动态布局和定制系统/导航栏，CPMS 的屏幕策略需要覆盖多 Display，而不再是假定单一中控屏；
- CPMS 与 PMS/DMS 的边界更重要：车辆休眠/唤醒仍由 CPMS/VHAL 决定，具体 Display 状态和图层合成仍由 DMS/WMS/SurfaceFlinger 完成。[AOSP Android 17 发布说明](https://source.android.com/docs/whatsnew/android-17-release)

### 7.4 车载功耗调试

建议同时抓取：

```text
dumpsys car_service --services CarPowerManagementService
dumpsys power
dumpsys display
dumpsys SurfaceFlinger --list
```

若车辆已进入 Suspend 但屏幕仍亮，优先检查 CPMS 电源策略和 VHAL 状态；若 PMS 已进入非交互但仍有图层输出，则检查 DMS、WMS 和 SurfaceFlinger；若频繁唤醒，则检查 WakeLock、Vehicle HAL 请求和 CarPowerPolicy 组件。

## 8. Android 14 与 17 源码级差异矩阵

| 业务 | Android 14 | Android 17 | 影响 |
|---|---|---|---|
| 屏幕唤醒 | PMS + DMS + Power HAL，主要围绕 Doze/亮度/WakeLock | 增加严格资源预算、后台音频限制、设备级内存治理 | 唤醒源和进程资源需要联合分析 |
| 显示设备 | 单屏/多屏基础管理，大屏覆盖 | per-display desktop windowing、车载 Scalable UI | DMS/WMS/SystemUI/HWC 都需升级 |
| 图层 | SurfaceFlinger Layer 基本模型，HDR/Buffer 渲染增强 | WebGPU、多屏桌面图层和装饰协同 | 合成、调度和 Layer 树复杂度上升 |
| Activity 配置 | 预测返回、大屏 override | target 37 大屏不得绕过方向/比例约束 | PMS 元数据直接影响 WMS 策略 |
| 功耗 | 精确闹钟、FGS、JobScheduler、广播收紧 | RAM 级内存限制、Memory Limiter、PMGD/mmd | lmkd/OOM_adj 之外增加主动限额 |
| PMS | 安装安全、动态代码只读、最低 target API | PQC 签名、NPU Feature、Native DCL 加强 | 安装链和硬件能力声明升级 |
| 音频 | USB 无损、HDR/相机能力扩展 | 后台音频硬化、SCO 路由迁移、Assistant 音量流 | Audio Framework 与 PMS/电源策略耦合增强 |

## 9. 建议的源码阅读与回归顺序

1. 先读 `PowerManagerService`、`DisplayManagerService`、`DisplayPowerController`，建立屏幕电源状态机。
2. 再读 `ActivityTaskManagerService`、`ActivityRecord`、`DisplayContent`、`RootWindowContainer`，理解任务/配置/窗口传播。
3. 对照 `PackageManagerService`、`PackageInstallerService`、`PackageInfo`/`ActivityInfo`，确认 manifest 元数据如何进入窗口策略。
4. 最后进入 `SurfaceFlinger`、`Layer`、`CompositionEngine` 和 HWC，定位实际图层合成与掉帧问题。
5. 用 `dumpsys power/display/window/surfaceflinger` 建立运行时状态与源码状态的对应关系。

## 10. 参考资料

- [AOSP Android 17 发布说明](https://source.android.com/docs/whatsnew/android-17-release)
- [Android 17 功能与变更总表](https://developer.android.com/about/versions/17/summary)
- [Android 17 Features and APIs](https://developer.android.com/about/versions/17/features)
- [Android 17 Release Notes](https://developer.android.com/about/versions/17/release-notes)
- [Android 14 功能与变更总表](https://developer.android.google.cn/about/versions/14/summary?hl=en)
- [AOSP Frameworks/Base Android 17 标签](https://android.googlesource.com/platform/frameworks/base/+android-17.0.0_r1)
- [Android 平台架构](https://source.android.google.cn/docs/core/architecture?hl=en)
