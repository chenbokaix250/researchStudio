# Android Power 键亮屏机制解析

> **分类**: Android 框架 / 系统服务
> **更新**: 2026-06-10
> **标签**: Android, PowerManager, WakeLock, Display, Input, PowerKey

---

## 1. 概述

Power 键（电源键）是 Android 设备的核心交互入口，短按切换亮灭屏，长按弹出关机菜单。其机制贯穿 Linux Kernel → HAL → Framework 三个层级，涉及 PMIC 中断、Input 驱动、WakeLock、DisplayManager 等多个组件协作。

---

## 2. 整体流程

```
Power 键按下
    ↓
PMIC（电源管理芯片）中断
    ↓
Kernel Input Driver 捕获按键事件
    ↓
WindowManagerService / PowerManagerService 处理
    ↓
Display 驱动打开屏幕
```

---

## 3. 核心路径

### 3.1 Kernel 层：Input 驱动

```c
// kernel/drivers/input/power_key.c
static irqreturn_t power_key_interrupt(int irq, void *dev_id)
{
    // 读取 PMIC 中断状态
    int state = read_pm8894_register(PMIC_PWRKEY_STATUS);
    
    if (state & PWRKEY_PRESSED) {
        // 上报 INPUT 事件
        input_report_key(power_key_input, KEY_POWER, 1);
        input_sync(power_key_input);
    }
    
    if (state & PWRKEY_RELEASED) {
        input_report_key(power_key_input, KEY_POWER, 0);
        input_sync(power_key_input);
    }
    
    return IRQ_HANDLED;
}
```

### 3.2 Framework 层：PowerManagerService 接收

```java
// frameworks/base/services/core/java/com/android/server/power/PowerManagerService.java

private int handlePowerKey(KeyEvent event) {
    if (event.getAction() == KeyEvent.ACTION_DOWN) {
        // 短按：亮屏或灭屏
        // 长按：弹出关机对话框
        if (isScreenOn()) {
            goToSleepNoUpdate(SystemClock.uptimeMillis(),
                PowerManager.GO_TO_SLEEP_REASON_POWER_BUTTON);
        } else {
            wakeUpNoUpdate(SystemClock.uptimeMillis());
        }
    }
    return 0;
}
```

### 3.3 亮屏核心：wakeUpNoUpdate

```java
private void wakeUpNoUpdate(long eventTime) {
    synchronized (mLock) {
        // 1. 更新电源状态
        mWakeLock = 1;  // 持有 WakeLock
        
        // 2. 通知 Display 打开
        mDisplayManagerService.displayStateChanged(
            Display.STATE_ON
        );
        
        // 3. 解锁屏幕
        mWindowManagerConditionLock.release();
        
        // 4. 发送亮屏广播
        Intent intent = new Intent(Intent.ACTION_SCREEN_ON);
        mContext.sendBroadcast(intent);
    }
}
```

---

## 4. 关键组件协作

```
┌─────────────────────────────────────────────┐
│              PowerManagerService            │
│  ┌─────────────────────────────────────┐    │
│  │  handlePowerKey()                   │    │
│  │    - 判断短按/长按                    │    │
│  │    - 调用 wakeUp / goToSleep        │    │
│  └─────────────────────────────────────┘    │
└──────────────────┬────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ↓                     ↓
┌───────────────┐    ┌─────────────────────┐
│ DisplayManager│    │  PowerManagerService │
│ Service       │    │  - WakeLock 管理      │
│ - 屏幕状态    │    │  - 亮度调节           │
│ - STATE_ON   │    │  - 用户活动检测        │
└───────────────┘    └─────────────────────┘
        │                     │
        └──────────┬──────────┘
                   ↓
        ┌─────────────────────┐
        │   SurfaceFlinger   │
        │   - 合成帧输出       │
        │   - 屏幕刷新        │
        └─────────────────────┘
```

---

## 5. WakeLock 机制

