# Android ShutdownThread 机制解析

> **分类**: Android 框架 / 系统服务
> **更新**: 2026-06-10  
> **标签**: Android, ActivityManagerService, ShutdownThread, PowerManager

---

## 1. 概述

`ShutdownThread` 是 Android 系统服务 `ActivityManagerService` (AMS) 内部使用的核心关机流程控制类，负责执行设备关机/重启的完整流程。它运行在 `system_server` 进程中，协调各系统服务有序关闭，最终触发 kernel 电源管理完成关机。

---

## 2. 核心工作流程

```
AMS.shutdown() / AMS.reboot()
    ↓
ActivityManagerService 调用 ShutdownThread
    ↓
ShutdownThread.run() 主线程执行
    ↓
1. 关闭 Activity 栈
2. 发送广播 (ACTION_SHUTDOWN)
3. 关闭应用进程
4. 调用 native 方法执行实际关机
```

---

## 3. 关键源码路径

| 文件 | 路径 |
|------|------|
| ShutdownThread | `frameworks/base/core/java/com/android/internal/app/ShutdownThread.java` |
| ActivityManagerService | `frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java` |
| PowerManager | `frameworks/base/core/java/android/os/PowerManager.java` |
| Native 层 | `frameworks/base/core/jni/android_os_power.cpp` |

---

## 4. 主要方法

| 方法 | 作用 |
|------|------|
| `shutdown()` | 完整关机流程 |
| `reboot()` | 重启（可带参数进入 recovery/fastboot） |
| `run()` | 主执行线程 |
| `beginShutdownSequence()` | 开始关机序列 |
| `finishShutdownSequence()` | 完成关机序列 |
| `setConfirmDialog()` | 设置是否显示关机确认对话框 |

---

## 5. 关机序列细节

### 5.1 入口方法

```java
// ShutdownThread.java
public static void shutdown(Context context, boolean confirm) {
    // confirm=true 显示确认对话框
    ShutdownThread.setConfirmDialog(confirm, null);
    ShutdownThread.beginShutdownSequence(context);
}
```

### 5.2 完整流程 (run 方法)

```java
public void run() {
    // Step 1: 显示关机动画/对话框
    ProgressDialog dialog = createDialog();
    dialog.show();
    
    // Step 2: 广播关机事件（有序广播，可被拦截）
    Intent broadcast = new Intent(Intent.ACTION_SHUTDOWN);
    context.sendOrderedBroadcast(
        broadcast, 
        android.Manifest.permission.SHUTDOWN
    );
    
    // Step 3: 关闭 ActivityManager
    ActivityManagerService am = context.getSystemService(ActivityManager.class);
    am.onShutdown();
    
    // Step 4: 关闭系统服务（按优先级）
    // 关闭顺序示例：
    // - BatteryService (拔掉电池警告)
    // - VibratorService (振动服务)
    // - TelephonyRegistry (通话服务)
    // - SmsService (短信服务)
    // - ContentService (内容服务)
    // - ...
    
    // Step 5: 同步文件系统
    sync();
    
    // Step 6: 调用 native 方法执行实际关机
    nativeShutdown();  // -> android_os_power.cpp -> kernel poweroff
}
```

---

## 6. 与 PowerManager 的关系

```
PowerManager.shutdown() 
    ↓
调用 ShutdownThread.shutdown()
    ↓
而不是直接操作 hardware/power
```

`ShutdownThread` 是 AMS 封装的高层关机接口，内部最终调用 `PowerManager` 或直接 JNI 到 `android_os_power.cpp`。

```java
// PowerManager.java
public void shutdown() {
    shutdown(null, false);
}

public void shutdown(String reason, boolean confirm) {
    // 最终调用 ShutdownThread
    ShutdownThread.shutdown(mContext, confirm);
}
```

---

## 7. 有序关闭的服务优先级

关机时系统服务按以下顺序关闭（部分）：

| 顺序 | 服务 | 说明 |
|------|------|------|
| 1 | ActivityManagerService | 关闭所有 Activity 栈 |
| 2 | BatteryService | 电池状态服务 |
| 3 | VibratorService | 振动服务 |
| 4 | TelephonyRegistry | 电话服务 |
| 5 | SmsService | 短信服务 |
| 6 | ContentService | 内容服务 |
| 7 | MountService | 挂载服务 |
| 8 | NetworkManagementService | 网络管理 |
| 9 | NotificationManagerService | 通知管理 |

