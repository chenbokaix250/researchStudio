# Android OTA 研究

> 创建时间：2026-03-20
> 状态：📝 进行中

---

## 概述

Android Over-The-Air (OTA) 更新系统研究笔记。

---

Android 在升级完成后出现“**合并过程**”，本质上是因为它采用了 **A/B 分区 + 增量更新（delta OTA）+ 动态分区快照（Virtual A/B）** 这一整套机制。这个“合并”并不是多余步骤，而是为了 **无缝升级（Seamless Update）+ 可回滚 + 减少写入量** 的工程折中。

下面我按体系给你拆清楚（偏工程实现视角）。

---

# 一、Android 升级方案全景（从早期到现在）

## 1. 早期方案：Recovery OTA（非 A/B）

特点：

* 下载完整 OTA 包
* 重启进入 recovery
* 直接覆盖 system / boot / vendor

问题：

* 升级期间不可用（停机）
* 失败容易变砖
* 无法回滚

👉 这是 Android 6 及以前主流方案

---

## 2. A/B 分区（Seamless Update）

从 Android 7（Android Nougat）开始引入

### 核心思想

设备有两套分区：

```
当前运行：slot A
备用分区：slot B
```

升级流程：

1. 系统在后台下载 OTA
2. 把新系统写入 **B 分区**
3. 重启 → 切换到 B
4. 如果启动成功 → 标记成功
5. 如果失败 → 自动回滚到 A

### 优点

* 无需停机升级
* 安全（天然 rollback）
* 用户无感

### 缺点

* 占用两倍分区空间
* 写入成本高（全量写）

---

## 3. 动态分区（Dynamic Partitions）

从 Android 10（Android 10）开始

### 核心点

* system / vendor / product 不再是固定分区
* 统一放在 super 分区里（逻辑分区）

👉 好处：

* 分区大小可动态调整
* OTA 更灵活

---

## 4. Virtual A/B（重点：你看到“合并”的根因）

从 Android 11（Android 11）开始

这是目前主流方案（车机、手机基本都在用）

---

# 二、为什么会有“合并过程”？

## 核心结论：

👉 因为 Virtual A/B 使用了 **快照（snapshot）+ Copy-on-Write（COW）机制**

---

## 1. 升级时并没有真的写完整 B 分区

传统 A/B：

```
直接写 B 分区（完整镜像）
```

Virtual A/B：

```
创建 snapshot（快照）
+ 写入差异数据（COW）
```

---

## 2. Snapshot 工作原理（关键）

升级时：

```
原始分区（system）
        ↓
创建 snapshot（逻辑映射）
        ↓
新数据写入 COW 文件
```

此时系统结构：

```
[旧数据] + [COW差异块] = 新系统视图
```

👉 设备看到的是“新系统”，但实际上数据是拼出来的

---

## 3. 重启后发生了什么？

设备已经切换到新系统，但底层仍然是：

```
旧数据 + COW overlay
```

👉 这时候性能和稳定性都不是最优状态

---

## 4. 合并（merge）过程

系统会在后台做一件事：

```
把 COW 数据真正写回原始分区
```

也就是：

```
merge:
COW → base partition
```

完成后：

```
system 分区 = 完整新系统
COW 被删除
```

---

## 5. 为什么不直接写？

这是关键设计权衡：

| 方案               | 优点         | 缺点      |
| ---------------- | ---------- | ------- |
| 直接写分区            | 简单         | 慢 + 不安全 |
| snapshot + merge | 快速切换 + 可回滚 | 需要后处理   |

👉 Google 选择了：
**先快速可用，再慢慢整理（merge）**

---

# 三、合并过程的工程意义

## 1. 保证“快速开机”

升级完成后用户可以立即使用系统

## 2. 保证“可回滚”

如果 merge 前出问题：

* 仍然可以 rollback

## 3. 减少写放大

只写差异（delta），不是全量刷写

---

# 四、合并过程的触发机制

由 Android 的 update engine + init 共同驱动：

关键组件：

* update_engine
* snapuserd（用户态 snapshot driver）
* dm-snapshot / dm-user

---

## merge 触发条件

通常：

* 开机后自动触发
* 空闲时执行
* 充电时优先

---

## merge 状态机（简化）

```
NONE
 → SNAPSHOTTED
 → MERGING
 → MERGED
```

---

