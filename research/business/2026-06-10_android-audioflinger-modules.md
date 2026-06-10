# Android AudioFlinger 音频控制模块解析

> **分类**: Android 框架 / 多媒体
> **更新**: 2026-06-10
> **标签**: Android, AudioFlinger, Audio HAL, Mixer, PlaybackThread, AudioPolicy

---

## 1. 概述

AudioFlinger 是 Android 音频系统的核心服务，运行在 `system_server` 进程中，负责音频的播放、录制、混音、音效处理和音频路由策略管理。它是用户空间音频管理的枢纽，连接应用层与内核音频驱动。

---

## 2. 整体架构

```
┌─────────────────────────────────────────────────────┐
│                   应用层 (Apps)                      │
│         AudioTrack / AudioRecord / MediaPlayer      │
└───────────────────────┬─────────────────────────────┘
                        │ Binder IPC
┌───────────────────────▼─────────────────────────────┐
│              AudioFlinger (核心)                     │
│   ─────────────────────────────────────────────────│
│   ThreadLoop │ Mixer │ Track │ Effect │ Policy      │
└───────────────────────┬─────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ↓               ↓               ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ AudioHAL    │ │ Audio HAL    │ │ Audio HAL    │
│ (Legacy)    │ │ (AIDL/HIDL) │ │ (Direct)     │
└──────────────┘ └──────────────┘ └──────────────┘
        │               │               │
        ↓               ↓               ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Kernel ALSA │ │  TinyALSA    │ │  AAudio/     │
│  Driver     │ │  Driver      │ │  Oboe        │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## 3. 核心模块

### 3.1 PlaybackThread (播放线程)

```cpp
// 负责音频输出播放
class PlaybackThread : public ThreadBase {
    // Mixer 混合多个 Track
    MixerThread* mMixerThread;
    
    // 输出 HAL 接口
    AudioStreamOut* mOutput;
    
    // 混音过程
    void threadLoop() {
        // 1. 从各 Track 获取音频数据
        // 2. Mix 多轨音频
        // 3. 写入 HAL 输出
    }
}
```

**PlaybackThread 类型：**

| 类型 | 说明 |
|------|------|
| `MixerThread` | 混音线程，混合多个播放轨 |
| `DirectOutputThread` | 直出线程，单轨直接输出 |
| `OffloadThread` | 硬解线程，硬件解码直通 |
| `DuplicatingThread` | 复制线程，多输出（蓝牙+Speaker）|

---

### 3.2 RecordThread (录制线程)

```cpp
// 负责音频输入录制
class RecordThread : public ThreadBase {
    // 输入 HAL 接口
    AudioStreamIn* mInput;
    
    // 录音 Track
    RecordTrack* mRecordTrack;
    
    void threadLoop() {
        // 1. 从 HAL 读取音频数据
        // 2. 分发给各 RecordTrack
    }
}
```

---

### 3.3 Mixer (混音器)

```cpp
// 混音核心
class Mixer {
    // 32轨混音能力
    static constexpr int MAX_SLOTS = 32;
    
    // 混音参数
    VolumeCurve mVolumeCurve;  // 音量曲线
    Equalizer mEqualizer;       // EQ均衡器
    BassBoost mBassBoost;       // 低音增强
    Virtualizer mVirtualizer;   // 虚拟环绕声
    
    // 执行混音
    void processFrames() {
        for (int i = 0; i < MAX_SLOTS; i++) {
            if (mTracks[i].isActive()) {
                mixOneTrack(mTracks[i]);
            }
        }
    }
}
```

**混音处理流程：**

```
输入 Track 1 ─┐
输入 Track 2 ─┤
输入 Track 3 ─┼──► Volume Apply ─► EQ ─► BassBoost ─► Virtualizer ─► Output
     ...      │     (音量)      (均衡)   (低音)       (环绕声)
输入 Track N ─┘
```

---

### 3.4 Track (音轨)

```cpp
// 播放音轨
class Track {
    audio_flags_t mFlags;           // AUDIO_FLAG_NONE / FAST / COMPRESS_OFFLOAD
    audio_format_t mFormat;         // PCM / AC3 / DTS / MP3 / AAC
    audio_channel_mask_t mChannelMask;
    uint32_t mSampleRate;
    BufferProvider* mBufferProvider; // 数据源
    VolumeController mVolumeCtrl;    // 音量控制
    sp<IMemory> mCblk;             // 共享内存控制块
}
```

**Track 状态机：**

```
IDLE ──► STOPPED ──► FLUSHED ──► IDLE
         │                              ↑
         └──────► RESUMING ◄───── STARTING
```

---

### 3.5 AudioPolicy (音频策略)

```cpp
// 音频路由和策略管理
class AudioPolicyManager {
    // 设备连接状态
    DeviceVector mAvailableOutputDevices;
    DeviceVector mAvailableInputDevices;
    