---

## 8. ShutdownThread vs Fast Shutdown

| 特性 | ShutdownThread | Fast Shutdown |
|------|---------------|--------------|
| 广播 | 发送 ACTION_SHUTDOWN | 不发送 |
| 服务关闭 | 全部按序关闭 | 跳过部分服务 |
| 文件 sync | 执行 | 跳过 |
| 速度 | 慢（完整） | 快（应急） |
| 使用场景 | 正常关机 | 强制关机/应急 |

---

## 9. 拦截关机事件

### 9.1 注册广播接收器

```kotlin
class ShutdownReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_SHUTDOWN) {
            // 执行清理操作
            saveData()
            closeConnections()
            
            // 可选择 abort取消关机（需 BROADCAST_SHUTDOWN 权限）
            // abortBroadcast()
        }
    }
}
```

### 9.2 AndroidManifest.xml 注册

```xml
<receiver android:name=".ShutdownReceiver">
    <intent-filter>
        <action android:name="android.intent.action.ACTION_SHUTDOWN" />
    </intent-filter>
</receiver>
```

### 9.3 权限说明

```xml
<!-- 需要此权限才能接收 ACTION_SHUTDOWN -->
<uses-permission android:name="android.permission.BROADCAST_SHUTDOWN" />
```

> ⚠️ 注意：`ABORT_SHUTDOWN` 权限仅授予系统应用

---

## 10. 重启流程 (Reboot)

```java
public static void reboot(Context context, String reason, boolean confirm) {
    // reason 可选值:
    // - "recovery"  进入 recovery模式
    // - "bootloader" 进入 fastboot 模式
    // - "" 正常重启
    setConfirmDialog(confirm, null);
    beginShutdownSequence(context);
}
```

---

## 11. 关键代码片段

### 11.1 beginShutdownSequence

```java
private static void beginShutdownSequence(Context context) {
    // 创建并启动 ShutdownThread
    Thread thr = new Thread(null, new ShutdownThread(),
                           "ShutdownThread", STACK_SIZE);
    thr.start();
}
```

### 11.2 系统属性控制

```java
// 通过系统属性控制关机行为
// adb shell setprop sys.shutdown.requested true
boolean shutdownRequested = SystemProperties.getBoolean(
    "sys.shutdown.requested", false
);
```

---

## 12. 常见问题

### Q1: 按电源键关机走的是 ShutdownThread 吗？

是的。长按电源键 → 系统弹出关机对话框 → 用户确认后 → 调用 `ShutdownThread.shutdown()`

### Q2: ShutdownThread 在哪个进程运行？

运行在 `system_server` 进程，不是独立进程

### Q3: 如何阻止关机？

注册 `BroadcastReceiver` 监听 `ACTION_SHUTDOWN`，调用 `abortBroadcast()` 可取消关机（需要系统权限）

### Q4: 为什么关机前要 sync 文件系统？

确保所有挂起的写入操作完成，防止数据损坏或文件系统不一致

### Q5: Fast Shutdown 和正常关机的区别？

Fast Shutdown 跳过服务关闭和 sync，适用于强制关机场景，可能导致数据丢失或文件系统损坏

---

## 13. 总结

```
ShutdownThread = Android 关机流程的编排器
  ├── 协调 AMS、系统服务、Native 层
  ├── 保证各服务按优先级有序关闭
  ├── 确保文件系统 sync
  └── 最终触发 kernel 电源管理
```

### 核心职责

1. **广播分发** - 通知所有应用和系统服务即将关机
2. **服务协调** - 按依赖关系有序关闭系统服务
3. **状态保存** - 确保关键状态写入持久化存储
4. **文件同步** - sync() 保证文件系统一致性
5. **硬件交互** - JNI 调用 native 层执行实际电源操作

---

## 参考资料

- [Android Source Code - ShutdownThread.java](https://cs.android.com/search?q=ShutdownThread.java)
- [Android Source Code - ActivityManagerService.java](https://cs.android.com/search?q=ActivityManagerService.java)
- [Android Developer - PowerManager](https://developer.android.com/reference/android/os/PowerManager)
- [Android 系统关机流程分析 - CSDN](https://blog.csdn.net/android_system_china)

---

*文档更新时间: 2026-06-10*