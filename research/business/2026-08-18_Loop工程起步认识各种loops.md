# Loop 工程：起步——认识各种 loops

*原文标题：Loop engineering: Getting started with loops*

> 原文链接：https://claude.com/blog/getting-started-with-loops

*了解 Claude Code 团队如何定义智能体 loop，并附上从 turn-based 到 goal-based、time-based、再到 proactive loops 的进阶实用指引——以及何时使用哪一种。*

## 起步——认识 loops

最近大家都在谈论 loop engineering，或者叫"设计 loops"，来取代为你的编码 agent 写 prompt 这件事。如果你在 X 上花点时间想搞清楚 loop 到底是什么，你会看到很多种不同的说法。

在 Claude Code 团队，我们把 **loops 定义为：智能体不断重复工作循环，直到某个停止条件被满足**。我们按以下几个维度把 loops 划分为不同类别：

- 它们是如何被触发的
- 它们是如何被停止的
- 它们使用的 Claude Code 原语是什么
- 哪种任务最适合哪一种 loop

下文会覆盖主要的 loop 类型、各自的使用场景，以及如何在管理 token 用量的同时保持代码质量。并非所有任务都需要复杂的 loops；从最简单的方案起步、按需选用这些模式。

## **基于回合的 loops（Turn-based）**

- **触发方式**：用户的 prompt。
- **停止条件**：Claude 判断任务已完成，或需要补充上下文。
- **最适合**：不属于固定流程或排期的较短任务。
- **用量管理**：写明确的 prompt，并用 skills 加强验证，从而减少回合数。**

你每发一条 prompt，都开启了一个由你指挥每一回合的手动 loop：Claude 收集上下文、采取动作、复核自己的成果、必要时重复，然后给出回应。我们把这称为"智能体 loop"。

比如，让 Claude 创建一个点赞按钮：它会读你的代码、做修改、跑测试，然后交回一个它 *相信* 能用的东西。你再人工复核这份工作，写下一个 prompt。

你可以把验证步骤自动化——把你的手工核验流程编码成 `SKILL.md`，让 Claude 自己端到端地复核更多工作。（关于在 skills、hooks、subagents 之间选择做这类自动化的取舍，请参考我们的 [Claude Code 引导指南](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)。）

这套验证里还要包括让 Claude 能够"看"、"测量"或"交互"结果的工具或连接器。检查越量化，Claude 越容易自验。

例如，你可以在 `SKILL.md` 里这样写：

```
---
name: verify-frontend-change
description: Verify any UI change end-to-end before declaring it done.
---

Never report a UI change as complete based on a successful edit alone. Verify it the way a human reviewer would:

1. Start the dev server and open the edited page in the browser.

2. Interact with the change directly. For a new control (button, input, toggle): click it, confirm the expected state change, and screenshot before/after.

3. Check the browser console: zero new errors or warnings.

4. Use the Chrome Devtools MCP, run a performance trace and audit Core Web Vitals.

If any step fails, fix the issue and rerun from step 1 — do not hand back partially verified work.
```

## **基于目标的 loop（`/goal`）**

- **触发方式**：实时的手动 prompt。
- **停止条件**：目标达成，或达到最大回合数。
- **最适合**：具备可验证退出标准的任务。
- **用量管理**：设置明确的完成标准与显式的回合上限，例如"5 次之后停止"。

有时一个回合不够，尤其对更复杂的任务。智能体在能迭代时表现更好。你可以通过 `/goal` 定义"做完是什么样"来延长 Claude 持续迭代的时间。

当你定义了成功标准，Claude 就不用再自己判断"差不多就行"而过早结束。每次它想停下时，会有一个评估模型核验你的条件，把它推回工作直到目标达成，或者到达你定义的回合上限。

这就是为什么确定性的标准（如通过的测试数、达到某个分数阈值）格外有效。

例如：

`/goal get the homepage Lighthouse score to 90 or above, stop after 5 tries.`

## **基于时间的 loop（`/loop` 与 `/schedule`）**

- **触发方式**：指定的时间间隔。
- **停止条件**：你取消它，或工作完成（PR 合并、队列清空）。
- **最适合**：重复性工作，或与外部环境/系统对接。
- **用量管理**：用更长间隔，或基于事件而非时间触发。

有些智能体工作是重复性的：任务保持不变，只有输入在变。比如每天早上汇总 Slack 消息。其他工作依赖外部系统，而最简单的对接方式就是定时检查、对变化做出反应。比如一个 PR 可能持续收到代码评审或 CI 失败。

对于这类工作，你可以用 `/loop` 来让 Claude 按间隔重新跑某条 prompt。例如：

`/loop 5m check my PR, address review comments, and fix failing CI`

`/loop` 运行在你的电脑上，所以关机它就会停止。你可以通过 `/schedule` 创建一个 routine 把 loop 搬到云端。

