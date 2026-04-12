# AI Agent Harness Engineering 研究报告

> **来源**: @servasyy_ai (huangserva) - X/Twitter
> **原文链接**: https://x.com/servasyy_ai/status/2038213141083947053
> **整理日期**: 2026-03-30
> **阅读量**: 6.6万

---

## 核心观点

**2026年，Agent 的胜负手不在模型，在 Harness！**

顶级模型差距已很小，竞争优势在于"模型外面那一圈东西"——**Harness Engineering**，即给 Agent 搭一套"操作系统"。

---

## 一、什么是 Harness？

### 1.1 概念类比

| 组件 | 对应 | 作用 |
|------|------|------|
| **模型** | CPU | 原始算力 |
| **上下文窗口** | 内存 | 临时存储，关机即失 |
| **Agent** | 应用程序 | 跑在上面的任务执行者 |
| **Harness** | 操作系统 | 让一切稳定、持续、大规模运行 |

> 没有操作系统，CPU 再猛也只是一块芯片，你总不能对着芯片敲键盘。
> 没有 Harness，模型再聪明也只是聊天框。

### 1.2 Harness 解决的问题

| 问题 | Harness 解决方案 |
|------|------------------|
| 长任务中忘记上下文 | 记忆治理 |
| 写垃圾代码没人拦 | 架构约束（linter + CI）|
| 犯错不自知 | 评估闭环（独立评估器）|

---

## 二、为什么 2026 年突然火了？

### 2.1 模型够强了

- 2024年大家卷"谁的模型更聪明"
- 2026年顶级模型差距已很小（Claude vs GPT 同题分数差不了几点）
- 但让它们**连续干8小时**，差距就出来了

### 2.2 瓶颈转移

**OpenAI Codex 团队的数据**：
- 5个月，100万行代码
- **零手写**
- 瓶颈从"模型能不能写代码" → "人类来不来得及审查代码"

> 模型产出速度已超过人类审查速度。这时候优化模型有什么用？
> 该优化的是审查流程、质量把控、架构约束 —— 这就是 Harness 要干的事。

---

## 三、三根支柱

### 3.1 评估闭环（Anthropic 强调）

**核心思想**：Agent 不能自己给自己打分。

| 传统做法 | Harness 做法 |
|----------|--------------|
| 实习生写完报告自己评价"还行吧" | 独立评估器打分 |
| 看看代码就打分 | Playwright 实际操作产品测试 |

**评估驱动开发 = TDD 的 Agent 版**
> 先定义"做得好"，再让 Agent 做，做完由独立评估器打分。

**案例：Opus 4.5 的"创造性失败"**
- 航班预订测试中，Opus 4.5 发现政策漏洞，找到比标准答案更好的解法
- 但评估器判它"失败"——因为评估器没预料到这种创造性解法
- **教训**：评估闭环不只是检查 Agent，也在检查评估本身

**数据验证**：
- CORE-Bench：Opus 4.5 初始得分 42%
- 修复评分 bug、放宽 scaffold 限制 → **95%**
- 很多时候不是模型不行，是 Harness 有问题

**成果**：
- Anthropic 用这套方法，6小时、200美元，让 Agent 做出完整游戏

---

### 3.2 架构约束（OpenAI Codex 看家本领）

**核心思想**：靠 linter 和 CI 机械执行，不是靠文档。

> 你跟实习生说"代码要分层"，他点头说好，转头就把 UI 逻辑写进数据库层。
> **靠嘴说没用。**

**OpenAI 的分层架构**：
```
Types → Config → Service → UI
（每一层只能依赖上一层，不能反向）
```

- 规则写在 linter 里自动检查
- **Linter 本身也是 Codex 生成的** → Agent 给自己写规矩，自己遵守

**Martin Fowler 评价**：
> "增加信任和可靠性，需要约束解空间。这意味着放弃一些'生成任何东西'的灵活性。"

**约束越多反而越可靠**：

| 项目 | 改动 | 效果 |
|------|------|------|
| LangChain | 只改 Harness，模型不变 | Terminal Bench 2.0: 52.8% → 66.5% |
| Vercel | 删掉 80% Agent 工具 | 步骤更少、速度更快、效果更好 |

> **工具越少反而越好用**——这个结论在 Agent 领域被反复验证。

---

### 3.3 记忆治理（PrismerCloud）

**问题**：多 Agent 共享知识库，一个 Agent 的幻觉会污染所有 Agent。

**解决方案**：进化引擎

```
信号（Agent经验）→ 验证 → 基因（验证后的知识）→ 实际效果优化 → 技能涌现
```

> 基因 = 被验证过、确实有效的知识。没验证的不算。

**效果对比**：
| 方案 | 效果 |
|------|------|
| 3行 prompt + 记忆系统 | ≈ 200行精心编写的专家 prompt |
| 记忆系统持续进化 | prompt 写完就固定 |

> 记忆系统做得好，你根本不需要写那么复杂的 prompt。Agent 自己会越跑越好。

---

## 四、熵对抗（补充）

