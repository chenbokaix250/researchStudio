# Claude Managed Agents: 构建生产级AI Agent

**视频来源**: Anthropic官方 | Code with Claude London  
**时长**: ~37分钟  
**视频链接**: https://www.youtube.com/watch?v=19HDQ9HppOA  
**整理时间**: 2026-06-01

---

## 一、Claude API 演进历程

| 阶段 | 时间 | 产品 | 特点 |
|------|------|------|------|
| 第一代 | 2023 | Messages API | 原始模型访问，开发者自己实现context管理、agent loop、compaction等所有原生功能 |
| 第二代 | — | Agent SDK | 引入了Claude Code能力，开发者仍需自行管理hosting和scaling |
| 第三代 | — | Claude Managed Agents | 全托管harness，提供sandboxing、observability、tool runtime，自动处理compaction/caching等 |

**驱动演进的原因**: 模型智能度提升 → Agent能处理更复杂任务 → 所需的原生操作（context管理、tool调用）复杂度大幅上升

---

## 二、核心架构设计：Brain & Hands 分离

### 设计理念
- **传统模式**: Agent loop 和 tool execution 紧耦合（同在一个容器/进程内）
- **Claude Managed Agents**: 将"大脑"（思考、决策）与"手"（执行）解耦

### 关键优势

1. **安全性提升** — Agent无法直接访问credentials，通过加密的vaults存储分离
2. **延迟大幅降低** — 不再需要为每个session预spin up完整容器  
   → P95 TTFT（Time to First Token）降低 **>90%**
3. **可靠性** — 容器重启不影响agent loop，session状态独立维护

---

## 三、三大核心资源

### 1. Agent（大脑）
定义agent的persona和capabilities：
- **模型选择**（如 Claude Opus 4.7）
- **System Prompt**（如 SRE agent prompt）
- **MCP Servers / Skills**
- **Tools**（如 get_metrics, get_recent_deploys, get_diff）

### 2. Environment（手）
Agent执行操作的空间/容器：
- 支持 Anthropic 托管基础架构
- **新发布**: 支持Bring Your Own Container / Compute（伦敦场发布）
- **网络控制**: allowed list细粒度网络访问控制
- **MCP Tunnels**: 在私有网络运行MCP服务器

### 3. Session（连接器）
将Agent和Environment绑定，实现：
- 事件流（而非tokens in/out）
- 会话持久化（关闭页面/laptop后会话状态保留）
- 支持webhook触发恢复会话

---

## 四、Event-Driven 架构（关键概念）

### 传统Request-Response vs Managed Agents Event Model

```
传统: user → request → response (token stream)
Managed Agents: user → events appended to session log
```

**Events类型**:
- `user message`
- `agent tool call`
- `agent response`

### 为什么重要
1. **可观测性**: 每个event可独立记录日志
2. **会话恢复**: 容器故障 → 重新spin容器 → 从event log恢复，无需重启整个agent loop
3. **流式体验**: 用户实时看到tool calls执行过程，而非等待完整response

---

## 五、Session 状态机

```
idle → running → rescheduling（重试）/ terminated（失败）
```

- **idle**: 等待输入
- **running**: Agent正在处理
- **rescheduling**: 需要重试（如API临时失败）
- **terminated**: 会话结束

**webhook驱动**: 外部事件可触发会话状态转换，Agent可监听webhook实现自动化

---

## 六、Local Tools 实现模式

视频演示中，tools以JSON本地定义，通过`load_tools()`注册：

```python
tools = [
    {"name": "get_metrics", "description": "...", "parameters": {...}},
    {"name": "get_recent_deploys", ...},
    {"name": "get_diff", ...}
]
```

→ 实际生产中可替换为DataDog等监控系统的API client，保持相同wire protocol

---

## 七、Context Engineering（实践重点）

**核心观点**: 给Agent越多上下文数据，Agent越强大

视频中演示的SRE Agent案例：
- 上传metrics日志文件
- Agent分析日志 + 调用工具 → 定位到"database pool exhaustion"
- 进一步定位到Alice的commit引入的query问题

开发者主要工作: 管理上传哪些文件、如何组织context、哪些tools要给Agent

---

## 八、高级功能（Beyond Basics）

### Subagents / Multi-Agent
- Orchestrator agent管理subagents
- Subagents有独立context windows
- 实现并行化 + 更好的context管理

### Memory + Dreaming
- **Memory**: 让Agent记住用户偏好、纠错历史
- **Dreaming**: Claude自动分析memory logs，决定保留什么、自主管理记忆

### Outcomes（目标导向）
- 定义rubric（评估标准）而非具体步骤
- Agent自主决定调用哪些tool来达成目标结果

### Vaults（安全凭证管理）
- credentials加密存储在独立endpoint
- 按用户/按会话维度管理
- 依赖brain/hands分离架构

### 其他特性
- Webhooks（事件驱动Agent）
- 细粒度权限策略
- MCP Server控制（伦敦场发布）
- Console Agent Builder（图形化观测dashboard）

---

## 九、演示案例：SRE Incident Response Agent

### 问题场景
- P99 latency是baseline的10倍

### Agent执行流程
1. 调用 `sandbox` tool查看日志
2. 调用 `get_recent_deploys` 查看部署记录
3. 分析排除其他原因
4. 定位根因：Alice的commit引入的query导致DB pool资源耗尽
5. 给出修复建议

### 可扩展方向
- 进一步给Agent提供Claude Code访问权限
- Agent可进入codebase、提PR、完成从发现到修复的完整闭环

---

## 十、关键设计原则总结

| 原则 | 说明 |
|------|------|
| 分离关注点 | Brain/Hand分离，Agent定义 vs 执行环境分离 |
| 事件优先 | 会话以event log而非token流为核心 |
| 云原生持久化 | Agent loop在服务端运行，session状态跨客户端保持 |
| 安全默认 | Vaults加密、sandboxing、网络控制 |
| 可组合性 | Skills、MCP Servers、自定义容器自由组合 |

---

**标签**: #Anthropic #Claude #AI-Agent #LLM-Applications #Production-AI