## **主动型 loops（Proactive）**

- **触发方式**：事件或排期，无实时人工介入。
- **停止条件**：每个任务在目标达成时退出；routine 本身持续运行直到你关掉它。
- **最适合**：边界清晰、重复性的工作流：bug 报告、issue triage、迁移、依赖升级等。
- **用量管理**：让 routine 路由给小而快的模型，把判断类工作交给最强模型。

上面这些原语，连同 Claude Code 的其他特性如 **auto mode** 和 **dynamic workflows**（研究预览），可以组合成用于长时工作的 loop。

例如，要处理流入的反馈，你可以这样组合：

- **`/schedule`**（研究预览）跑一个 routine，检查新报告
- **`/goal`** 定义"完成是什么样"，并用 **skills** 记录怎么验证
- **Dynamic workflows** 编排智能体，对每个报告 triage、修复、并复查修复
- **Auto mode** 让 routine 不必停下来请求权限

把它们拼到一起，一条 prompt 大致像这样：

`/schedule every hour: check #project-feedback for bug reports. /goal: don't stop until every report found this run is triaged, actioned, and responded to. When fixing a bug, use a workflow to explore three solutions in parallel worktrees and have a judge adversarially review them.`

## **维持代码质量**

loop 的产出质量取决于围绕它的系统。设计这套系统时：

- **保持代码库本身整洁**：Claude 会遵循你代码库里现有的模式与约定。
- **给 Claude 一种自验方式**：用 [skills](https://code.claude.com/docs/en/skills) 把"你和团队眼中的好"编码进去。
- **让文档触手可及**：框架与库的文档都跟有最新的最佳实践。
- **用第二个 agent 做代码评审**：一个拥有新上下文的评审者会更少偏见，也不受主 agent 推理路径的影响。你可以用内置的 `/code-review` skill，或 GitHub 上的 [Code Review](https://code.claude.com/docs/en/code-review)。写代码的 loops 需要检查代码的 loops —— 请见 [Anthropic 如何守护 AI 原生 SDLC](https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle)。

当个别结果不达标时，不要止步于修这一次，而是把它编码进系统，让未来所有迭代都受益。

## **管理 token 用量**

要管住 token 用量，loops 需要清晰的边界：

- **为任务选对原语和模型**：小任务不需要多个 agent 或 loop。一些任务用更便宜、更快的模型就够。
- **定义清晰的"成功"与"停止"标准**：具体说清楚"做完是什么样"，让 Claude 更快到达解（但又不能太早）。
- **大规模跑之前先试运行**：Dynamic workflows 可能拉起上百个 agent。先用一小块工作评估用量。
- **把确定性的工作交给脚本**：跑脚本比一步步推理便宜。比如一个 PDF skill 可以发布一个表单填写脚本，每次 Claude 直接跑它，而不是每次重新推导代码。
- **不要按比你所需更高的频率跑 routine**：让轮询间隔和你观察对象的变化节奏匹配。
- **复查用量**：`/usage` 命令按 skills、subagents、MCP 拆分最近用量；不带参数的 `/goal` 显示回合数与已用 token；`/workflows` 显示每个 agent 的 token 用量，你可以随时停掉某个 agent。

你的 [模型与 effort level](https://claude.com/blog/claude-model-and-effort-level-in-claude-code) 选择，是 loop 成本最大的几个杠杆之一。

## **起步指南**

总结一下：

| Loop 类型 | 你移交的是 | 何时使用 | 选用 |
|---|---|---|---|
| Turn-based | 验证环节 | 正在探索或决策 | 自定义验证 skills |
| Goal-based | 停止条件 | 你清楚"完成是什么样" | `/goal` |
| Time-based | 触发器 | 工作发生在你的项目之外、按时排期 | `/loop`、`/schedule` |
| Proactive | prompt | 工作是重复且边界清晰的 | 以上全部 + dynamic workflows |

要上手 loops，先看看你已经在做的事。挑一件你是瓶颈的任务，问自己能移交哪一块：你能不能写出验证检查？目标是否够清晰？工作是否按排期抵达？

有了想法之后，把 loop 跑起来，观察结果——它在哪里卡住、哪里过度推进——不要害怕对它反复迭代。

更多信息，请阅读 Claude Code 文档中的 [并行运行 agent](https://code.claude.com/docs/en/agents)、[loop](https://code.claude.com/docs/en/goal)、[schedule](https://code.claude.com/docs/en/routines)、[goal](https://code.claude.com/docs/en/goal) 与 [dynamic workflows](https://code.claude.com/docs/en/workflows#orchestrate-subagents-at-scale-with-dynamic-workflows) 章节。想让你的检查在多次会话间可复用，请见 [Building verification loops in Claude Code with skills](https://claude.com/blog/building-verification-loops-in-claude-code-with-skills)。

*本文由 Delba de Oliveira 与 Michael Segner 撰写。*