**问题**：Agent 系统跑久了会自然腐化（文档过期、架构被绕过、知识库堆过时信息）

**OpenAI 的做法**：
- 定期跑"重构 Agent"扫描文档不一致和架构违规
- **Agent 遇到问题 → 修 Harness，不是修 Agent**

> 当 Agent 遇到困难时，把它当作信号：找出缺什么，然后反馈到代码库中，始终让 Codex 自己写修复。

---

## 五、谁在做这件事？

### 5.1 开源项目（已可用）

| 项目 | Stars | 特点 | 适用场景 |
|------|-------|------|----------|
| **LangChain DeepAgents** | 115k | 最接近通用版 Claude Code，支持任意模型 | 起步门槛最低 |
| **DeerFlow 2.0** | 39k | 字节跳动出品，SuperAgent Harness，基于 LangGraph | 多 Agent 操作系统 |
| **OpenHands** | - | SWE-bench Verified 77.6%，模型无关，MIT协议 | 代码 Agent |
| **SWE-agent** | - | Princeton/Stanford，NeurIPS 2024 | 评估驱动极致实践 |
| **Goose** | - | Block 出品，Apache 2.0，通用 on-machine Agent | 依赖安装、测试、文件操作 |
| **PrismerCloud** | - | 记忆治理，进化引擎 | 多 Agent 共享知识 |
| **Cognee** | - | 知识图谱驱动记忆，6行代码接入 | 语义连接理解 |

### 5.2 商业公司实践（方法论可学，代码拿不到）

| 公司 | 产品 | 核心贡献 |
|------|------|----------|
| Anthropic | Claude Code + Agent SDK | 评估驱动方法论标杆 |
| OpenAI | Codex | 架构约束极致实践，5个月百万行零手写 |

---

## 六、关键教训：Build to Delete

**Rich Sutton 的"苦涩的教训"**：
> 长期来看，利用计算能力的通用方法总是会打败人类精心设计的特定方法。

**Agent 领域再次应验**：

| 公司 | 重构次数 | 周期 |
|------|----------|------|
| Manus | 5次 | 6个月 |
| LangChain | 3次 | 1年 |
| Vercel | 删掉80%工具 | - |

> **Build to Delete** —— 为删除而构建。
> 今天写的"聪明逻辑"，明天模型升级可能就不需要了。
> 架构必须模块化，随时准备撕掉重来。

**Phil Schmid 金句**：
> "竞争优势不再是 prompt，而是你的 Harness 捕获的轨迹。
> 每次 Agent 的成功和失败，都是训练下一代的数据。"

> Harness 跑得越久，积累的轨迹越多，Agent 就越强。这不是靠换模型能追上的。

---

## 七、三个阶段

```
┌─────────────────────────────────────────────────────┐
│              AI 工程的三层架构                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Layer 1: Prompt Engineering                       │
│  └─ 解决"说什么"                                    │
│  └─ 单次交互，给指令→得回答                          │
│                                                     │
│  Layer 2: Context Engineering                      │
│  └─ 解决"知道什么"                                  │
│  └─ 准备参考资料、历史记录、工具描述                  │
│                                                     │
│  Layer 3: Harness Engineering                      │
│  └─ 解决"怎么持续、稳定、大规模干活"                 │
│  └─ 评估闭环 + 架构约束 + 记忆治理                   │
│                                                     │
│  三层叠加，缺一层就会出问题                          │
└─────────────────────────────────────────────────────┘
```

**三层叠加的问题**：
| 缺失层 | 结果 |
|--------|------|
| 光有 Prompt 没有 Context | Agent 聪明但啥都不记得 |
| 加了 Context 但没有 Harness | 记得住事但没人管，迟早出乱子 |
| 三层都到位 | 才是能长期干活的角色 |

---

## 八、关键数据汇总

| 指标 | 数据 |
|------|------|
| OpenAI Codex 代码量 | 5个月，100万行，零手写 |
| CORE-Bench Opus 4.5 提升 | 42% → 95%（修复 Harness）|
| LangChain Terminal Bench 提升 | 52.8% → 66.5%（只改 Harness）|
| Vercel 工具删减 | 80%，效果反而更好 |
| PrismerCloud prompt 效果 | 3行 + 记忆 ≈ 200行专家 prompt |
| Anthropic 游戏开发成本 | 6小时，200美元 |
| 原文阅读量 | 6.6万 |

---

## 九、参考来源

- OpenAI: Harness Engineering
- Anthropic: Demystifying Evals for AI Agents
- Anthropic: Building Agents with Claude Agent SDK
- Phil Schmid (HuggingFace): The Importance of Agent Harness in 2026
- Martin Fowler (Thoughtworks): Harness Engineering
- LangChain: Agent Frameworks Runtimes and Harnesses

---

## 十、应用场景

- 构建 AI Agent 产品
- 代码自动化系统
- 多 Agent 协作平台
- 企业级 AI 工程化
- Agent 测试与评估体系

---

*整理时间: 2026-03-30*
*字数: 约3000字*