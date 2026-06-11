# Android PowerHal 与 PowerKey 架构分析

> **分类**: Android 架构
> **更新**: 2026-06-11
> **标签**: PowerHal / PowerKey / Framework / HAL / Android

---

## 1. PowerHal 定位：Framework 还是 HAL？

### 1.1 架构层次总览

```
┌─────────────────────────────────────────┐
│           Framework 层 (Java/Kotlin)     │
│   PowerManagerService / PowerHintManager │
└─────────────────┬───────────────────────┘
                  │ 调用
                  ▼
┌─────────────────────────────────────────┐
│          HAL 层 (AIDL/HIDL)              │
│         IPowerHal / PowerHal│
└─────────────────┬───────────────────────┘
                  │ 调用
                  ▼
┌─────────────────────────────────────────┐
│         Kernel 层 (Linux)               │
│   cpufreq / suspend / wakelocks / regulator │
└─────────────────────────────────────────┘
```

### 1.2 结论

| 层次 | 组件 | 职责 |
|------|------|------|
| Framework | `PowerManagerService` | 策略决策（何时请求性能/休眠） |
| **HAL** | **`PowerHal`** | **将策略翻译为内核操作** |
| Kernel | cpufreq / regulator / suspend | 实际硬件控制 |

**PowerHal 本质是 Framework 和 Kernel 之间的"翻译层"**，负责 CPU 频率、屏幕电源、WakeLock 等底层电源管理。

---

## 2. PowerHal 实现的业务

| 业务功能 | 说明 |
|---------|------|
| **WakeLock 管理** | 防止 CPU 休眠、屏幕常亮 |
| **CPUFreq 调控** | 请求 CPU 频率档位（performance / powersave / sched） |
| **Display Power** | 屏幕亮灭、亮度等级控制 |
| **Suspend/Resume** | 系统 suspend（深度休眠）和唤醒流程 |
| **Power Hint** | 来自 `PowerHintManager` 的性能提示（touch、audio、camera 等） |
| **一组 `power_hint()`** | AOSP 12+ 引入的新型交互接口 |

### 2.1 关键接口一览

```cpp
// IPower.hal 核心接口
interface IPower {
    powerHint(power_hint_t hint, int32_t data);
    setInteractive(bool enable);
    setDisplayLowPower(bool enable);
    suspend(int64_t timeoutNs);
    resume();
};
```

### 2.2 常见 power_hint 类型

| Hint 类型 | 触发场景 |
|-----------|---------|
| `POWER_HINT_INTERACTION` | 触摸/滑动 |
| `POWER_HINT_VIDEO_ENCODE` | 视频编码 |
| `POWER_HINT_VIDEO_DECODE` | 视频解码 |
| `POWER_HINT_LOW_POWER` | 低功耗模式 |

### 2.3 代码路径

```
# AOSP HAL 接口定义
hardware/interfaces/power/1.0/IPower.hal
hardware/interfaces/power/1.1/
hardware/interfaces/power/1.2/  (Android 13+)

# Framework 调用方
frameworks/base/services/core/java/com/android/server/power/
frameworks/base/core/java/android/os/PowerManager.java
frameworks/base/core/java/android/os/PowerHintManager.java

# 厂商实现（示例）
vendor/qcom/opensource/power-hal/
vendor/mediatek/mtkpowerhal/
```

---

## 3. PowerKey 维护层级分析

### 3.1 总体架构

```
┌──────────────────────────────────────────────┐
│           Linux Kernel 层                    │
│  Keypad/GPIO Driver → Input Subsystem        │
│  (产生 KEY_POWER 输入事件)                   │
└────────────────────┬─────────────────────────┘
                     │ input_event (EV_KEY, KEY_POWER)
                     ▼
┌──────────────────────────────────────────────┐
│           Framework 层 (Native)               │
│  InputReader → InputDispatcher → WindowManager│
│  (InputFlinger 负责事件读取和分发)           │
└────────────────────┬─────────────────────────┘
                     │ ACTION_POWER_KEY_OFF / _ON
                     ▼
┌──────────────────────────────────────────────┐
│           Framework 层 (Java)                 │
│  PhoneWindowManager (拦截处理)                │
│  PowerManagerService (协调电源状态)           │
│  PowerHal / IPower (下发硬件指令)            │
└──────────────────────────────────────────────┘
```