### 5.1 基本使用

```java
// PowerManager 持有 WakeLock 防止系统休眠
PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
WakeLock wakeLock = pm.newWakeLock(
    PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP,
    "MyTag"
);

wakeLock.acquire();  // 禁止休眠，保持屏幕亮
wakeLock.release();   // 释放后系统可休眠
```

### 5.2 WakeLock 类型

| Flag | 作用 |
|------|------|
| `SCREEN_BRIGHT_WAKE_LOCK` | 保持屏幕亮，亮度最高 |
| `SCREEN_DIM_WAKE_LOCK` | 保持屏幕亮，亮度降低 |
| `PARTIAL_WAKE_LOCK` | 仅保持 CPU 运行，屏幕可灭 |
| `ACQUIRE_CAUSES_WAKEUP` | 获得锁时强制亮屏 |
| `ON_AFTER_RELEASE` | 释放后保持屏幕亮一段时间 |

### 5.3 WakeLock 层级

```
WakeLock Level（从高到低）
    │
    ├── PARTIAL_WAKE_LOCK
    │       └── 仅 CPU 运行
    ├── SCREEN_DIM_WAKE_LOCK
    │       └── CPU + 屏幕 dim
    ├── SCREEN_BRIGHT_WAKE_LOCK
    │       └── CPU + 屏幕亮
    └── FULL_WAKE_LOCK (已废弃)
            └── CPU + 屏幕 + 键盘灯
```

---

## 6. Screen State 流转

```
STATE_OFF
    │
    │  wakeUp()
    ↓
STATE_ON
    │
    │  userInactive() / timeout / sleep button
    ↓
STATE_DOZE  (Always On Display / AOD)
    │
    │  系统暂停（suspend）
    ↓
STATE_DOZE_SUSPEND
    │
    │  用户交互 / 按键
    ↓
STATE_ON
```

---

## 7. 短按 vs 长按

| 按键时长 | 行为 |
|----------|------|
| 短按（< 500ms） | 切换亮/灭屏 |
| 长按（> 500ms） | 弹出关机对话框 |
| 长按（> 8s） | 强制重启（硬件看门狗） |

### 7.1 按键时序检测

```java
// PowerManagerService.java
private void interceptPowerKeyDown(KeyEvent event) {
    if (!mPowerKeyWakeLock.isHeld()) {
        mPowerKeyWakeLock.acquire();  // 开始计时
    }
    
    // 取消长按对话框的延迟
    mHandler.removeMessages(MSG_SHOW_GLOBAL_ACTIONS);
    
    // 延迟发送长按事件
    Message msg = mHandler.obtainMessage(MSG_POWER_KEY_DOWN);
    mHandler.sendMessageDelayed(msg, POWER_KEY_LONG_PRESS_TIMEOUT);
}
```

---

## 8. 关机对话框流程

```
长按 Power 键 (> 500ms)
    ↓
PowerManagerService 收到长按事件
    ↓
显示 GlobalActionsDialog
    ↓
用户选择"关机" → 调用 ShutdownThread.shutdown()
```

```java
// GlobalActionsDialog.java
private void handlePower() {
    // 显示确认对话框（可取消）
    ShutdownThread.shutdown(mContext, true);
}
```

---

## 9. 关键源码路径

| 文件 | 说明 |
|------|------|
| `frameworks/base/services/core/.../PowerManagerService.java` | 电源状态管理，handlePowerKey |
| `frameworks/base/services/core/.../DisplayManagerService.java` | 屏幕状态管理 |
| `frameworks/base/core/.../android/view/WindowManagerGlobal.java` | Window 状态同步 |
| `frameworks/base/core/.../android/os/PowerManager.java` | WakeLock API 定义 |
| `frameworks/base/core/.../android/view/KeyEvent.java` | 按键事件定义 |
| `system/core/.../PowerHalService.cpp` | Power HAL 接口 |
| `hardware/interfaces/power/1.0/` | Power HIDL 接口 |

