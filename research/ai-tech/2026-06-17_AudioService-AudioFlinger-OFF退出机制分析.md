# AudioService 与 AudioFlinger OFF 退出机制分析

> 分析日期：2026-06-17  
> 分类：ai-tech  
> 标签：Android 框架 | 音频系统 | 关机流程

---

## 1. 概述

本文梳理 Android 音频系统中 `AudioService` 和 `AudioFlinger` 在系统关机（OFF）时的业务退出机制和锁释放过程。两者是 Android 音频架构的核心组件：

- **AudioService**：运行在 `system_server` 进程，负责音频策略管理、音频焦点、音量控制等上层服务
- **AudioFlinger**：运行在 `media` 进程，负责音频混音、音频 Hardware 接口抽象、播放/录音线程管理

---

## 2. 系统关机触发链路

### 2.1 整体调用链

```
PowerManager.shutdown()
  │
  ▼
ActivityManagerService.shutdown()
  │
  ├─→ 发送广播: Intent.ACTION_SHUTDOWN
  │
  ├─→ AudioService.shutdown()
  │
  ├─→ AudioPolicyService.shutdown()
  │
  └─→ 其他系统服务 shutdown()
```

### 2.2 关机入口点

```java
// frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java
public void shutdown(int timeout) {
    // 发送 ACTION_SHUTDOWN 广播
    final Intent intent = new Intent(Intent.ACTION_SHUTDOWN);
    intent.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
    broadcastIntentLocked(null, null, intent, null, null, 0, null, null,
            android.Manifest.permission.SHUTDOWN, false, false, MY_PID, Process.SYSTEM_UID);
    
    // 调用各服务 shutdown()
    mSystemServiceManager.shutdown();
}
```

---

## 3. AudioService 退出机制

**源码路径**: `frameworks/base/services/audio/java/com/android/server/AudioService.java`

### 3.1 类结构

```java
public class AudioService extends Binder implements IBinder {
    
    // IBinder 服务
    private final IBinder mBinder = new Binder();
    
    // 核心组件
    private AudioPolicyInterface mAudioPolicy;      // 音频策略接口
    private MediaFocusControl mMediaFocusControl;   // 音频焦点控制
    private SoundPool mSoundPool;                    // 音效池
    
    // 锁
    private final Object mSettingsLock = new Object();
    private final Object mAudioPolicyLock = new Object();
}
```

### 3.2 shutdown() 流程

```java
public void shutdown() {
    
    // ========== 第一阶段: 停止音频焦点 ==========
    if (mMediaFocusControl != null) {
        mMediaFocusControl.abandonAudioFocus(null);
        mMediaFocusControl = null;
    }
    
    // ========== 第二阶段: 关闭录音 ==========
    // 关闭所有 AudioRecord
    closeRecording(-1);  // -1 表示关闭所有
    
    // ========== 第三阶段: 关闭音频策略 ==========
    synchronized (mAudioPolicyLock) {
        if (mAudioPolicy != null) {
            mAudioPolicy.shutdown();
            mAudioPolicy = null;
        }
    }
    
    // ========== 第四阶段: 关闭 SoundPool ==========
    if (mSoundPool != null) {
        mSoundPool.release();
        mSoundPool = null;
    }
    
    // ========== 第五阶段: 停止音频播放 ==========
    synchronized (mSettingsLock) {
        // 停止所有正在播放的 AudioTrack
        stopAllOutputs();
    }
    
    // ========== 第六阶段: 清理设备缓存 ==========
    if (mAudioDeviceCache != null) {
        mAudioDeviceCache.clear();
    }
    
    // ========== 第七阶段: 注销回调 ==========
    mAudioCallback = null;
}
```

### 3.3 关键资源释放点

| 资源 | 方法 | 说明 |
|------|------|------|
| AudioFocus | `abandonAudioFocus()` | 放弃所有音频焦点请求 |
| AudioRecord | `closeRecording()` | 关闭所有录音会话 |
| AudioPolicy | `mAudioPolicy.shutdown()` | 关闭音频策略引擎 |
| SoundPool | `mSoundPool.release()` | 释放音效池 |
| AudioDeviceCache | `mAudioDeviceCache.clear()` | 清空设备缓存 |

---

## 4. AudioFlinger 退出机制

**源码路径**: `frameworks/av/services/audioflinger/AudioFlinger.h/cpp`

### 4.1 类结构

```cpp
class AudioFlinger : public Thread, public IBinder {
    
    // 线程管理
    DefaultKeyedVector< audio_io_handle_t, sp<PlaybackThread> > mPlaybackThreads;
    DefaultKeyedVector< audio_io_handle_t, sp<RecordThread> > mRecordThreads;
    
    // 锁
    Mutex mLock;
    Condition mWaitWorkCV;
    
    // 引用计数
    int mRefCount;
};
```

