# Android 车机 VM / Virtualization 架构完整研究报告

**研究主题：Android Automotive / SDV 中的 Virtual Machine、Hypervisor、VirtIO 与跨 VM 架构**

**面向对象：Android / Linux / Automotive 底软工程师**

**目标：建立从 CPU 硬件虚拟化到 AAOS Framework 的完整认知**

**资料时间：2026 年 9 月**

---

# 一、先建立一个最重要的认知

Android 车机里讲的 **VM**，实际上经常有三种完全不同的东西：

| 名称  | 全称                   | 所处层次                   | 作用                         |
| --- | -------------------- | ---------------------- | -------------------------- |
| JVM | Java Virtual Machine | Android Runtime / Java | 执行 Java 字节码                |
| ART | Android Runtime      | Android                | Android App/Framework 运行环境 |
| VM  | Virtual Machine      | OS/Hypervisor          | 运行一个完整 Guest OS            |

你现在研究车机架构时，重点应该是第三种：

> **Virtual Machine = 一台虚拟出来的计算机。**

例如一个 SoC：

```text
                    Automotive SoC
                         │
              ┌──────────┴──────────┐
              │                     │
          Hypervisor / KVM       Hardware
              │
       ┌──────┼────────┐
       │      │        │
      VM1    VM2      VM3
       │      │        │
     AAOS    Linux    ADAS OS
       │
    Android
       │
   CarService
       │
      VHAL
```

也就是说：

> **以前是一颗 SoC 跑一个 OS；现在是一颗 SoC 跑多个 OS。**

这就是 Automotive Virtualization 最核心的思想。

Google 当前的 AAOS 文档明确描述了这种架构：多个 AAOS 实例可以作为 Guest VM，与仪表、ADAS 等其他 Automotive OS 并行运行，并通过 VirtIO 抽象硬件。([Android 开源项目][1])

---

# 二、为什么汽车开始需要 VM？

传统车机大致是：

```text
SoC
 │
 └── Linux Kernel
      │
      └── Android
           │
           ├── App
           ├── Framework
           ├── HAL
           └── Driver
```

一个系统几乎吃掉整颗 SoC。

但是新一代中央计算平台变成：

```text
             Central Compute SoC
                    │
             Hypervisor
       ┌────────────┼────────────┐
       │            │            │
      VM1          VM2          VM3
       │            │            │
      AAOS         ADAS       Cluster
       │            │            │
    IVI/HMI       Driving      Cluster
```

原因主要有 **5 个**。

---

## 2.1 隔离

这是 VM 最重要的价值之一。

假设：

```text
VM1 = Android IVI

VM2 = Cluster

VM3 = ADAS
```

如果 Android：

```text
system_server crash
Binder deadlock
某个 App 内存泄漏
kernel bug
```

理论上不应该直接把 Cluster / ADAS 一起干掉。

因此：

> **VM 是系统级 Fault Containment Boundary。**

这和 Android App Sandbox 完全不是一个级别。

---

# 三、VM 和 Android Sandbox 到底有什么区别？

这是理解车载 VM 非常重要的一个概念。

Android App：

```text
Linux Kernel
     │
     ├── App A
     ├── App B
     └── App C
```

App A 崩了：

```text
App A ✕
```

一般不会影响：

```text
App B
App C
system_server
```

因为 Linux process / UID / SELinux 提供隔离。

但是：

```text
App
 ↓
Android Framework
 ↓
Linux Kernel
```

所有 App 还是共享：

> **同一个 Kernel。**

如果 Kernel 出现严重问题：

```text
Kernel crash
      ↓
整个 Android
      ↓
全部 App
```

都会受到影响。

---

VM 则进一步变成：

```text
                 Hypervisor
              ┌──────┴──────┐
              │             │
            VM1           VM2
              │             │
        Android Kernel   Linux Kernel
```

VM1 和 VM2：

> **连 Kernel 都不是同一个。**

所以隔离级别明显更高。

---

# 四、VM 的基本组成

一台真正的 VM，可以抽象成：

```text
┌─────────────────────────────┐
│          Guest OS            │
│                             │
│  Application                │
│       ↓                     │
│  Framework                  │
│       ↓                     │
│  Guest Kernel               │
│       ↓                     │
│  Virtual Devices            │
└──────────────┬──────────────┘
               │
          Virtual CPU
          Virtual Memory
          Virtual Device
               │
┌──────────────▼──────────────┐
│          Hypervisor          │
└──────────────┬──────────────┘
               │
┌──────────────▼──────────────┐
│       Physical Hardware      │
│ CPU / RAM / GPU / CAN / ... │
└─────────────────────────────┘
```

VM 本质上需要虚拟化：

### CPU

```text
vCPU
 ↓
Physical CPU
```

### Memory

```text
Guest Physical Address
          ↓
Host Physical Address
```

### Device

```text
Guest virtio-net
       ↓
Virtual Device
       ↓
Host network driver
       ↓
Physical NIC
```

所以理解 VM 的关键就是四个东西：

> **CPU Virtualization + Memory Virtualization + Device Virtualization + Isolation**

---

# 五、Hypervisor 是什么？

Hypervisor 可以理解成：

> **管理多台 VM 的"操作系统"。**

它位于：

```text
Hardware
   ↓
Hypervisor
   ↓
VM
```

传统 OS：

```text
Hardware
   ↓
Linux Kernel
   ↓
Application
```

虚拟化：

```text
Hardware
   ↓
Hypervisor
   ↓
Guest Kernel
   ↓
Application
```

Hypervisor 的主要职责：

