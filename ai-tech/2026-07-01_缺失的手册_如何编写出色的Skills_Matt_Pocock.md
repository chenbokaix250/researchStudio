# 缺失的手册：如何编写出色的Skills - Matt Pocock

**日期**: 2026-07-01  
**来源**: YouTube（中文同传）  
**链接**: https://youtube.com/watch?v=BqF6PUAXY1M

---

## 视频概述

这是 Matt Pocock 在 AI Engineer World's Fair 上的演讲（因家庭原因改为线上），主题是如何编写优质的 AI Agent Skills。核心观点：当前开发者处于"技能地狱"（Skill Hell）——有大量免费技能可用，但无法判断好坏，也不知道如何让它们协同工作。

---

## 核心内容：技能检查清单（4大维度）

### 1. 触发机制（Trigger）

**关键决策：用户触发 vs 模型触发**

| 类型 | 特点 | 代价 |
|------|------|------|
| **模型触发** (Model Invoked) | 描述自动进入 Agent 上下文，Agent 可自主调用 | 增加上下文负载（Context Load）；Agent 可能不按预期调用 |
| **用户触发** (User Invoked) | 需用户手动调用，描述默认不进入上下文 | 增加用户认知负载（Cognitive Load）——用户需熟悉所有技能 |

**Matt Pocock 的选择**：优先用户触发技能。理由：
- 模型触发有不可预测性（Agent 可能拒绝调用正确技能）
- 避免"技能是否被正确调用"的评估难题
- 保持 Agent 上下文精简

> 技巧：`disable_model_invocation: true` 可将技能设为纯用户触发

---

### 2. 内部结构（Structure）

**两个核心单元**：
- **Steps（步骤）**：逐步执行的操作流程
- **Reference（参考）**：支撑步骤的辅助信息

**核心原则**：让 `skill.md` 尽可能小

**分支处理技术**：如果技能有多个分支（不同使用路径），将仅在某分支使用的参考材料移到外部，通过上下文指针（Context Pointer）引用。

**示例**：`two PRD` 技能（创建产品需求文档）：
- 3 个步骤：查找相关上下文 → 确认测试接缝 → 编写 PRD
- 2 个参考：什么是测试接缝 + PRD 模板
- 只有一条路径，所有参考都在主文件中

`domain modeling` 技能（更新词汇表 + 创建 ADR）：
- 2-3 个分支
- ADR 模板和 context.md 模板移到外部，不在主文件中

---

### 3. 引导技术（Steering）

**核心技巧：Leading Words（引导词）**

引导词是承载大量意义的短词/短语，Agent 会在推理过程中重复它，从而改变行为。

**示例**：
- 问题：Agent 习惯"分层编码"（先写完所有数据库层，再写所有 API...）
- 引导词：`vertical slice`（垂直切片）
- 效果：Agent 在推理 trace 中重复"thin vertical slice"，开始采用更符合人类习惯的开发方式

**如何验证有效**：在推理 trace 中观察 Agent 是否重复了你的引导词。

**另一个技巧：隐藏未来目标**
- 问题：Plan Mode 中"问澄清问题"步骤总是做得很敷衍（因为 Agent 知道最终要创建计划）
- 解决：将"问澄清问题"拆成独立技能（`grill with docs`），完全隐藏后续的"创建计划"步骤
- 效果：Agent 在该步骤上投入更多精力

---

### 4. 修剪（Pruning）

**三种失败模式**：

1. **重复自己（Don't Repeat Yourself）**
   - 每个部分保持单一事实来源
   - 即使在参考材料中也要避免重复

2. **沉积物（Sediment）**
   - 多人协作积累的无关内容
   - 解决：检查结构，将无关材料移到正确分支或删除

3. **空操作（No-ops）**
   - 看起来在做某事但实际不影响 Agent 行为的段落
   - **验证方法**：删除该段落，观察 Agent 行为是否变化——如果没变化，就是 no-op

---

## 完整检查清单

| 维度 | 检查点 |
|------|--------|
| **触发** | 是用户触发还是模型触发？上下文负载 vs 认知负载如何取舍？ |
| **结构** | skill.md 是否足够小？分支参考是否移到外部？steps 和 reference 是否分离？ |
| **引导** | 是否有强力引导词？Agent 推理 trace 中是否重复了引导词？当前步骤是否投入足够精力？ |
| **修剪** | 是否有重复？是否有沉积物？是否有 no-ops？ |

---

## 资源

- Matt Pocock's Skills Repo: `mattpocock/mattpocock`
- 相关技能：`writing great skills`（内含完整检查清单）
- Newsletter: aihero.dev
- 即将发布：AI Coding Crash Course

---

*由 Hermes Agent Whisper语音转文字 + 整理*
*原始转录长度：6732 字符