### 4.2 引用计数退出 (onLastRef)

```cpp
void AudioFlinger::onLastRef() {
    // 当引用计数归零时自动调用
    shutdown();
}

void AudioFlinger::shutdown() {
    
    // ========== 第一阶段: 停止播放线程 ==========
    for (size_t i = 0; i < mPlaybackThreads.size(); i++) {
        mPlaybackThreads.valueAt(i)->requestExit();
    }
    
    // ========== 第二阶段: 停止录音线程 ==========
    for (size_t i = 0; i < mRecordThreads.size(); i++) {
        mRecordThreads.valueAt(i)->requestExit();
    }
    
    // ========== 第三阶段: 等待线程退出 ==========
    // 等待所有线程安全退出
    mWaitWorkCV.broadcast();
    
    // ========== 第四阶段: 释放混音器 ==========
    for (size_t i = 0; i < mPlaybackThreads.size(); i++) {
        mPlaybackThreads.valueAt(i).clear();
    }
    mPlaybackThreads.clear();
    
    // ========== 第五阶段: 释放录音线程 ==========
    for (size_t i = 0; i < mRecordThreads.size(); i++) {
        mRecordThreads.valueAt(i).clear();
    }
    mRecordThreads.clear();
    
    // ========== 第六阶段: 关闭硬件抽象层 ==========
    if (mHardware != null) {
        mHardware->closeOutput(mPrimaryOutput);
        mHardware->closeInput(mPrimaryInput);
        mHardware = NULL;
    }
}
```

### 4.3 PlaybackThread 退出

```cpp
void AudioFlinger::PlaybackThread::requestExit() {
    mStopRequested = true;
    
    // 中断所有播放中的 Track
    for (size_t i = 0; i < mTracks.size(); i++) {
        sp<Track> track = mTracks[i];
        track->mState = Track::STOPPING;
        track->mRequested = true;  // 请求停止
    }
    
    // 唤醒等待中的线程
    mWaitWorkCV.broadcast();
}

void AudioFlinger::PlaybackThread::threadLoop() {
    while (!mStopRequested) {
        // 混音处理
        process_l();
        
        // 检查停止请求
        if (mStopRequested) break;
        
        // 写入硬件缓冲区
        writeToHardware();
    }
    
    // ========== 线程退出清理 ==========
    // 清空所有 Track
    mTracks.clear();
    
    // 释放混音器资源
    deleteMixer();
}
```

### 4.4 RecordThread 退出

```cpp
void AudioFlinger::RecordThread::requestExit() {
    mStopRequested = true;
    
    // 中断所有录音中的 RecordTrack
    for (size_t i = 0; i < mRecordTracks.size(); i++) {
        mRecordTracks[i]->mState = RecordTrack::STOPPING;
    }
    
    mWaitWorkCV.broadcast();
}
```

---

## 5. 锁释放详细过程

### 5.1 锁层次结构

```
┌─────────────────────────────────────────────────────────────┐
│                    AudioService (system_server)              │
├─────────────────────────────────────────────────────────────┤
│  mAudioPolicyLock ─────────────────────────┐                 │
│  mSettingsLock ────────────────────────────┤                 │
│  mMediaFocusControl ────────────────────────┤                 │
└──────────────────────────────────────────────┼─────────────────┘
                                               │
                    ┌──────────────────────────┘
                    │ IPC 调用
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                    AudioFlinger (media)                      │
├─────────────────────────────────────────────────────────────┤
│  mLock ──────────────────────────────────────────────────┐   │
│  mWaitWorkCV ─────────────────────────────────────────────┤   │
│  PlaybackThread 锁 ──────────────────────────────────────┤   │
│  RecordThread 锁 ────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 AudioService 侧锁释放

#### 5.2.1 mAudioPolicyLock 释放

```java
public void shutdown() {
    synchronized (mAudioPolicyLock) {
        if (mAudioPolicy != null) {
            mAudioPolicy.shutdown();  // 触发 AudioPolicyService 退出
            mAudioPolicy = null;
        }
    }  // ← mAudioPolicyLock 在此自动释放
}
```

#### 5.2.2 mSettingsLock 释放

```java
public void shutdown() {
    synchronized (mSettingsLock) {
        stopAllOutputs();  // 停止所有音频输出
        
        // 清空输出设备列表
        mOutputs.clear();
        mAudioDeviceCache.clear();
    }  // ← mSettingsLock 在此自动释放
}
```

### 5.3 AudioFlinger 侧锁释放

#### 5.3.1 onLastRef 触发释放

```cpp
void AudioFlinger::onLastRef() {
    Mutex::Autolock _l(mLock);  // 获取主锁
    
    shutdown();  // 在锁保护下执行退出
    
}  // ← onLastRef 结束时 mLock 自动释放
```

#### 5.3.2 PlaybackThread 锁释放

```cpp
void AudioFlinger::PlaybackThread::requestExit() {
    Mutex::Autolock _l(mLock);  // 获取线程锁
    
    mStopRequested = true;
    mWaitWorkCV.broadcast();  // 唤醒等待中的线程
    
}  // ← requestExit 结束时线程锁自动释放
```

#### 5.3.3 线程等待与唤醒

```cpp
void AudioFlinger::PlaybackThread::threadLoop() {
    while (!mStopRequested) {
        // 在等待时释放锁，让 requestExit 能够获取锁
        Mutex::Autolock _l(mLock);
        
        // 检查是否需要停止
        if (mStopRequested) break;
        
        // 等待工作信号（此时会释放 mLock）
        mWaitWorkCV.wait(mLock);
        
        // 被唤醒后重新获取 mLock
    }
    
    // 线程退出，清理 Track
    mTracks.clear();
}  // ← 线程结束时所有局部锁自动释放
```

### 5.4 完整锁释放时序

```
[系统关机]
    │
    ▼