1. CPU 隔离
2. Memory 隔离
3. VM 生命周期
4. Virtual Device
5. Interrupt virtualization
6. IOMMU / DMA 隔离
7. VM-to-VM communication
8. Security boundary

---

# 六、Hypervisor 有两种基本形态

这是学习 VM 时必须掌握的概念。

## Type-1 Hypervisor

```text
Hardware
   ↓
Hypervisor
   ├── VM1
   ├── VM2
   └── VM3
```

也叫：

> Bare-metal Hypervisor

例如汽车行业常见：

* Xen
* QNX Hypervisor
* Jailhouse
* 某些商业 Automotive Hypervisor

---

## Type-2 / Hosted

```text
Hardware
   ↓
Linux
   ↓
KVM
   ↓
VM
```

Linux 本身是 Host OS。

Android AVF 使用的 KVM/pKVM 就属于这种思路的典型实现。

AOSP 对 AVF 的架构描述是：

```text
Android
   ↓
Linux Kernel
   ↓
KVM / pKVM
   ↓
Guest VM
```

其中 pKVM 建立在 Linux KVM 之上。([Android 开源项目][2])

---

# 七、ARM 车机为什么能够跑 VM？

你做车机，最应该理解的是 ARM Virtualization Extension。

现代 ARM64 CPU 有：

```text
EL0
EL1
EL2
EL3
```

可以粗略理解成权限等级：

```text
EL0 ───── Application
          ↓
EL1 ───── OS Kernel
          ↓
EL2 ───── Hypervisor
          ↓
EL3 ───── Secure Monitor / Firmware
```

ARM 官方资料也采用这种模型描述虚拟化：Guest OS 通常运行在 EL1，而 Hypervisor 位于 EL2，安全固件通常处于 EL3。([Arm 开发者][3])

所以：

```text
Guest Android

App
 │
EL0
 │
Android Linux Kernel
 │
EL1
 │
──────────────
 │
Hypervisor
 │
EL2
 │
──────────────
 │
Secure Monitor
 │
EL3
```

这就是你理解车机 Hypervisor 的第一张核心图。

---

# 八、vCPU 是什么？

VM 里面看到的是：

```text
CPU0
CPU1
CPU2
CPU3
```

但实际上这些叫：

> **vCPU = Virtual CPU**

例如：

```text
VM1
 ├── vCPU0
 ├── vCPU1
 ├── vCPU2
 └── vCPU3
```

Hypervisor 再把：

```text
vCPU0
vCPU1
vCPU2
```

调度到：

```text
Physical CPU Core
```

所以：

```text
VM
 │
 ├── vCPU0 ───── Physical CPU 2
 ├── vCPU1 ───── Physical CPU 3
 ├── vCPU2 ───── Physical CPU 4
 └── vCPU3 ───── Physical CPU 5
```

这也是为什么：

> **VM CPU 数量 ≠ 实际物理 CPU 数量。**

实际映射可以根据 Hypervisor 策略进行调度。

---

# 九、Memory Virtualization 是 VM 最核心的技术之一

假设 Android VM 认为：

```text
0x40000000
```

是自己的物理内存。

但是这个地址其实并不是 SoC 真正的物理地址。

存在至少两层：

```text
Guest Virtual Address
          ↓
Guest Physical Address
          ↓
Host Physical Address
```

即：

```text
GVA
 ↓
GPA
 ↓
HPA
```

例如：

```text
Android Process
       │
       │ virtual address
       ▼
0x7xxxxxxx
       │
       ▼
Guest Physical
0x40000000
       │
       ▼
Host Physical
0x8A000000
```

Hypervisor 负责建立这些映射和隔离。

这就是为什么 VM 能够让多个 OS：

```text
VM1:
0x40000000

VM2:
0x40000000
```

同时存在。

它们看到相同的 Guest Physical Address：

```text
VM1 → 0x40000000
VM2 → 0x40000000
```

但实际映射到不同的物理内存。

---

# 十、为什么汽车特别重视 Memory Isolation？

因为汽车场景里面可能存在：

```text
ADAS
Cluster
IVI
Telematics
Gateway
```

例如：

```text
VM1
Android IVI
2GB

VM2
Cluster
1GB

VM3
ADAS
4GB
```

如果没有硬件级内存隔离：

```text
ADAS
  ↓
Memory
  ↓
Android
```

可能互相破坏。

所以 Hypervisor + MMU + IOMMU 构成非常重要的安全边界。

---

# 十一、IOMMU 是什么？

这是你后面研究车载 VM 时一定会遇到的概念。

CPU 有 MMU：

```text
CPU
 ↓
MMU
 ↓
Memory
```

但是 DMA 设备：

```text
GPU
Camera
Ethernet
PCIe
DSP
```

可以直接访问内存。

因此需要：

```text
Device
   ↓
IOMMU
   ↓
Memory
```

IOMMU 的作用之一就是：

> **控制设备 DMA 能访问哪些物理内存。**

例如：

```text
VM1
 └── GPU
      │
      ▼
   IOMMU
      │
      ├── VM1 memory ✓
      ├── VM2 memory ✕
      └── Hypervisor ✕
```

这对汽车 VM 安全非常关键。

---

# 十二、设备虚拟化才是 Android 车机 VM 最复杂的地方

CPU / Memory 虚拟化其实只是基础。

真正做车机 VM：

> **最大的问题是设备。**

因为 Android 需要：

```text
Display
GPU
Audio
Camera
Touch
Sensor
GNSS
Bluetooth
Wi-Fi
CAN
Ethernet
Storage
USB
Power
```