    // 策略规则
    routing_strategy mStrategy;  // STRATEGY_MEDIA / STRATEGY_PHONE / STRATEGY_DTMF
    
    // 输出设备选择
    audio_io_handle_t getOutputForDevice(
        audio_devices_t device,
        audio_stream_type_t stream
    ) {
        // 1. 检查设备是否可用
        // 2. 根据策略选择输出
        // 3. 打开/复用 HAL stream
    }
}
```

**策略类型：**

| 策略 | 场景 | 输出设备 |
|------|------|----------|
| `STRATEGY_MEDIA` | 音乐/视频 | Speaker / Headphone / BT A2DP |
| `STRATEGY_PHONE` | 电话 | Earpiece / Speaker / BT SCO |
| `STRATEGY_DTMF` | DTMF | 听筒 |
| `STRATEGY_SONIFICATION` | 触摸音效 | Speaker |
| `STRATEGY_ENFORCED_AUDIBLE` | 强制提示音 | Speaker (即使静音) |

---

### 3.6 Effects (音效)

```cpp
// 音效模块
class EffectModule {
    effect_handle_t mHandle;    // 音效句柄
    effect_descriptor_t mDesc;  // 音效描述
}

// 内置音效
enum effects_type {
    EFFECT_BASS_BOOST,      // 低音增强
    EFFECT_VIRTUALIZER,     // 虚拟环绕声
    EFFECT_EQUALIZER,       // 均衡器
    EFFECT_REVERB,          // 混响
    EFFECT_DYNAMICS_PROCESSING, // 动态处理(压缩/限制)
};
```

**音效处理位置：**

```
┌─────────────────────────────────────────────────────┐
│                   PlaybackThread                     │
│                                                      │
│  Track1 ──┐                                          │
│  Track2 ──┼──► Pre-Effects ──► Mixer ──► Post-Effects│
│  Track3 ──┘      (输入处理)           (输出处理)      │
│                                                      │
└─────────────────────────────────────────────────────┘
```

---

## 4. 数据流

### 4.1 播放数据流

```
App (AudioTrack)
    ↓ write()
Binder IPC
    ↓
AudioFlinger::PlaybackThread
    ↓ mix()
Mixer (Volume → EQ → BassBoost → Virtualizer)
    ↓
EffectChain (后处理音效)
    ↓
AudioStreamOut (HAL)
    ↓
ALSA / TinyALSA Driver
    ↓
Codec / DSP
    ↓
Speaker / Headphone
```

### 4.2 录制数据流

```
Microphone
    ↓
ALSA / TinyALSA Driver
    ↓
AudioStreamIn (HAL)
    ↓
AudioFlinger::RecordThread
    ↓
EffectChain (预处理音效 - 降噪/回声消除)
    ↓
App (AudioRecord)
```

---

## 5. 关键 HAL 接口

### 5.1 Audio HAL v3.0+ (AIDL)

```cpp
// Audio HAL AIDL 接口
interface IAudioDevice {
    // 输出
    createOutputStream(...) -> IAudioStreamOut;
    
    // 输入
    createInputStream(...) -> IAudioStreamIn;
    
    // 设备枚举
    getSupportedDevices(...) -> DeviceAddress[];
    
    // 模式
    setMode(audio_mode_t mode) -> audio_mode_t;
    
    // 音量
    setMasterVolume(float volume) -> void;
    setStreamVolume(audio_stream_type_t stream, float volume) -> void;
}
```

### 5.2 AudioStreamOut

```cpp
// 输出流接口
interface IAudioStreamOut {
    // 写入音频数据
    write(in AudioBufferWrapper data) -> int bytesWritten;
    
    // 获取延迟
    getLatency() -> uint32_t latencyMs;
    
    // 状态
    getPresentationPosition() -> AudioTimestamp;
    
    // 参数设置
    setParameters(in String8 keys) -> void;
    getParameters(in String8 keys) -> String8;
}
```

---

## 6. 模块协作关系

```
AudioTrack/AudioRecord
         │
         │  Binder
         ▼
   ┌─────────────┐
   │  ThreadBase │◄──── PlaybackThread / RecordThread
   └──────┬──────┘
          │
    ┌─────┴─────┐
    ▼           ▼
┌────────┐  ┌────────┐
│ Mixer  │  │ Tracks │
└───┬────┘  └───┬────┘
    │           │
    ▼           ▼
┌─────────────┐  ┌─────────────┐
│AudioPolicy  │  │  Effects    │
│(路由策略)   │  │(音效处理)   │
└──────┬──────┘  └──────┬──────┘
       │                │
       ▼                ▼
