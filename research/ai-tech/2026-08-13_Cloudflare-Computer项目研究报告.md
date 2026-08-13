# Cloudflare Computer 项目研究报告

> **项目**: [cloudflare/computer](https://github.com/cloudflare/computer)  
> **来源**: GitHub Repo Clone  
> **研究日期**: 2026-08-13  
> **分类**: AI Tech  
> **标签**: Cloudflare, Durable-Object, FUSE, Agent, Workspace, Virtual-Filesystem, monorepo

---

## 一、项目概述

Cloudflare Computer 是一个**运行在 Durable Object 内的虚拟文件系统**，核心设计目标是为 AI Agent 提供一个持久的、可执行代码的工作空间。

项目状态：**PREVIEW ONLY** — 不适合生产使用，API 不稳定，设计可能变更。

---

## 二、核心架构

### 2.1 三层结构

```
┌─────────────────────────────────────────────────────────┐
│              Durable Object (DO)                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │  SQLite-backed VFS（权威状态，持久化）           │   │
│  │  tables: vfs_meta, vfs_nodes, vfs_dirents,     │   │
│  │          vfs_blobs, vfs_changes                 │   │
│  └─────────────────────────────────────────────────┘   │
│                         ↕ push/pull sync               │
│  ┌─────────────────────────────────────────────────┐   │
│  │  @cloudflare/computer (Workspace API)           │   │
│  │  workspace.fs  +  workspace.runtime             │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                         ↕ capnweb RPC
┌─────────────────────────────────────────────────────────┐
│  Sandbox（可插拔执行后端）                              │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │  Container   │  │  Worker Shell │  │ Worker JS   │  │
│  │  (FUSE+daemon)│  │  (just-bash)  │  │ (ES Module)  │  │
│  │  Full Linux  │  │  Fast,文本工具 │  │ 结构化JS执行 │  │
│  └──────────────┘  └──────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 2.2 核心组件

| Package | NPM 包 | 职责 |
|---|---|---|
| `packages/dofs` | `@cloudflare/dofs` | Durable Object SQLite VFS 实现，sync 协议构建块 |
| `packages/rpc` | `@cloudflare/computer-rpc` | capnweb 线缆类型，DO↔computerd RPC 共享代码 |
| `packages/computerd` | `@cloudflare/computerd` | 沙箱内 FUSE 挂载 + WebSocket RPC 服务端 |
| `packages/computer` | `@cloudflare/computer` | 顶层 Workspace API，DO 消费者入口 |
| `packages/computer-computerd-linux-x64` | — | 预编译 `computerd` Linux x64 Docker 镜像 |

---

## 三、Virtual Filesystem（VFS）

### 3.1 SQLite Schema 设计

DO 的 SQLite 中维护以下核心表（均以 `vfs_` 前缀避免与应用表冲突）：

| 表名 | 作用 |
|---|---|
| `vfs_meta` | schema 版本号 + 全局单调递增 `rev` 计数器 |
| `vfs_nodes` | inode 元数据（type, mode, mtime, rev, mount_root, 块哈希等） |
| `vfs_dirents` | 目录项（inode 间接引用，实现 O(1) rename 和 hardlink） |
| `vfs_blobs` | 内容块存储（hash → bytes 映射） |
| `vfs_changes` | 变更日志（驱动增量同步） |

**路径解析**：通过 `vfs_dirents` → `vfs_nodes` 的 inode 间接层，rename 为 O(1) 操作，hardlink 免费实现。

### 3.2 文件系统接口（workspace.fs）

兼容 Node.js `fs/promises` 风格，完全异步，操作在 DO 重启后持久化：

```ts
workspace.fs.writeFile("/workspace/notes/todo.md", content)
workspace.fs.readFile("/workspace/data/blob.bin")
workspace.fs.mkdir("/workspace/notes/daily", { recursive: true })
workspace.fs.readdir("/workspace/notes")
workspace.fs.rm("/workspace/notes/todo.md", { recursive: true })
workspace.fs.grep("TODO", "/workspace", { ignoreCase: true })
```

### 3.3 局限性

- **最大容量 ~10GB**（与 DO 存储共享）
- **不适合超大仓库**（FUSE 内存存放文件树，适用 Agent 级工作空间而非完整 monorepo）
- **重 I/O 有性能惩罚**（大文件顺序写入明显慢于原生磁盘，见性能章节）

---

## 四、Sync Protocol（同步协议）

### 4.1 双向增量同步

VFS 在 DO 和 Sandbox 两端各有一份副本，通过增量 revision 机制保持同步：

- **DO → Container（Push）**：每次 DO 侧写入产生新的 `rev`，Push 时发送该 rev 之后的所有变更，按路径合并（同一路径 5 次重写 = 1 次网络传输）。内容块通过 hash 去重，未持有的块才传输。
- **Container → DO（Pull）**：FUSE 写入即时产生变更记录，Pull 时分批（256 条/批）取回，防止内存爆炸。

### 4.2 典型 exec() 流程

```
1. Push:  DO 推送 (rev+1) 之后所有变更到 Container（合并后）
2. Hydrate: 懒加载的 stub 文件从 provider 获取并一起推送
3. Exec:   命令在 Container 内执行，FUSE 写入被捕获
4. Fetch:  DO 调用 fetchChanges 拉回 Container 新产生的变更
5. Diff:   DO 比对本地已有块，只请求缺失的 blob
6. Apply:  变更批量写入 DO SQLite（事务保证持久性）
```

### 4.3 capnweb RPC 接口

DO 与 `computerd` 之间通过 capnweb（Cap'n Proto over HTTP/WebSocket）通信，关键端点：
- `pushObjects` / `hasObjects` — 块内容传输
- `fetchChanges` — 拉取变更增量
- `fetchObjects` — 按需获取缺失块
- 预留给 `workspace.runtime.exec` 的调用通道

---

## 五、Runtime（可插拔执行后端）

`workspace.runtime.exec(source, { backend })` 是唯一执行入口。

| Backend ID | 源码类型 | 适用场景 |
|---|---|---|
| `container-shell` | shell 命令 | 完整 Linux 用户态、原生二进制、网络访问 |
| `worker-shell` | just-bash 命令 | 快速文本工具，无需 Container |
| `worker-javascript` | ECMAScript Module | 隔离的 JS 执行，结构化输入/输出，持久化相对导入 |

**Container 后端** 使用 `computerd`（一个 FUSE 挂载 + HTTP/WebSocket 服务进程），运行在 Cloudflare 的沙箱容器内。

**Worker 后端**（Shell / JavaScript）运行在 Dynamic Worker 内，通过 Workers RPC 直连 Workspace，无需第二个存储或同步往返。

### 生命周期管理

```ts
const handle = await workspace.runtime.exec(source, { id: "build-1", backend: "worker-javascript" });
await handle.kill();
const resumed = await workspace.runtime.getExec("build-1", { resume: "full" });
await workspace.runtime.disposeExec("build-1");
```

---

## 六、关键设计亮点

### 6.1 存储与执行分离

文件系统状态（SQLite）和执行环境（Container/Worker）完全分离，通过增量同步桥接。这使得：
- DO 可以随意重启，执行环境按需创建/销毁
- 多个后端可以挂载同一个 Workspace
- 执行结果通过 sync 写回 DO，持久化保证

### 6.2 Hardlink 与目录优化的 O(1) rename

通过 inode 间接层，目录 rename 只需更新 `vfs_dirents`，无需递归遍历子树。同一文件的多个 hardlink 共享一个 inode，修改只写一份 blob。

### 6.3 变更合并（Coalescing）

同一路径多次写入只产生一次网络传输（最新状态覆盖），避免频繁 small-write 场景（如 npm 安装中每个文件都重写）的往返开销爆炸。

### 6.4 MCP 支持

内置 [examples/mcp](examples/mcp) 示例，提供一个 Code Mode `code` 工具，背后是 durable workspace + Worker shell + 完整 Linux Container，支持 Agent 通过 MCP 协议调用。

---

## 七、性能数据

基准测试（来源：[docs/19_performance.md](docs/19_performance.md)）：

### computerd vs 磁盘（比率越低越快）

| 场景 | computerd vs tmpfs | computerd vs ext4 |
|---|---|---|
| stat 1000 文件 | 1.49x | **0.91x** ✓ |
| rm 1000 文件 | 2.56x | **0.66x** ✓ |
| mkdir tree | 1.01x | **0.74x** ✓ |
| find tree | 1.00x | **0.72x** ✓ |
| git init + commit | 9.56x | **0.72x** ✓ |
| npm init | **0.95x** ✓ | **0.95x** ✓ |
| write 64 MiB | 4.87x | 16.93x |
| npm install (完整) | 3.6x vs tmpfs | 2x vs ext4 |

**结论**：
- **computerd 在元数据密集型操作上优于磁盘**（stat, rm, mkdir, git init, npm init）
- **大文件顺序 I/O 明显慢于磁盘**（64 MiB write 慢 ~5-17x）
- **适合 Agent 小文件工作流，不适合大文件批处理**

---

## 八、Examples 示例生态

```
examples/
├── container/          Container 后端完整示例（HTTP surface）
├── worker-shell/       just-bash Worker 示例
├── worker-javascript/  ES Module Worker 示例
├── egress/             三种后端的 egress 策略对比
├── mcp/                MCP Server 示例（Agent → Computer）
├── think/              @cloudflare/think 聊天 Agent 终端
├── think-compare-runtimes/  Web UI 对比 Container vs Worker
├── tutorial/           Pandoc PDF 生成教程
├── artifacts/         生成 Worker 项目并发布到 Artifacts
└── assets/            AI 生成图片 + R2 分享链接
```

---

## 九、技术栈与依赖

| 领域 | 技术选型 |
|---|---|
| 持久化存储 | Durable Object SQLite（内置） |
| 文件系统 | FUSE（`computerd` 在容器内挂载） |
| RPC 协议 | capnweb（Cap'n Proto over HTTP/WebSocket） |
| 语言 | TypeScript（Workspace + RPC + dofs），Rust/C（computerd 二进制） |
| 包管理 | npm monorepo（workspace） |
| 容器 | Docker（computerd Linux x64 预编译镜像） |
| 代码质量 | Biome（lint + format） |
| Worker 运行时 | Cloudflare Workers（Dynamic Worker for shell/js 后端） |

---

## 十、局限性与已知问题

1. **Preview 状态**：API 不稳定，不适合生产
2. **存储上限 ~10GB**：受 DO 存储限制
3. **FUSE I/O 开销**：大文件顺序读写比真实磁盘慢 5-40x
4. **Container 重启丢失本地状态**：`computerd` 当前运行于进程级 DB，容器重启后需从 DO re-baseline
5. **arm64 FUSE 需手动修复链接**：预编译 binary 为 x64，arm64 主机需替换 libfuse 链接
6. **真实 FUSE 需要特权**：测试需要 `--privileged` Docker 容器或 `CAP_SYS_ADMIN`

---

## 十一、核心价值定位

```
传统 AI Agent:
  LLM + 提示词 + 有限上下文
  → 无持久状态，重启即失
  → 无真实执行能力，只能"建议"

Cloudflare Computer:
  Durable Object VFS + 可插拔执行后端
  → 持久文件系统（SQLite 持久化）
  → 真实 shell 命令 / JS 模块执行
  → 增量 sync，支持多人协作
  → 断点可恢复，重启不丢状态
```

**一句话总结**：Cloudflare Computer 将一个完整的、持久化的、带执行能力的工作空间，下沉到 Cloudflare Durable Object 的基础设施层面，让 AI Agent 从"能说不能做"变成"能说也能做"。

---

## 相关链接

- Repo: https://github.com/cloudflare/computer
- @cloudflare/computer: https://www.npmjs.com/package/@cloudflare/computer
- @cloudflare/dofs: https://www.npmjs.com/package/@cloudflare/dofs
- Cloudflare Agents SDK: https://www.npmjs.com/package/@cloudflare/agents