Guest Android 不可能直接随便访问所有物理硬件。

因此出现：

# VirtIO

---

# 十三、VirtIO 是什么？

一句话：

> **VirtIO 是 Guest OS 和 Hypervisor/Host 之间的标准虚拟设备接口。**

例如：

```text
Android Guest

virtio-net
virtio-blk
virtio-snd
virtio-input
virtio-gpu
virtio-video
virtio-vsock
        │
        ▼
Hypervisor / Host
        │
        ▼
Physical Device
```

Google 的 AAOS 虚拟化架构就是大量采用 VirtIO。([Android 开源项目][1])

---

# 十四、VirtIO 最重要的思想

传统 Android：

```text
Android
  ↓
HAL
  ↓
Linux Driver
  ↓
Hardware
```

虚拟化以后：

```text
Android
  ↓
HAL
  ↓
VirtIO Driver
  ↓
Virtual Device
  ↓
Host Driver
  ↓
Hardware
```

所以：

> **VirtIO 把"硬件依赖"从 Guest Android 中剥离了。**

这是 Automotive VM 架构最重要的思想之一。

---

# 十五、举一个最容易理解的例子：网络

非 VM：

```text
Android
   ↓
Ethernet HAL
   ↓
Linux Network Driver
   ↓
Ethernet Controller
```

VM：

```text
Android VM
    │
    ↓
virtio-net driver
    │
    ↓
virtqueue
    │
    ↓
Host virtio-net backend
    │
    ↓
Host Ethernet Driver
    │
    ↓
Physical Ethernet
```

于是 Android 不需要知道：

```text
Qualcomm Ethernet Controller
NVIDIA Ethernet
Realtek Ethernet
```

它只需要知道：

```text
virtio-net
```

这就是：

> **Hardware Abstraction through Virtualization**

---

# 十六、Virtqueue 是什么？

VirtIO 最重要的数据结构之一：

> **virtqueue**

可以简单理解为：

```text
Guest                    Host
 │                        │
 │   descriptor           │
 │───────────────────────>│
 │                        │
 │       data             │
 │───────────────────────>│
 │                        │
 │<───────────────────────│
 │       response         │
```

实际上是一个：

> **ring buffer + descriptor**

AOSP 对 AAOS VirtIO 架构的描述也明确指出，VirtIO driver 与 device 之间通过 virtqueue 通信，其本质是类似 DMA 的 scatter-gather ring buffer。([Android 开源项目][4])

你后面研究：

```text
virtio-net
virtio-blk
virtio-snd
virtio-gpu
```

都会反复遇到它。

---

# 十七、vsock 是什么？

另一个车载 VM 非常重要的概念：

> **vsock = Virtual Socket**

它类似：

```text
TCP Socket
```

但不是走传统 IP 网络。

它主要用来：

> **VM ↔ Host / VM ↔ VM 通信**

例如：

```text
VM1
 │
 │ vsock
 ▼
VM2
```

或者：

```text
Android VM
     │
     │ vsock
     ▼
Host Service
```

AOSP 当前文档中，vsock 是 pVM 之间的主要通信方式之一，每个 VM 通过 CID 标识，类似网络里的 IP 地址。([Android 开源项目][5])

---

# 十八、为什么不用 TCP？

因为很多情况下：

```text
VM1
 ↓
Host
 ↓
VM2
```

它们其实就在：

> **同一颗 SoC。**

根本不需要：

```text
IP
Ethernet
TCP
```

所以可以直接：

```text
VM1
 ↓
vsock
 ↓
VM2
```

这样更加简单。

---

# 十九、Android Automotive 的 VM 架构

现在进入你真正关心的部分。

一个典型 AAOS VM：

```text
                    SoC
                     │
               Hypervisor
                     │
       ┌─────────────┼──────────────┐
       │             │              │
       ▼             ▼              ▼
   AAOS VM        Cluster VM      ADAS VM
       │             │              │
       │             │              │
   Android        Linux/QNX       Linux
       │
   Framework
       │
   CarService
       │
   VHAL
       │
   VirtIO / vsock
       │
       ▼
   Host VM / Service
       │
       ▼
   Physical Hardware
```

这里非常重要：

> **VHAL 不一定直接访问物理 CAN/车身硬件。**

它可以变成：

```text
VHAL Client
     │
     │ vsock
     ▼
VHAL Server
     │
     ▼
Vehicle Bus
```

AOSP 的虚拟化参考架构就是这种设计。VHAL server 可以运行在 Host VM，AAOS Guest 中运行 VHAL client，两者通过 GRPC-vsock 通信。([Android 开源项目][6])

---

# 二十、所以你熟悉的 VHAL 架构会发生变化

传统：

```text
CarService
   ↓
VHAL
   ↓
Vehicle HAL
   ↓
CAN
```

VM：

```text
CarService
   ↓
VHAL Client
   ↓
GRPC / vsock
   ↓
VHAL Server
   ↓
CAN Driver
   ↓
CAN Controller
```

这是理解 VM 对 Android 架构影响的关键。

---

# 二十一、Audio 怎么办？

传统：

```text
Android AudioFlinger
       ↓
Audio HAL
       ↓
ALSA
       ↓
Codec / DSP
```

VM：

```text
Android VM
     ↓
Audio HAL
     ↓
virtio-snd
     ↓
Host
     ↓
Audio Driver
     ↓
DSP
```

当前 AAOS 虚拟化架构已经定义了：

```text
virtio-snd
```

用于虚拟音频设备。([Android 开源项目][1])

---

