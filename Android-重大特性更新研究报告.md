# Android 重大特性更新研究报告

> 创建时间：2026-03-21
> 状态：📝 完整版

---

## 目录

1. [概述](#概述)
2. [OTA 更新系统](#ota-更新系统)
3. [Framework 核心架构](#framework-核心架构)
4. [车载视频系统](#车载视频系统)
5. [休眠唤醒机制](#休眠唤醒机制)
6. [电源管理](#电源管理)
7. [功耗优化](#功耗优化)
8. [云服务集成](#云服务集成)
9. [总结与展望](#总结与展望)

---

## 概述

Android 在车载系统 (Android Automotive OS, AAOS) 领域持续演进，针对车辆特殊场景引入了多项重大特性更新。本报告聚焦以下核心领域：

- **OTA 更新系统** - Virtual A/B 无缝升级
- **Framework 核心** - Car Service 架构
- **车载视频** - EVS 增强型视觉系统
- **休眠唤醒** - 深度睡眠/休眠机制
- **电源管理** - 状态机与政策系统
- **功耗优化** - 车库模式与低功耗设计
- **云服务** - 远程访问与数据同步

---

## OTA 更新系统

### 一、演进历程

#### 1.1 早期方案：Recovery OTA（Android 6 及以前）

```
下载完整 OTA 包 → 重启进入 recovery → 直接覆盖分区
```

**问题：**
- 升级期间设备不可用（停机）
- 失败容易变砖
- 无法回滚

#### 1.2 A/B 分区（Android 7+）

设备拥有两套分区：

```
┌─────────────────┐
│  当前运行: Slot A │
├─────────────────┤
│  备用分区: Slot B │
└─────────────────┘
```

**升级流程：**
1. 系统在后台下载 OTA
2. 把新系统写入 B 分区
3. 重启 → 切换到 B
4. 启动成功 → 标记成功
5. 启动失败 → 自动回滚到 A

**优点：** 无需停机、安全回滚、用户无感

**缺点：** 占用两倍分区空间、写入成本高

#### 1.3 动态分区（Android 10+）

```
system / vendor / product 不再是固定分区
            ↓
统一放在 super 分区里（逻辑分区）
```

**好处：** 分区大小可动态调整、OTA 更灵活

#### 1.4 Virtual A/B（Android 11+）- 当前主流

这是目前车机、手机都在用的主流方案，也是"合并过程"的根因。

### 二、Virtual A/B 核心机制

#### 2.1 为什么会有"合并过程"？

**核心答案：** Virtual A/B 使用了 **快照（snapshot）+ Copy-on-Write（COW）机制**

#### 2.2 升级时的写入方式

**传统 A/B：**
```
直接写 B 分区（完整镜像）
```

**Virtual A/B：**
```
创建 snapshot（快照）
      ↓
写入差异数据（COW）
```

#### 2.3 Snapshot 工作原理

升级时：
```
原始分区（system）
        ↓
创建 snapshot（逻辑映射）
        ↓
新数据写入 COW 文件
```

系统结构变为：
```
[旧数据] + [COW差异块] = 新系统视图
```

#### 2.4 合并（merge）过程

```
merge: COW → base partition

完成后：
system 分区 = 完整新系统
COW 被删除
```

**设计权衡：**

| 方案 | 优点 | 缺点 |
|------|------|------|
| 直接写分区 | 简单 | 慢 + 不安全 |
| snapshot + merge | 快速切换 + 可回滚 | 需要后处理 |

### 三、核心组件

#### 3.1 update_engine

Android OTA 的核心执行体，是一个 **状态机驱动的分块更新引擎**。

**整体流程：**
```
云端 OTA 包
   ↓
下载（HTTP/HTTPS）
   ↓
校验（metadata + payload hash）
   ↓
解析 payload.bin
   ↓
执行 InstallOperation
   ↓
写入 snapshot（Virtual A/B）
   ↓
标记 slot 可启动
   ↓
重启切换 slot
   ↓
merge（后台）
```

#### 3.2 payload.bin 结构

```
payload.bin
 ├── header
 ├── manifest（protobuf）
 └── data blobs
```

#### 3.3 InstallOperation 类型

| 类型 | 作用 |
|------|------|
| REPLACE | 全量写块 |
| REPLACE_BZ | 压缩块 |
| SOURCE_COPY | 从旧分区复制 |
| SOURCE_BSDIFF | 二进制差分 |
| ZERO | 填零 |

#### 3.4 snapuserd / dm-user

用户态守护进程，负责：
- 处理 snapshot 的读写请求
- COW 文件管理
- merge 过程执行

### 四、车机 OTA 架构设计

#### 4.1 整体架构

```
    云端 OTA 平台
          ↓
  （灰度 / 分批 / 策略）
          ↓
   车端 OTA Agent
          ↓
  update_engine（执行）
          ↓
 snapshot / merge（系统层）
```

#### 4.2 关键设计要点

**回滚策略：**
- 业务健康检查
- 超时回滚
- 服务启动验证

**灰度发布：**
```
1% → 5% → 20% → 50% → 100%
```

**分区升级策略：**

| 分区 | 策略 |
|------|------|
| boot | 强一致 |
| system | OTA |
| vendor | 慎重 |
| 应用层 | 独立升级（APK） |

#### 4.3 merge 优化策略

1. **延迟 merge** - 仅在熄火、夜间、充电时
2. **限速** - 使用 blkio.throttle.write_bps_device
3. **分阶段 merge** - system → vendor → product
4. **可中断 merge** - 防止用户启动时卡顿

---

## Framework 核心架构

### 一、Car Service 架构

Android Automotive 的核心是 Car Service，它提供了车辆特定的功能和服务。

#### 1.1 核心组件

```
┌─────────────────────────────────────────┐
│              Car Service                 │
├─────────────────────────────────────────┤
│  ├── CarPowerManagementService          │
│  ├── CarPropertyService                 │
│  ├── CarAudioService                    │
│  ├── CarInputService                    │
│  ├── CarUserService                     │
│  └── CarPackageManagerService           │
├─────────────────────────────────────────┤
│              Vehicle HAL (VHAL)         │
└─────────────────────────────────────────┘
```

#### 1.2 CarService 启动流程

```
SystemServer 启动
      ↓
CarServiceLoader 加载
      ↓
ICarImpl 初始化
      ↓
各 CarService 子服务启动
      ↓
与 VHAL 建立连接
      ↓
系统就绪
```

### 二、VHAL（车载硬件抽象层）

#### 2.1 概述

VHAL 定义了 OEM 可以实现的属性，包含属性元数据。VHAL 接口以对属性的访问（读取、写入和订阅）为基础。

**演进：**
- Android 12 及以下：HIDL 语言（`IVehicle.hal`）
- Android 13+：迁移到 AIDL（`IVehicle.aidl`）

#### 2.2 核心功能

```
┌──────────────────────────────────────────┐
│                 VHAL                       │
├──────────────────────────────────────────┤
│  属性访问：                                │
│  ├── 读取 (get)                           │
│  ├── 写入 (set)                           │
│  └── 订阅 (subscribe)                     │
├──────────────────────────────────────────┤
│  属性类型：                                │
│  ├── 系统属性（预定义）                    │
│  ├── 厂商属性（OEM 自定义）                │
│  └── ADAS 属性（高级驾驶辅助）             │
└──────────────────────────────────────────┘
```

#### 2.3 关键属性类别

- **车身控制：** 车门、车窗、座椅、后视镜
- **驾驶辅助：** ADAS、车道保持、自适应巡航
- **电源管理：** AP_POWER_STATE_REQ/REPORT
- **环境感知：** 温度、光照、雨量

### 三、CarPowerManager

#### 3.1 状态定义

```java
public static final int STATE_ON                    = 0;
public static final int STATE_SHUTDOWN_PREPARE      = 1;
public static final int STATE_SHUTDOWN_ENTER        = 2;
public static final int STATE_POST_SHUTDOWN_ENTER   = 3;
public static final int STATE_SUSPEND_ENTER         = 4;
public static final int STATE_POST_SUSPEND_ENTER    = 5;
public static final int STATE_SUSPEND_EXIT          = 6;
public static final int STATE_HIBERNATION_ENTER     = 7;
public static final int STATE_HIBERNATION_EXIT      = 8;
public static final int STATE_WAIT_FOR_VHAL         = 9;
```

#### 3.2 API 使用示例

```java
Car car = Car.createCar(this);
CarPowerManager powerManager = (CarPowerManager) 
    car.getCarManager(android.car.Car.POWER_SERVICE);

CarPowerManager.CarPowerStateListener listener = 
    new CarPowerManager.CarPowerStateListener() {
        @Override
        public void onStateChanged(int state) {
            // 处理电源状态变化
        }
    };

powerManager.setListener(listener, executor);
```

---

## 车载视频系统

### 一、概述

Android Automotive 提供两个不同的摄像头 API：

#### 1.1 EVS（增强型视觉系统）

- **用途：** 后视摄像头、环绕视图
- **特点：** 对 Android 系统服务依赖最小，早期可用
- **限制：** 仅适用于系统和第一方应用

#### 1.2 Camera2 API

- **用途：** 视频会议、传统摄像头体验
- **特点：** 与其他 Android 服务紧密耦合
- **适用：** 系统、1P、3P 应用

### 二、EVS 架构

```
┌─────────────────────────────────────────┐
│           EVS Application                │
├─────────────────────────────────────────┤
│           CarEvsService                  │
├─────────────────────────────────────────┤
│           EVS HAL                        │
├─────────────────────────────────────────┤
│           Camera Hardware                │
└─────────────────────────────────────────┘
```

### 三、EVS 1.1 新特性

#### 3.1 事件和帧通知机制

回调机制，让 EVS 管理器和硬件模块对应用中的流式传输事件发出通知。

#### 3.2 摄像头控制参数

getter/setter 方法，用于在视频流活跃时更改摄像头参数。

#### 3.3 多摄像头支持

逻辑摄像头设备，包含多个实体摄像头设备。

#### 3.4 车载显示屏代理服务

新服务，用于启用 HAL 实现以使用 SurfaceFlinger。

### 四、应用场景

| 场景 | 推荐方案 | 启动时机 |
|------|----------|----------|
| 后视摄像头 | EVS | Android 启动初期 |
| 环绕视图 | EVS | Android 启动初期 |
| 视频会议 | Camera2 | Android 完全启动后 |
| 行车记录仪 | EVS | 后台持续运行 |

---

## 休眠唤醒机制

### 一、硬件架构

```
┌──────────────────────────────────────────────────┐
│                    VMCU                           │
│         (车载微控制器单元)                         │
├──────────────────────────────────────────────────┤
│  • 与车辆原生接口（CAN 总线）连接                  │
│  • 控制 AP 的电源                                 │
│  • 通过数据总线和 GPIO 与 AP 通信                 │
└──────────────────────────────────────────────────┘
          ↓ GPIO / SPI / UART
┌──────────────────────────────────────────────────┐
│                     AP                            │
│         (应用处理器 - Android)                    │
└──────────────────────────────────────────────────┘
```

### 二、电源状态定义

#### 2.1 睡眠（Sleep）

- VMCU 决定保留 AP 主电源
- 唤醒信号通过 GPIO 发送到 AP
- 快速唤醒

#### 2.2 休眠（Hibernate）

- VMCU 切断主电源，但保留内存内容
- 下次开机时加载保存的内存内容
- 中等唤醒速度

#### 2.3 关闭（Shutdown）

- VMCU 保留电池电量
- AP 下次开机必须冷启动
- 最慢唤醒

### 三、状态机

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│    ┌──────────┐                                          │
│    │ 挂起到RAM │ ◄─────────────────────────────────────┐ │
│    └────┬─────┘                                        │ │
│         │ 唤醒                                         │ │
│         ↓                                              │ │
│    ┌──────────┐                                        │ │
│    │等待 VHAL │                                        │ │
│    └────┬─────┘                                        │ │
│         │ VHAL 就绪                                    │ │
│         ↓                                              │ │
│    ┌──────────┐        关闭请求      ┌──────────┐     │ │
│    │   开启   │ ───────────────────► │ 关闭准备 │     │ │
│    └──────────┘                      └────┬─────┘     │ │
│         ▲                                 │           │ │
│         │                                 ↓           │ │
│         │                           ┌──────────┐     │ │
│         │                           │等待VHAL完│     │ │
│         │                           └────┬─────┘     │ │
│         │                                │           │ │
│         └────────────────────────────────┴───────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 四、进入深度睡眠流程

```
VMCU 发送关闭通知
      ↓
CPMS 广播 SHUTDOWN_PREPARE 状态
      ↓
应用/服务执行 onStateChanged()
      ↓
所有 CPM 对象完成关闭准备
      ↓
CPMS 发送 AP_POWER_STATE_REPORT
      ↓
VHAL 通知 VMCU AP 准备挂起
      ↓
CPMS 调用内核挂起方法
      ↓
系统进入深度睡眠
```

### 五、VHAL 电源属性

#### 5.1 AP_POWER_STATE_REPORT

Android 向 VMCU 报告状态转换：

| 值 | 说明 |
|-----|------|
| WAIT_FOR_VHAL | AP 正在启动 |
| DEEP_SLEEP_ENTRY | AP 进入深度睡眠 |
| DEEP_SLEEP_EXIT | AP 退出深度睡眠 |
| HIBERNATION_ENTRY | AP 进入休眠 |
| HIBERNATION_EXIT | AP 退出休眠 |
| SHUTDOWN_PREPARE | Android 准备关闭 |
| SHUTDOWN_START | AP 准备好关闭 |

#### 5.2 AP_POWER_STATE_REQ

VMCU 指示 Android 转换电源状态：

| 值 | 说明 |
|-----|------|
| ON | AP 应开始完全正常运行 |
| SHUTDOWN_PREPARE | AP 应准备关闭 |
| CANCEL_SHUTDOWN | AP 应停止准备关闭 |
| FINISHED | AP 应已关闭或挂起 |

---

## 电源管理

### 一、核心需求

车载应用对电源的要求与移动设备有很大差异：

1. **停放时几乎零耗电** - 即使数月后仍有足够电量启动
2. **快速响应** - 后视摄像头、音频、启动画面的开机反应极快
3. **快速启动** - 用户可以立即与设备互动
4. **状态恢复** - 重启后可以继续/恢复应用状态

### 二、电源政策（Power Policy）

#### 2.1 概述

电源政策确保根据需要选择性地开启和关闭硬件和软件组件。

#### 2.2 组件控制

- 屏幕
- 音频
- 语音互动
- 传感器
- 通信模块

#### 2.3 政策示例

```
政策名称: "no_audio"
禁止组件: AUDIO
允许组件: DISPLAY, INPUT
```

### 三、车库模式（Garage Mode）

#### 3.1 概念

车库模式为汽车提供空闲时间，让系统保持唤醒状态，直到 JobScheduler 中的作业执行完成。

**工作原理：**
```
用户关闭引擎
      ↓
系统进入车库模式
      ↓
显示屏关闭，系统电源保持接通
      ↓
执行 JobScheduler 队列中的空闲作业
      ↓
作业完成或超时
      ↓
系统关闭
```

#### 3.2 实现

VHAL 发送 `AP_POWER_STATE_REQ`：
- 状态：`SHUTDOWN_PREPARE`
- 参数：`SHUTDOWN_ONLY` 或 `CAN_SLEEP`

#### 3.3 应用使用

```java
public class MyGarageModeJob extends JobService { ... }

JobInfo.Builder infoBuilder = new JobInfo.Builder(jobId, myGarageModeJobName)
    .setRequiresDeviceIdle(true);  // 关键：要求设备空闲

infoBuilder.setRequiredNetworkType(NetworkType.NETWORK_TYPE_UNMETERED);

JobScheduler jobScheduler = (JobScheduler) 
    context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
jobScheduler.schedule(infoBuilder.build());
```

### 四、启动时间优化

#### 4.1 优化目标

- 后视摄像头：100ms 内显示
- 音频：1s 内可用
- Android 主屏幕：5s 内显示

#### 4.2 优化策略

1. **并行初始化** - 独立服务并行启动
2. **延迟加载** - 非关键服务延迟启动
3. **预加载** - 关键资源预加载
4. **内核优化** - 减少内核启动时间

---

## 功耗优化

### 一、功耗来源分析

#### 1.1 硬件层面

| 组件 | 功耗占比 | 优化方向 |
|------|----------|----------|
| SoC | 30-40% | 休眠、降频 |
| 显示屏 | 20-30% | 亮度调节、关闭 |
| 通信模块 | 10-20% | 休眠、断开 |
| 音频 | 5-10% | 关闭 |

#### 1.2 软件层面

- 系统服务运行
- 后台进程
- 网络连接
- 唤醒锁

### 二、优化策略

#### 2.1 深度睡眠优化

```
正常模式 ──► 浅睡眠 ──► 深度睡眠 ──► 休眠
   │           │           │           │
   ↓           ↓           ↓           ↓
 全功耗      低功耗     极低功耗     几乎零功耗
 RAM保持     RAM保持     RAM断电     RAM写入磁盘
```

#### 2.2 唤醒源管理

**关键原则：** 设备处于挂起模式时，必须停用所有唤醒源，唯一有效的唤醒源应来自 VMCU。

**常见唤醒源：**
- 心跳检测信号
- 调制解调器
- Wi-Fi
- 蓝牙

#### 2.3 分时复用

```
时间轴：
├── 驾驶时段 ── 全功能运行
├── 停车时段 ── 车库模式（维护任务）
├── 熄火时段 ── 深度睡眠
└── 长期停放 ── 休眠/关闭
```

### 三、监控与调优

#### 3.1 关键指标

```
- 升级成功率
- 升级耗时
- merge 耗时
- 回滚率
- 分区失败率
- 唤醒时间
- 睡眠功耗
```

#### 3.2 调试命令

```bash
# 启用车库模式日志
adb shell setprop log.tag.GarageMode VERBOSE
adb shell setprop log.tag.CAR.POWER VERBOSE

# 查看电源状态
adb logcat | grep "CAR.POWER"

# 查看 merge 状态
ls /metadata/ota/snapshots
```

---

## 云服务集成

### 一、远程访问

Android Automotive 支持远程访问功能，允许从云端发起对车辆的操作。

#### 1.1 应用场景

- 远程启动
- 远程解锁
- 远程空调控制
- 远程诊断
- 远程 OTA

#### 1.2 架构

```
┌─────────────────┐
│   云端服务       │
├─────────────────┤
│   远程访问网关   │
├─────────────────┤
│   VMCU          │
├─────────────────┤
│   AP (Android)  │
└─────────────────┘
```

### 二、数据同步

#### 2.1 车辆数据上传

- 驾驶行为数据
- 车辆状态数据
- 诊断数据
- 位置信息

#### 2.2 云端数据下发

- 导航数据
- 音乐/媒体
- 天气信息
- OTA 包

### 三、OTA 云端平台

#### 3.1 核心能力

**版本管理：**
- base version
- target version
- 兼容矩阵

**灰度策略：**
- VIN 分组
- 地域
- 车型
- 用户画像

**包管理：**
- 全量包
- 增量包（delta）
- 差分算法优化

#### 3.2 安全机制

- HTTPS 传输
- 签名验证
- 完整性校验
- 灰度控制

---

## 总结与展望

### 一、技术演进趋势

#### 1.1 OTA 系统

- **更快：** 增量更新算法优化
- **更安全：** 多重校验、回滚保障
- **更灵活：** 分区升级、独立组件更新

#### 1.2 电源管理

- **更深：** 更低功耗的睡眠模式
- **更快：** 更快的唤醒响应
- **更智能：** 基于场景的自适应策略

#### 1.3 车载视频

- **更高清：** 4K/8K 支持
- **更低延迟：** 毫秒级响应
- **更智能：** AI 增强视觉

### 二、关键挑战

1. **功耗与性能的平衡**
   - 深度睡眠 vs 快速唤醒
   - 功能完整 vs 低功耗

2. **OTA 可靠性**
   - 大版本跨度的增量更新
   - 复杂分区的协调升级
   - 断电恢复机制

3. **实时性要求**
   - 后视摄像头毫秒级响应
   - 关键服务的优先级保障

### 三、建议

1. **架构层面**
   - 模块化设计，支持独立升级
   - 明确的电源状态转换边界
   - 完善的监控和告警体系

2. **实现层面**
   - 充分利用 Virtual A/B 的优势
   - 合理配置车库模式参数
   - 优化 merge 时机和策略

3. **测试层面**
   - 全面的电源状态转换测试
   - OTA 升级回滚测试
   - 长期停放功耗测试

---

## 参考资料

1. [Android Open Source Project - Automotive](https://source.android.com/docs/automotive)
2. [Android OTA 更新架构](https://source.android.com/docs/core/ota)
3. [Android 车载电源管理](https://source.android.com/docs/automotive/power)
4. [EVS 增强型视觉系统](https://source.android.com/docs/automotive/camera/evs)
5. [VHAL 车载硬件抽象层](https://source.android.com/docs/automotive/vhal)

---

*本报告持续更新中...*