┌──────────────────────────────────┐
│         Audio HAL                │
│  (AudioStreamOut / AudioStreamIn)│
└──────────────────────────────────┘
```

---

## 7. 音频格式支持

| 格式 | 编码 | 说明 |
|------|------|------|
| `AUDIO_FORMAT_PCM_16_BIT` | PCM | 原始音频，最常见 |
| `AUDIO_FORMAT_PCM_8_BIT` | PCM | 8位音频 |
| `AUDIO_FORMAT_PCM_32_BIT` | PCM | 32位浮点 |
| `AUDIO_FORMAT_AC3` | Dolby Digital | 5.1环绕声 |
| `AUDIO_FORMAT_E_AC3` | Dolby Digital+ | 杜比全景声 |
| `AUDIO_FORMAT_DTS` | DTS | 影院级音频 |
| `AUDIO_FORMAT_MP3` | MP3 | 压缩音频 |
| `AUDIO_FORMAT_AAC_LC` | AAC | 高效压缩 |
| `AUDIO_FORMAT_HE_AAC` | HE-AAC | 高效低码率 |
| `AUDIO_FORMAT_OPUS` | Opus | 免版税编码 |

---

## 8. 音频采样率

| 采样率 | 应用场景 |
|--------|----------|
| 8 kHz | 语音电话 |
| 16 kHz | VoIP / 语音识别 |
| 22.05 kHz | 早期 CD |
| 44.1 kHz | CD 音频标准 |
| 48 kHz | 视频 / 专业音频 |
| 96 kHz | 高分辨率音频 |
| 192 kHz | 母带级音频 |

---

## 9. 关键源码路径

| 文件 | 说明 |
|------|------|
| `frameworks/av/services/audioflinger/` | AudioFlinger 核心 |
| `AudioFlinger.h` | 头文件定义 |
| `PlaybackThread.h` | 播放线程 |
| `RecordThread.h` | 录制线程 |
| `Mixer.h` | 混音器 |
| `AudioPolicyService.h` | 音频策略服务 |
| `frameworks/av/media/audioflinger/` | Audio HAL 接口 |
| `hardware/interfaces/audio/` | Audio HIDL/AIDL |

---

## 10. 常见问题

### Q1: AudioFlinger 和 AudioTrack 的关系？

- `AudioTrack` 是客户端 API，运行在 App 进程
- `AudioFlinger` 是服务端，运行在 `system_server`
- 通过 Binder IPC 通信，`AudioTrack` 实际调用 `AudioFlinger` 的服务

### Q2: 为什么音频会有延迟？

延迟来源：
1. **HAL 缓冲** - Audio HAL 内部缓冲区
2. **App 缓冲** - AudioTrack 缓冲区大小
3. **Mixer 调度** - 混音线程周期
4. **驱动缓冲** - ALSA/TinyALSA 缓冲区

优化方式：使用 `FLAG_FAST` 音轨，减少缓冲

### Q3: 什么是 Fast Audio Path？

```
Fast Path (低延迟):
App → AudioFlinger → Audio HAL → Kernel → Codec → Speaker
                    (跳过 Effects)

Normal Path (完整处理):
App → AudioFlinger → Effects → Audio HAL → Kernel → Codec → Speaker
```

### Q4: 多个应用同时播放音频如何处理？

`MixerThread` 最多支持 **32 轨**同时混音，按策略优先级：
1. `STRATEGY_ENFORCED_AUDIBLE` (系统提示音)
2. `STRATEGY_PHONE` (电话)
3. `STRATEGY_SONIFICATION` (触摸音效)
4. `STRATEGY_MEDIA` (音乐/视频)

---

## 11. 总结

```
AudioFlinger = Android 音频系统的核心枢纽
    ├── PlaybackThread ─── 播放线程管理
    │     ├── Mixer ────── 多轨混音
    │     ├── Track ─────── 单轨控制
    │     └── Effects ───── 音效处理
    ├── RecordThread ──── 录音线程管理
    ├── AudioPolicy ───── 路由策略决策
    └── Audio HAL ──────── 驱动抽象层
```

### 核心职责

1. **混音** - 多轨音频混合输出
2. **路由** - 设备切换和策略决策
3. **音效** - EQ/低音/环绕声处理
4. **格式转换** - 采样率/位深/声道转换
5. **延迟控制** - 平衡延迟和音质
6. **资源管理** - 音轨生命周期管理

---

## 参考资料

- [Android Source - AudioFlinger](https://cs.android.com/search?q=AudioFlinger)
- [Android Source - Audio HAL](https://cs.android.com/search?q=audio+hal)
- [Android Developer - Audio Architecture](https://developer.android.com/guide/topics/media/audio)
- [ALSA Project](https://www.alsa-project.org/)
- [Android Audio Latency](https://source.android.com/docs/audio/audio-latency)

---

*文档更新时间: 2026-06-10*