# 二十二、Display 怎么办？

传统：

```text
Android
 ↓
SurfaceFlinger
 ↓
HWC
 ↓
GPU / Display Controller
```

虚拟化：

```text
Android VM
 ↓
SurfaceFlinger
 ↓
Virtual GPU / Display
 ↓
VirtIO
 ↓
Host
 ↓
Physical Display
```

当前 AAOS SDV media requirements 中已经明确涉及：

```text
virtio-gpu
virtio-input
virtio-sound
virtio-video / virtio-media
```

等虚拟设备。([Android 开源项目][7])

---

# 二十三、Sensor 怎么办？

例如：

```text
Accelerometer
Gyroscope
Temperature
```

Guest Android：

```text
Sensor HAL
    ↓
virtio / SCMI
    ↓
Host
    ↓
Physical Sensor
```

AAOS 已经扩展 VirtIO 用于汽车传感器、Power、Clock、Performance 等场景。([Android 开源项目][1])

---

# 二十四、Power 是你特别值得研究的部分

结合你之前做过的：

```text
PowerManagerService
CarPowerManagementService
CPMS
VehicleApPowerStateReq
```

VM 环境下会更加复杂。

传统：

```text
Android
 ↓
CPMS
 ↓
Power HAL
 ↓
SoC
```

VM：

```text
Android VM
 ↓
CPMS
 ↓
Power HAL
 ↓
Virtual Power Device
 ↓
Hypervisor
 ↓
Host Power Manager
 ↓
SoC
```

于是会出现：

```text
Host Power State
        │
        ├── VM1 Power State
        ├── VM2 Power State
        └── VM3 Power State
```

这意味着：

> **整机 Power State 和单个 Guest OS Power State 不再是同一个概念。**

这会直接影响：

* suspend
* resume
* reboot
* shutdown
* wakeup
* ignition off
* garage mode
* watchdog
* VM crash recovery

AOSP 当前 SDV/VM 要求也明确要求 Host 能够控制 Guest 的启动、唤醒和干净关闭。([Android 开源项目][8])

---

# 二十五、VM Boot 是怎么发生的？

你可以把启动链理解成：

```text
Boot ROM
   ↓
Bootloader
   ↓
Hypervisor
   ↓
Host OS
   ↓
VMM
   ↓
Create VM
   ↓
Load Guest Kernel
   ↓
Guest Bootloader
   ↓
Guest Kernel
   ↓
Android init
   ↓
System Server
   ↓
CarService
```

如果有多个 VM：

```text
Boot
 │
 ▼
Hypervisor
 │
 ├── Start Cluster VM
 │
 ├── Start ADAS VM
 │
 └── Start Android VM
```

因此：

> **Hypervisor 已经成为整车系统启动链的一部分。**

---

# 二十六、VMM 又是什么？

这里容易和 Hypervisor 混淆。

例如：

```text
Hypervisor = KVM
VMM        = crosvm
```

可以理解：

### Hypervisor

负责：

```text
CPU
Memory
Isolation
Virtualization
```

### VMM

负责：

```text
创建 VM
创建 vCPU
配置 Memory
创建 Virtual Device
加载 Kernel
处理 VM IO
```

Android AVF 中：

```text
VirtualizationService
        ↓
      crosvm
        ↓
       KVM
        ↓
      Hardware
```

AOSP 明确将 crosvm 定义为 VMM，它通过 Linux KVM 接口运行 VM，并负责 VM memory、vCPU thread 和 virtual device backend。([Android 开源项目][2])

---

# 二十七、所以这几个概念一定要区分

```text
Hypervisor
    ↓
负责真正的硬件虚拟化

KVM
    ↓
Linux 中的 Hypervisor 技术

pKVM
    ↓
Android 对 KVM 的安全增强

VMM
    ↓
用户空间 VM 管理器

crosvm
    ↓
Google/Android 使用的 VMM

VirtualizationService
    ↓
Android Framework 层 VM 生命周期管理

Microdroid
    ↓
运行在 VM 中的轻量 Android OS
```

这几个概念搞清楚之后，Android VM 的架构基本就打开了。

---

# 二十八、Android AVF 是什么？

你可能会在 AOSP 中看到：

> **AVF — Android Virtualization Framework**

它和 Automotive Virtualization 不是完全相同的东西。

AVF 的目标主要是：

> **让 Android 能够安全地运行隔离的 pVM。**

架构：

```text
Android
 │
 │ VirtualizationService
 ▼
crosvm
 │
 ▼
pKVM
 │
 ▼
Microdroid
```

AOSP 当前 AVF 支持 ARM64，并使用 pKVM 作为核心 hypervisor 技术。([Android 开源项目][9])

---

# 二十九、Microdroid 是什么？

Microdroid 可以理解成：

> **一个极简 Android Guest OS。**

它不是完整 Android。

没有：

```text
SystemServer
Zygote
完整 Java Framework
Graphics/UI
完整 HAL
```

它主要用于：

```text
安全执行某些 Native Code
```

AOSP 对 Microdroid 的定义就是运行在 pVM 中的 mini-Android OS。([Android 开源项目][10])

---

# 三十、为什么车机会需要 Microdroid？

例如：

```text
普通 Android App
        │
        ├── UI
        ├── 普通业务
        │
        └── Sensitive Algorithm
                   │
                   ▼
               Microdroid
```

比如：

* 密钥处理
* DRM
* AI inference
* sensitive computation
* security-sensitive logic

这样即使 Android Host 被攻破：

```text
Android Host ✕
       │
       X
       │
Microdroid
```