---

## 10. 亮屏广播

```java
// 广播 Intent
Intent.ACTION_SCREEN_ON      // 屏幕点亮
Intent.ACTION_SCREEN_OFF     // 屏幕熄灭
Intent.ACTION_USER_PRESENT   // 用户解锁完成
Intent.ACTION_POWER_CONNECTED // 电源连接
Intent.ACTION_POWER_DISCONNECTED // 电源断开
```

### 10.1 注册广播接收

```kotlin
class ScreenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> {
                Log.d("Screen", "Screen ON")
            }
            Intent.ACTION_SCREEN_OFF -> {
                Log.d("Screen", "Screen OFF")
            }
            Intent.ACTION_USER_PRESENT -> {
                Log.d("Screen", "User unlocked")
            }
        }
    }
}

// 注册
val filter = IntentFilter().apply {
    addAction(Intent.ACTION_SCREEN_ON)
    addAction(Intent.ACTION_SCREEN_OFF)
    addAction(Intent.ACTION_USER_PRESENT)
}
context.registerReceiver(ScreenReceiver, filter)
```

---

## 11. 相关服务启动顺序

```
init进程 (PID 1)
    ↓
zygote (孵化 Java 世界)
    ↓
system_server (启动系统服务)
    ├── ActivityManagerService
    ├── WindowManagerService
    ├── PowerManagerService     ← 核心
    ├── DisplayManagerService   ← 屏幕控制
    └── SurfaceFlinger          ← 帧合成
```

---

## 12. 常见问题

### Q1: WakeLock 忘记 release 会怎样？

导致设备无法休眠，电池快速消耗。检查：
- 是否在 onDestroy 中 release
- 是否在 try-finally 中 release

### Q2: 亮屏广播和亮屏事件的区别？

| 事件 | 触发时机 |
|------|----------|
| `ACTION_SCREEN_ON` | Display 状态变为 ON |
| `ACTION_USER_PRESENT` | 用户解锁完成 |
| `onScreenTurningOn` | WindowManager 回调 |

### Q3: 为什么有时候按 Power 键不响应？

可能原因：
- 系统正在休眠（SCREEN_BRIGHT_WAKE_LOCK 未释放）
- 系统正在忙（input 队列阻塞）
- kernel panic 或 Watchdog 重置

### Q4: AOD (Always On Display) 如何实现？

利用 `STATE_DOZE` 状态，仅刷新部分像素，保持低功耗显示时钟/通知。

---

## 13. 总结

```
Power 键机制 = 硬件中断 + Input 驱动 + Framework 服务协作
    ├── PMIC 中断 → kernel input subsystem
    ├── Input 事件 → PowerManagerService.handlePowerKey()
    ├── WakeLock 持有 → 防止系统休眠
    ├── Display 状态切换 → SurfaceFlinger 刷新
    └── Broadcast 通知 → 应用层感知
```

### 核心职责

1. **中断捕获** - PMIC 检测 Power 键按下/释放
2. **事件分发** - Input 驱动上报 KEY_POWER 事件
3. **状态决策** - PowerManagerService 判断短按/长按
4. **屏幕控制** - DisplayManager + SurfaceFlinger 控制屏幕
5. **应用通知** - 广播让 App 感知屏幕状态

---

## 参考资料

- [Android Source - PowerManagerService](https://cs.android.com/search?q=PowerManagerService.java)
- [Android Source - DisplayManagerService](https://cs.android.com/search?q=DisplayManagerService.java)
- [Android Developer - PowerManager](https://developer.android.com/reference/android/os/PowerManager)
- [Linux Kernel - Input Subsystem](https://www.kernel.org/doc/html/latest/input/index.html)
- [Android HAL - Power](https://source.android.com/docs/interact/hals/power)

---

*文档更新时间: 2026-06-10*