┌──────────────────────────────────────────────────────────────────┐
│ AudioService.shutdown()                                           │
│                                                                   │
│  1. abandonAudioFocus()                                          │
│  2. closeRecording() → 释放 mRecordClient 锁                    │
│  3. mAudioPolicy.shutdown()                                       │
│     │                                                             │
│     ├─→ AudioPolicyService.shutdown()                            │
│     │      │                                                      │
│     │      ▼                                                      │
│     │   AudioFlinger.onLastRef() ──→ mLock 获取/释放             │
│     │                                                             │
│  4. mSoundPool.release()                                          │
│  5. stopAllOutputs() ────────────→ mSettingsLock 释放             │
│                                                                   │
│  ┌─ mAudioPolicyLock 释放 ─┐                                      │
│  └─────────────────────────┘                                      │
└──────────────────────────────────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────────────────────────────────┐
│ AudioFlinger.shutdown()                                            │
│                                                                   │
│  1. mPlaybackThreads[i]->requestExit()                           │
│     │  ├─→ mStopRequested = true                                 │
│     │  └─→ mWaitWorkCV.broadcast()  ──→ 唤醒 threadLoop         │
│     │                                                             │
│  2. mRecordThreads[i]->requestExit()                             │
│     │                                                             │
│  3. mWaitWorkCV.broadcast()  ──→ 唤醒所有等待中的线程             │
│                                                                   │
│  4. 线程退出时自动释放:                                            │
│     ├─ PlaybackThread.mLock                                       │
│     ├─ RecordThread.mLock                                         │
│     └─ AudioFlinger.mLock                                         │
└──────────────────────────────────────────────────────────────────┘
```

---

## 6. 关键注意点

### 6.1 引用计数管理

- AudioFlinger 使用 `sp<>` (Strong Pointer) 智能指针管理引用计数
- `onLastRef()` 当引用计数归零时自动调用
- AudioService 与 AudioFlinger 通过 `Binder IPC` 连接，引用计数跨进程

### 6.2 线程安全退出

- `requestExit()` 使用 `mWaitWorkCV.broadcast()` 确保所有等待线程被唤醒
- PlaybackThread/RecordThread 在 `threadLoop()` 中正确处理停止请求
- 线程退出前清空所有 Track/RecordTrack 资源

### 6.3 资源释放顺序

```
AudioService                    AudioFlinger
    │                                │
    ├─ abandonAudioFocus              │
    ├─ closeRecording()               │
    ├─ AudioPolicy.shutdown() ────► │ onLastRef()
    │                                ├─ PlaybackThread.requestExit()
    ├─ SoundPool.release()           ├─ RecordThread.requestExit()
    ├─ stopAllOutputs()              ├─ 等待线程退出
    └─ 清空缓存                       └─ 释放硬件抽象层
```

---

## 7. 总结

| 阶段 | AudioService | AudioFlinger |
|------|--------------|--------------|
| **触发** | `shutdown()` 系统调用 | `onLastRef()` 引用归零 |
| **停止** | 停止焦点/录音/播放 | `requestExit()` 停止线程 |
| **释放策略** | `AudioPolicy.shutdown()` | `shutdown()` 清空线程 |
| **释放锁** | `mAudioPolicyLock`, `mSettingsLock` | `mLock`, `mWaitWorkCV` |
| **清理** | 清空缓存/回调 | 释放硬件抽象层 |

---

## 8. 参考

- `frameworks/base/services/audio/java/com/android/server/AudioService.java`
- `frameworks/av/services/audioflinger/AudioFlinger.h`
- `frameworks/av/services/audioflinger/AudioFlinger.cpp`
- `frameworks/av/services/audiopolicy/AudioPolicyService.cpp`
- `frameworks/base/core/java/android/media/AudioManager.java`