依然可以保持较强隔离。

pVM 的一个核心目标就是即使 Host Android 被攻破，也限制其访问 Guest 的内存。([Android 开源项目][9])

---

# 三十一、普通 VM 和 pVM 的区别

普通 VM：

```text
Host
 │
 ├── VM1
 └── VM2
```

Host 通常拥有更高权限。

pVM：

```text
Host
 │
 ├── pVM1
 └── pVM2
```

但：

> Host 本身也不能随便访问 pVM memory。

所以：

```text
普通 VM

Host
 ↓
Guest Memory
✓
```

而：

```text
pVM

Host
 ↓
Guest Memory
✕
```

这就是 pKVM 的重要价值。

---

# 三十二、为什么汽车 VM 和手机 AVF 不完全一样？

这是你研究时非常重要的一点。

### Android AVF

关注：

```text
Security
Isolation
Protected VM
Microdroid
App sandbox enhancement
```

### Automotive Virtualization

关注：

```text
IVI
ADAS
Cluster
Audio
Display
Sensor
VHAL
Power
CAN
Vehicle Network
```

所以：

```text
AVF
   ↓
Security-oriented virtualization

AAOS Automotive Virtualization
   ↓
System-level automotive virtualization
```

两者技术基础有重叠，但目标不同。

---

# 三十三、车机 VM 最核心的架构变化

如果把传统 Android 和 VM Android 放在一起：

## Traditional

```text
              Android
                 │
          ┌──────┴──────┐
          │ Framework   │
          │ HAL         │
          │ Driver      │
          └──────┬──────┘
                 │
               SoC
```

## Virtualized

```text
                  Hypervisor
                      │
        ┌─────────────┼─────────────┐
        │             │             │
     AAOS VM       Cluster VM     ADAS VM
        │             │             │
   Framework       Framework       Linux
        │
       HAL
        │
   VirtIO / vsock
        │
        ▼
   Host / Service
        │
        ▼
    Physical HW
```

这意味着：

> **HAL 以下的架构发生了巨大的变化。**

---

# 三十四、为什么 VirtIO 对 Android 非常重要？

因为它让：

> **Android Framework 尽可能保持不变。**

例如：

```text
CarService
    ↓
VHAL
    ↓
Generic HAL
    ↓
virtio / vsock
```

而不是：

```text
CarService
    ↓
Qualcomm VHAL
    ↓
Qualcomm Driver
```

因此：

```text
AAOS Image
       ↓
VirtIO
       ↓
Hypervisor A

AAOS Image
       ↓
VirtIO
       ↓
Hypervisor B
```

理论上可以提高：

> **Guest OS 的平台可移植性。**

AOSP 也明确指出，VirtIO 使 AAOS Guest 可以针对一个通用虚拟平台运行，从而降低对具体 Hypervisor 和硬件平台的依赖。([Android 开源项目][1])

---

# 三十五、这对 OEM 架构有什么重大意义？

以前：

```text
Android
  ↓
Qualcomm BSP
  ↓
Qualcomm Hardware
```

换平台：

```text
Android
  ↓
重新适配
```

现在希望变成：

```text
Android
 ↓
VirtIO
 ↓
Virtual Platform
 ↓
Hypervisor
 ↓
Qualcomm / NVIDIA / Renesas / ...
```

因此：

> **硬件平台和 Android Guest 之间出现了一个新的稳定 ABI。**

这就是 Virtual Platform 的思想。

---

# 三十六、一个完整车机 VM 数据流

我们拿一个你熟悉的场景：

> 用户调节空调温度。

传统：

```text
User
 ↓
AAOS UI
 ↓
CarService
 ↓
HVAC Manager
 ↓
VHAL
 ↓
CAN
 ↓
BCM/HVAC ECU
```

VM：

```text
User
 ↓
AAOS VM
 ↓
CarService
 ↓
HVAC Manager
 ↓
VHAL Client
 ↓
GRPC/vsock
 ↓
Host VHAL Server
 ↓
CAN Driver
 ↓
CAN Controller
 ↓
Vehicle Bus
 ↓
HVAC ECU
```

所以你会发现：

> **VM 本质上把"硬件访问路径"切开了。**

---

# 三十七、再看 Audio

```text
App
 ↓
AudioTrack
 ↓
AudioFlinger
 ↓
Audio HAL
 ↓
virtio-snd
 ↓
Hypervisor
 ↓
Host Audio
 ↓
DSP
 ↓
AMP
 ↓
Speaker
```

---

# 三十八、再看 Camera

可能变成：

```text
Camera App
 ↓
Camera Framework
 ↓
Camera HAL
 ↓
virtio-video / shared memory
 ↓
Host Camera Service
 ↓
ISP
 ↓
Camera
```

这里会比 Audio、Network 更复杂，因为：

> Camera / GPU / Video 涉及大量 DMA + buffer sharing。

这也是 Automotive Virtualization 最难的部分之一。

---

# 三十九、Shared Memory 为什么重要？

VM 间通信如果全部：

```text
VM1
 ↓
copy
 ↓
VM2
```

性能会很差。

尤其：

```text
4K Video
Camera Frame
GPU Buffer
Audio Buffer
```

所以通常会设计：

```text
VM1
 │
 │ shared memory
 ▼
VM2
```

配合：

* DMA
* IOMMU
* memory mapping
* synchronization
* cache coherency

实现高性能数据交换。

---

# 四十、汽车 VM 中真正难的不是"创建 VM"

创建：

```text
VM
vCPU
Memory
virtio-net
```

其实不是最困难的。

真正困难的是：