### 3.2 各层职责

| 层级 | 组件 | 职责 |
|------|------|------|
| **Kernel** | `keypad driver` / `gpio-keys` | 检测物理按键，产生 `KEY_POWER` 事件 |
| **Native Framework** | `InputReader` / `InputDispatcher` | 读取原始 input_event，过滤后分发给 WindowManager |
| **Java Framework** | `PhoneWindowManager` | **拦截 power key 事件，决定如何响应**（亮屏/关机/截图） |
| **Java Framework** | `PowerManagerService` | 管理 WakeLock、屏幕状态，调用 PowerHal |
| **HAL** | `PowerHal` | 接收 PowerManagerService 指令，操作 cpufreq / regulator |

### 3.3 关键路径

#### ① Kernel 层

```
drivers/input/keyboard/gpio-keys.c
drivers/input/keyboard/qpnp-power-key.c  (Qualcomm)
    ↓ 产生
input_event(EV_KEY, KEY_POWER, 0/1)  // 0=release, 1=press
```

#### ② Native Input 层

```
EventHub::getEvents()     // 读取 /dev/input/eventX
InputReader::loopOnce()   // 解析事件类型
InputDispatcher::notifyKey()  // 分发给 window
```

#### ③ PhoneWindowManager（核心拦截层）

```
PhoneWindowManager.interceptKeyBeforeDispatching()
    ├── KEY_POWER + FLAG_WOKE → goToSleep() 或 wakeUp()
    ├── 组合键检测 → POWER+VOL_UP = 截图
    ├── 长按 → 显示关机对话框 / 进入 Recovery
    └── 短按 → 亮屏/灭屏
```

### 3.4 完整流程图

```
用户按下 Power 键
    ↓
Kernel 驱动检测 GPIO 状态变化
    ↓
生成 input_event(KEY_POWER, 1)  // press
    ↓
InputReader 读取事件 → InputDispatcher
    ↓
PhoneWindowManager.interceptKeyBeforeDispatching()
    ├── 检测按键类型和 flags
    ├── 判断是 wake / sleep / screenshot / power off dialog
    └── 调用 PowerManagerService
            ↓
        PowerManagerService.goToSleep() / wakeUp()
            ↓
        PowerHal.suspend() / setInteractive(true)
                ↓
            Kernel cpufreq / suspend
```

---

## 4. 总结

| 问题 | 答案 |
|------|------|
| PowerHal属于哪层 | **HAL 层**（硬件抽象层），不属于 Framework |
| PowerHal 实现哪些业务 | WakeLock、CPUFreq、Display Power、Suspend/Resume、Power Hint |
| PowerKey 在哪层维护 | **PhoneWindowManager**（Framework Java 层） |
| Kernel 负责什么 | 物理检测 + input event 产生 |
| PowerManagerService 负责什么 | 电源状态管理 + 调用 PowerHal |
| PowerHal 负责什么 | 最终硬件操作（休眠/唤醒/背光） |

**一句话总结**: PowerKey 的"业务逻辑"在 **PhoneWindowManager**拦截处理后决定调用 PowerManagerService 执行亮屏/灭屏/关机等动作，而真正的硬件控制则下传到 **PowerHal → Kernel**。

---

## 5. 参考资料

- AOSP `hardware/interfaces/power/`
- AOSP `frameworks/base/services/core/java/com/android/server/power/`
- AOSP `frameworks/base/core/java/android/os/PowerManager.java`
- Qualcomm `vendor/qcom/opensource/power-hal/`