# 五、为什么你会“明显感知到合并”？

在车机/嵌入式设备上尤其明显，原因：

## 1. IO 带宽有限

* eMMC / UFS 性能较低
* merge 是大量写操作

## 2. CPU 被占用

* COW block replay
* metadata 更新

## 3. 系统调度不够优化

* merge 和前台任务抢资源

👉 表现：

* 卡顿
* 发热
* 启动后性能下降一段时间

---

# 六、车载 Android（你场景）特殊点

你做的是智能座舱/智驾，这里有几个更关键：

## 1. OTA 包通常是增量

* 版本跨度大 → COW 数据多 → merge 时间长

## 2. 分区更复杂

* system_ext
* vendor
* odm
* product

👉 merge 不是一个分区，是多个

---

## 3. 实时性要求高

merge 可能影响：

* 音频
* UI 流畅度
* 车控服务

👉 有些厂会：

* 延迟 merge
* 或限制 merge IO

---

# 七、优化思路（工程实战）

如果你要优化这个问题，可以从这些方向入手：

## 1. 限速 merge IO

```
ionice / cgroup / blkio
```

## 2. 调整 merge 时机

* 仅在：

  * 熄火
  * 充电
  * 空闲

## 3. 减小 OTA 包

* 提高 diff 精度
* 避免无意义文件变更

## 4. 分阶段 merge

* 优先关键分区
* 延迟非关键分区

## 5. 监控 merge 状态

```
/metadata/ota/snapshots
```

---

# 八、一句话总结

👉 Android 升级后的“合并过程”，本质是：

> **Virtual A/B 通过 snapshot + COW 实现快速升级，而 merge 是把“临时差异”真正固化到分区的后台过程**

---

如果你愿意，我可以帮你进一步拆：

* update_engine 源码级流程（非常适合你做版本管理）
* snapuserd / dm-user 的实现机制
* 或者给你一套 **车机 OTA 架构设计（含回滚策略 + 灰度升级）**


好，这三块我按“**可落地工程视角**”给你拆：不仅讲原理，还会贴近你做**车机/智驾版本管理**的实际场景。

---

# 一、update_engine 源码级流程（OTA 主链路）

Android OTA 的核心执行体是
👉 update_engine

它本质是一个 **状态机驱动的分块更新引擎**。

---

## 1. 整体流程（从云到设备）

```
云端 OTA 包
   ↓
下载（HTTP / HTTPS）
   ↓
校验（metadata + payload hash）
   ↓
解析 payload.bin
   ↓
执行 InstallOperation（核心）
   ↓
写入 snapshot（Virtual A/B）
   ↓
标记 slot 可启动
   ↓
重启切换 slot
   ↓
merge（后台）
```

---

## 2. payload.bin 内部结构（关键）

payload 不是简单镜像，而是：

```
payload.bin
 ├── header
 ├── manifest（protobuf）
 └── data blobs
```

manifest 里定义：

```
PartitionUpdate {
  partition_name: "system"
  operations: [InstallOperation...]
}
```

---

## 3. InstallOperation（核心执行单元）

典型操作：

| 类型            | 作用     |
| ------------- | ------ |
| REPLACE       | 全量写块   |
| REPLACE_BZ    | 压缩块    |
| SOURCE_COPY   | 从旧分区复制 |
| SOURCE_BSDIFF | 二进制差分  |
| ZERO          | 填零     |

👉 本质：
**不是刷镜像，而是执行“块级 patch 脚本”**

---

## 4. Virtual A/B 下的写入路径

传统 A/B：

```
write → /dev/block/by-name/system_b
```

Virtual A/B：

```
write → snapshot (dm-user)
         ↓
       COW file
```

涉及组件：

* snapuserd
* dm-user
* dm-snapshot

---

## 5. 状态机（精简版）

```
IDLE
 → DOWNLOADING
 → VERIFYING
 → FINALIZING
 → UPDATED_NEED_REBOOT
 → REPORTING_SUCCESS
```

---

## 6. 关键源码路径（AOSP）

```
system/update_engine/
```

重点文件：

* `update_attempter.cc`
* `payload_consumer/`
* `install_operation_executor.cc`

---

## 7. 你这个岗位要关注的点

在“版本管理/车机 OTA”里，关键是：

### ✔ 失败点控制

* hash mismatch
* partition 写失败
* snapshot 空间不足