### 1. GPU

### 2. Camera

### 3. Display

### 4. Audio

### 5. Sensor

### 6. CAN

### 7. Power

### 8. Watchdog

### 9. OTA

### 10. Safety

### 11. Boot time

### 12. Crash recovery

### 13. VM-to-VM communication

所以 Automotive VM 本质上是：

> **一个系统架构问题，而不是简单的 Hypervisor 问题。**

---

# 四十一、VM 对 Watchdog 的影响

传统：

```text
Watchdog
 ↓
Android
```

VM：

```text
Hardware Watchdog
       ↓
Hypervisor / Host
       ↓
 ┌─────┼──────┐
 ↓     ↓      ↓
VM1   VM2    VM3
```

于是要考虑：

```text
VM1 Crash
```

到底应该：

```text
restart VM1
```

还是：

```text
restart entire SoC
```

还是：

```text
restart Host
```

这涉及：

> **Fault containment strategy**

汽车架构里非常重要。

---

# 四十二、VM 对 OTA 的影响

传统：

```text
OTA
 ↓
Android System
```

VM：

```text
OTA
 │
 ├── Hypervisor
 ├── Host
 ├── AAOS VM
 ├── Cluster VM
 └── ADAS VM
```

所以 OTA 变成：

> **Multi-OS / Multi-VM OTA**

需要解决：

* version dependency
* rollback
* A/B
* VM image
* compatibility
* secure boot
* hypervisor update
* guest update

AOSP 当前 SDV 要求 Host OTA 机制必须能够应对断电等情况。([Android 开源项目][8])

---

# 四十三、VM 对 Secure Boot 的影响

传统：

```text
Boot ROM
 ↓
Bootloader
 ↓
Android
```

VM：

```text
Boot ROM
 ↓
Bootloader
 ↓
Hypervisor
 ↓
VM Loader
 ↓
Guest Bootloader
 ↓
Guest Kernel
 ↓
Android
```

因此必须建立：

> **Chain of Trust**

例如：

```text
Root of Trust
      ↓
Bootloader
      ↓
Hypervisor
      ↓
Guest
      ↓
Android
```

Google 当前 SDV 架构甚至使用 DICE chain 描述：

```text
Bootloader
 ↓
Hypervisor
 ↓
Android HLOS
```

每一层对下一层进行身份/完整性证明。([Android 开源项目][11])

---

# 四十四、VM 对安全架构的意义

可以把安全边界理解成：

```text
                    Hardware
                       │
                 Hypervisor
            ┌──────────┼──────────┐
            │          │          │
          VM1        VM2        VM3
            │          │          │
          SELinux    SELinux    SELinux
            │          │          │
           App        App        App
```

所以实际上是：

```text
Hardware Isolation
        +
VM Isolation
        +
Kernel Isolation
        +
SELinux
        +
Process Isolation
        +
App Sandbox
```

形成纵深防御。

---

# 四十五、车机 VM 中几个最重要的通信方式

你以后看架构图，看到这些词基本就知道是什么了：

| 技术            | 作用                |
| ------------- | ----------------- |
| VirtIO        | 虚拟设备              |
| virtqueue     | VirtIO 数据通道       |
| vsock         | VM ↔ VM / Host 通信 |
| Binder        | Android IPC       |
| Binder RPC    | 跨 VM Android 服务通信 |
| shared memory | 高性能数据共享           |
| GRPC          | RPC 协议            |
| Ethernet      | VM 网络             |
| PCIe          | 虚拟/物理设备总线         |
| MMIO          | 虚拟设备访问方式          |

---

# 四十六、Binder 和 vsock 的关系

这个特别容易混。

不是：

```text
Binder vs vsock
```

而是：

```text
Binder
  ↓
IPC mechanism

vsock
  ↓
Transport
```

例如：

```text
Android VM
   │
Binder
   │
Service
   │
Binder RPC
   │
vsock
   │
Host
```

因此：

> **Binder 可以建立在 vsock 上做跨 VM IPC。**

AVF 中也采用 Binder 作为主要的 VM 间通信机制，并利用 vsock 作为底层连接。([Android 开源项目][9])

---

# 四十七、你应该形成这样的完整认知

最终脑子里应该有这样一张图：

```text
┌─────────────────────────────────────────────────────┐
│                    Automotive SoC                    │
│                                                     │
│  CPU / Memory / GPU / DSP / ISP / CAN / Ethernet   │
│                                                     │
├─────────────────────────────────────────────────────┤
│                    Hypervisor                       │
│                 EL2 / KVM / pKVM                    │
│                                                     │
├──────────────┬────────────────┬─────────────────────┤
│              │                │                     │
│   AAOS VM    │   Cluster VM   │      ADAS VM        │
│              │                │                     │
│ Android      │ Linux/QNX      │ Linux               │
│              │                │                     │
│ Framework    │ Cluster SW     │ ADAS SW             │
│              │                │                     │
│ CarService   │                │                     │
│      │       │                │                     │
│ VHAL         │                │                     │
│      │       │                │                     │
│ VirtIO       │                │                     │
└──────┼───────┴────────┬───────┴─────────────────────┘
       │                │
       └───────┬────────┘
               │
        VirtIO / vsock
               │
        Host Services
               │
     ┌─────────┼─────────┐
     │         │         │
    GPU       Audio      CAN
     │         │         │
     └─────────┼─────────┘
               │
          Physical HW
```

这张图基本就是你未来学习的"地图"。

---

# 四十八、当前 Android Automotive 的发展方向

这一点值得你特别关注。

Google 目前正在推进：

> **Android Automotive + Software Defined Vehicle**

AOSP 当前的 SDV 架构明确采用 Multi-VM 思路，SDV Core 被设计成运行在 VirtIO-capable Hypervisor 上，并可以与 AAOS IVI 并行运行。([Android 开源项目][12])

可以理解为：

```text
传统：

                 AAOS
                   │
                Vehicle
```

逐渐变成：

```text
                  SoC
                   │
               Hypervisor
                   │
       ┌───────────┼────────────┐
       │           │            │
      IVI        SDV Core      ADAS
       │           │            │
      HMI       Services      Driving
```

更进一步：

```text
                    SDV Platform
                         │
          ┌──────────────┼──────────────┐
          │              │              │
       Service A      Service B      Service C
          │              │              │
       VM1/VM2        VM2/VM3        VM1/VM3
```

也就是：

> **从"一个 Android OS"走向"一个软件定义的分布式计算平台"。**

---

# 四十九、这对你个人技术栈意味着什么？

结合你现在的工作方向，我认为你学习 VM 的价值非常高。

你已经熟悉：

```text
Android
Linux
Power
VHAL
RDM
底软
SoC
日志
版本管理
```

现在缺的一块其实是：

```text
           ┌── Hypervisor
           │
Android ───┼── VM
           │
           ├── VirtIO
           │
           ├── vsock
           │
           ├── IOMMU
           │
           └── Multi-OS
```

一旦补齐，你的视角会从：

> **Android 底软工程师**

升级到：

> **Automotive Computing Platform / System Architecture**

这两个能力层次差别很大。

---

# 五十、建议你的学习路线

我不建议你直接去看 Xen/QNX/VMware 一大堆资料。

应该按下面的顺序。

---

## Level 1：CPU Virtualization

先搞懂：

```text
ARM EL0
EL1
EL2
EL3
```

然后：

```text
Exception Level
MMU
Stage-1 Translation
Stage-2 Translation
vCPU
Virtual Interrupt
```

重点理解：

> **Guest Kernel 为什么能够运行在虚拟 CPU 上。**

---

# Level 2：Memory Virtualization

重点：

```text
GVA
GPA
HPA

Stage 1
Stage 2

MMU
SMMU / IOMMU
DMA
```

这是 VM 的核心基础。

---

# Level 3：KVM

然后学习：

```text
Linux
 ↓
KVM
 ↓
VM
```

重点理解：

```text
/dev/kvm
KVM_CREATE_VM
KVM_CREATE_VCPU
ioctl
vCPU
VM memory
```

AOSP 的 AVF 文档对这些 KVM API 和 crosvm 的关系有非常直接的说明。([Android 开源项目][2])

---

# Level 4：crosvm

然后：

```text
crosvm
```

研究：

```text
VM lifecycle
vCPU
memory
virtio
devices
sandbox
```

你会真正看到：

```text
VMM
 ↓
KVM
 ↓
VM
```

是怎么组合起来的。

---

# Level 5：VirtIO

这是 Automotive 必学。

至少搞懂：

```text
virtio
virtqueue
descriptor
virtio-blk
virtio-net
virtio-console
virtio-input
virtio-snd
virtio-gpu
virtio-video
```

---

# Level 6：vsock

然后研究：

```text
CID
Port
VM ↔ VM
VM ↔ Host
```

再看：

```text
Binder RPC
GRPC-vsock
```

---

# Level 7：AAOS Virtualization

最后进入：

```text
AAOS VM
VHAL
Audio
Display
Sensor
GNSS
Power
Bluetooth
```

AOSP 目前已经提供了一套比较完整的 AAOS Virtualization 架构说明和参考实现。([Android 开源项目][1])

---

# Level 8：SDV

最后研究：

```text
AAOS SDV
Multi-VM
SDV Core
Service architecture
Distributed services
Display Safety
DICE
OTA
```

这个方向更接近未来中央计算平台。

---

# 五十一、建议你实际做一个实验

如果你真的想把 VM 学明白，我强烈建议不要只看资料。

直接做：

```text
Cuttlefish
      ↓
AAOS
      ↓
AVF
      ↓
Microdroid
      ↓
crosvm
      ↓
KVM
```

AOSP 官方提供了 AVF 的实验路径，包括 Cuttlefish、Microdroid Demo 等。([Android 开源项目][13])

你最终应该能够亲手完成：

```text
Android
   ↓
创建 VM
   ↓
crosvm
   ↓
KVM
   ↓
启动 Microdroid
   ↓
adb
   ↓
Binder/vsock
   ↓
Host
```

做到这一步，你对 VM 的理解就不会停留在概念层。

---

# 五十二、最后给你一张"知识树"

你可以把下面这棵树作为未来一段时间的学习目录：