### ✔ 幂等性

* 断电恢复
* 重试机制

---

# 二、snapuserd / dm-user 实现机制

这是“合并过程”的底层核心。

---

## 1. snapuserd 是什么？

👉 snapuserd

用户态守护进程，负责：

```
处理 snapshot 的读写请求
```

---

## 2. 数据结构（非常关键）

### COW（Copy-On-Write）

```
/data/ota/snapshots/system.cow
```

记录：

```
{
  old_block → new_block
}
```

---

## 3. 读路径（运行时）

当系统读取 block：

```
read(block X)
   ↓
dm-user 拦截
   ↓
if X in COW:
    return COW data
else:
    return base partition data
```

👉 这是 overlay 行为

---

## 4. 写路径（OTA 时）

```
write(block X)
   ↓
写入 COW
```

---

## 5. merge 过程（重点）

merge 时：

```
for each block in COW:
    write → base partition
```

然后：

```
删除 COW
```

---

## 6. 为什么用用户态（snapuserd）？

不是内核 dm-snapshot 的原因：

| 方案          | 问题      |
| ----------- | ------- |
| dm-snapshot | 内存占用大   |
| 用户态         | 灵活 + 可控 |

---

## 7. 性能关键点

### merge 是瓶颈：

* 顺序写 → OK
* 随机写 → 很慢（尤其 eMMC）

👉 优化关键：

* block 排序
* IO 限速

---

# 三、车机 OTA 架构设计（重点：可落地）

结合你当前岗位，我给你一个**完整可用架构**。

---

## 1. 整体架构

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

---

## 2. 云端设计

### 必备能力：

#### ✔ 版本管理

* base version
* target version
* 兼容矩阵

#### ✔ 灰度策略

* VIN 分组
* 地域
* 车型

#### ✔ 包管理

* 全量包
* 增量包（delta）

---

## 3. 车端 OTA Agent（你可以重点做）

职责：

```
1. 拉取任务
2. 校验策略
3. 下载 OTA
4. 调用 update_engine
5. 上报状态
6. 控制重启
```

---

## 4. 回滚策略（关键）

### A/B 已经提供基础能力，但不够

你要补：

#### ✔ 业务健康检查

```
开机后：
- 服务是否启动
- 音频是否正常
- 关键进程是否存活
```

#### ✔ 超时回滚

```
if 30min 内未标记成功：
    rollback
```

---

## 5. 灰度发布策略（实战）

### 推荐方案：

```
1% → 5% → 20% → 50% → 100%
```

每阶段：

* 收集 crash
* 收集 ANR
* 收集升级失败率

---

## 6. 分区升级策略（车机特有）

不要“一锅端”：

### 建议拆分：

| 分区     | 策略        |
| ------ | --------- |
| boot   | 强一致       |
| system | OTA       |
| vendor | 慎重        |
| 应用层    | 独立升级（APK） |

---

## 7. 合并（merge）优化策略

这是你可以拉开差距的点👇

### ✔ 策略1：延迟 merge

```
仅在：
- 熄火
- 夜间
- 充电
```

---

### ✔ 策略2：限速

```
blkio.throttle.write_bps_device
```

---

### ✔ 策略3：分阶段 merge

```
system → vendor → product
```

---

### ✔ 策略4：可中断 merge

防止：

* 用户启动 → 卡顿

---

## 8. 监控体系（必须有）

关键指标：

```
升级成功率
升级耗时
merge耗时
回滚率
分区失败率
```

---

# 四、给你一个“晋升级总结话术”

如果你要在答辩/汇报说：

> Android OTA 采用 Virtual A/B 机制，通过 snapshot + COW 实现无感升级，升级后通过后台 merge 完成数据固化。我在项目中重点优化了 merge 时机与 IO 调度，降低对车机实时业务的影响，同时结合灰度发布与健康检查机制，构建了完整的 OTA 风险控制闭环。

👉 这是**非常加分的表达**（技术 + 体系 + 落地）

---

# 五、如果你要再往深挖

我可以继续帮你拆：

1. update_engine 如何做断点续传（delta resume）
2. OTA 包生成（brillo_update_payload 工具链）
3. Android vs Linux（SWUpdate / Mender）对比
4. 车企常见 OTA 坑（真实踩坑总结）

直接说你要哪一块，我给你做到“能拿去用”的程度。