```text
Android Automotive Virtualization
│
├── 1. Computer Architecture
│   ├── ARM64
│   ├── EL0/EL1/EL2/EL3
│   ├── MMU
│   ├── Stage-1
│   ├── Stage-2
│   ├── IOMMU/SMMU
│   └── Interrupt
│
├── 2. Hypervisor
│   ├── Type-1
│   ├── Type-2
│   ├── KVM
│   ├── pKVM
│   ├── vCPU
│   ├── VM Memory
│   └── VM Lifecycle
│
├── 3. VMM
│   ├── crosvm
│   ├── VM Creation
│   ├── Device Backend
│   └── Sandbox
│
├── 4. Device Virtualization
│   ├── VirtIO
│   ├── virtqueue
│   ├── virtio-net
│   ├── virtio-blk
│   ├── virtio-snd
│   ├── virtio-gpu
│   ├── virtio-input
│   └── virtio-video
│
├── 5. IPC
│   ├── vsock
│   ├── Binder
│   ├── Binder RPC
│   ├── GRPC
│   └── Shared Memory
│
├── 6. Android
│   ├── AVF
│   ├── VirtualizationService
│   ├── Microdroid
│   ├── pVM
│   └── pvmfw
│
├── 7. Automotive
│   ├── AAOS VM
│   ├── VHAL
│   ├── Audio
│   ├── Display
│   ├── Camera
│   ├── Sensor
│   ├── GNSS
│   ├── Power
│   └── CAN
│
├── 8. System Architecture
│   ├── Multi-VM
│   ├── Fault Isolation
│   ├── Watchdog
│   ├── OTA
│   ├── Boot
│   └── Recovery
│
└── 9. SDV
    ├── SDV Core
    ├── Distributed Service
    ├── Multi-OS
    ├── Central Compute
    └── Safety
```

---

# 五十三、你现阶段最应该搞懂的 10 个问题

如果这 10 个问题你都能够自己解释，我认为你就已经入门了：

1. **ARM EL2 为什么可以实现 Hypervisor？**
2. **Guest OS 为什么感觉自己拥有完整 CPU？**
3. **GVA / GPA / HPA 分别是什么？**
4. **Stage-2 translation 解决什么问题？**
5. **KVM 和 crosvm 分别负责什么？**
6. **VirtIO 为什么能让 Android 和具体 SoC 解耦？**
7. **virtqueue 到底是怎么传数据的？**
8. **vsock 和 TCP/IP 有什么区别？**
9. **VHAL 在 VM 架构中为什么可能被拆成 Client / Server？**
10. **Power / Watchdog / OTA 为什么在 Multi-VM 下变得复杂？**

如果你能把这 10 个问题讲通，基本就已经从：

**"知道 VM 是什么"**

进入到：

**"能够设计 Automotive VM 架构"**

的阶段。

---

## 最后一个非常重要的判断

对于你目前的技术背景，我建议你**不要把 VM 当成一个新的独立技术栈来学**。

应该把它理解成：

```text
你原来的知识：

Android
  ↓
Linux
  ↓
HAL
  ↓
Driver
  ↓
Hardware

              ↓ 加上一层 ↓

Android
  ↓
Guest Kernel
  ↓
VirtIO / vsock
  ↓
Hypervisor
  ↓
Host
  ↓
Physical Hardware
```

也就是说，你已经掌握了下面一半：

```text
        Android
           ↓
      Linux / HAL
           ↓
       Hardware
```

现在真正需要补的是中间这一层：

```text
       Guest
         ↓
   VirtIO / vsock
         ↓
       VMM
         ↓
   KVM / pKVM
         ↓
      Hardware
```

**这恰好也是你从 Android 底软向"车载中央计算/平台架构"升级时非常关键的一块知识。**

如果你按这个方向继续，我建议下一步直接进入 **"VM 实战篇"**：我可以继续给你拆一套 **《从 ARM EL2 → KVM → crosvm → VirtIO → AAOS VM 的源码级学习教程》**，逐步带你看 `/dev/kvm`、vCPU、Stage-2 MMU、virtqueue、vsock，以及最终 **VHAL/CPMS 在 VM 架构里到底怎么落地**。这会比继续泛读 VM 理论更适合你的工作背景。

---

## 参考资料

[1]: https://source.android.com/docs/automotive/virtualization?utm_source=chatgpt.com "Overview  |  Android Open Source Project"

[2]: https://source.android.com/docs/core/virtualization/architecture?utm_source=chatgpt.com "AVF architecture  |  Android Open Source Project"

[3]: https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/Armv8-A%20virtualization.pdf?utm_source=chatgpt.com "Armv8-A virtualization"

[4]: https://source.android.com/docs/automotive/virtualization/architecture?hl=zh-cn&utm_source=chatgpt.com "架构  |  Android Open Source Project"

[5]: https://source.android.com/docs/core/virtualization/virtualization-service?utm_source=chatgpt.com "VirtualizationService  |  Android Open Source Project"

[6]: https://source.android.com/docs/automotive/virtualization/architecture?hl=zh-CN&utm_source=chatgpt.com "架构  |  Android Open Source Project"

[7]: https://source.android.com/docs/automotive/sdv/workstreams/media/requirements?hl=en&utm_source=chatgpt.com "SDV Media requirements  |  Android Open Source Project"

[8]: https://source.android.com/docs/automotive/sdv/workstreams/core/requirements?utm_source=chatgpt.com "Guest system (VM image) requirements  |  Android Open Source Project"

[9]: https://source.android.com/docs/core/virtualization?hl=en&utm_source=chatgpt.com "Android Virtualization Framework (AVF) overview  |  Android Open Source Project"

[10]: https://source.android.com/docs/core/virtualization/microdroid?hl=en&utm_source=chatgpt.com "Microdroid  |  Android Open Source Project"

[11]: https://source.android.com/docs/automotive/sdv/workstreams/core/vm-attestation/dice-profile?utm_source=chatgpt.com "SDV profile for DICE  |  Android Open Source Project"

[12]: https://source.android.com/docs/automotive/sdv/sdv-system-architecture?utm_source=chatgpt.com "SDV architecture  |  Android Open Source Project"

[13]: https://source.android.com/docs/core/virtualization/tryavf?utm_source=chatgpt.com "Try Android Virtualization Framework (AVF)  |  Android Open Source Project"
