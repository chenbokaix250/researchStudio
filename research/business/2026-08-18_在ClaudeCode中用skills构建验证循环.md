# 在 Claude Code 中用 skills 构建验证循环

*原文标题：Building verification loops in Claude Code with skills*

> 原文链接：https://claude.com/blog/building-verification-loops-in-claude-code-with-skills

如何把你手工做的检查转化为 skills，让 Claude 闭合自己的反馈循环。

大多数 [智能体编码](https://claude.com/blog/introduction-to-agentic-coding) 会话遵循一个循环：你提出一个修改，Claude 收集上下文、采取动作、验证结果，必要时再回头收集更多上下文。

验证是 agent 在回应前检查自身工作的方式。Claude 已经能从你代码库中的确定性信号里做一部分这件事——包括类型检查器、linter、测试、运行时错误。Claude 推断不出来的部分，就变成了你手工检查某个功能时要做的事。

然而，这些手工步骤可以被转化成验证循环。在 [Claude Code](https://claude.com/product/claude-code) 中，验证循环是一个迭代过程：Claude 检查并尝试修复自己的工作。

![agentic loop 示意图：1. 收集上下文，2. 采取动作，3. 验证结果。](*智能体循环：1. 收集上下文，2. 采取动作，3. 验证结果。*)

本文会覆盖最常见的验证循环类型，并向你展示我们在 Anthropic 内部用的方式。接下来我们会说明如何把你已经在做的手工检查编码成 skills，让 Claude 能够闭合自己的反馈循环，你也能在它迭代时去做别的事。

如果你是 agent loop 的新手，请从 [Getting started with loops](https://claude.com/blog/getting-started-with-loops) 开始。

## 什么是验证循环？

验证循环是一种重复的周期：AI agent 自查其工作——跑测试、跑 linter、或执行自定义检查——并修复失败的部分再继续。在 Claude Code 中，验证循环可以打包成 skills，这样每个会话都会自动应用同一套检查，而不再依赖人记住它们。

## 内置的验证循环

在动手设计自定义验证循环之前，了解 Claude 对多种验证循环的内置支持会很有帮助。常见功能与方法包括：

- **`/verify` skill**：构建、运行、观察你应用中的改动。
- **工具链**：Claude 力争捕获并处理你提供的任何工具（如 linter）所产生的错误码与告警。一个好习惯是在 `CLAUDE.md` 中列出你准确的 build 与 test 命令，避免 Claude 自行推断。
- **Code Review（研究预览）**：一个托管的多 agent 服务，会在你启用的仓库中为 PR 自动跑一轮评审。你可手工修复发现并推送，或者通过在发现条目下评论 `@claude` 来闭环（前提是你已经设置并配置好了 GitHub Actions，下文）。
- **GitHub Actions**：定义一个调用 Claude 并附带 verification skill 的 job，同样的检查会在每次 push 或 PR 时自动触发。
- **Spec validation**：一个帮助核对每一项变更是否违反仓库内 Markdown 规范、并尝试修复的 skill。
- **Rubrics in Claude Managed Agents（beta）**：一个托管的智能体服务，允许你用单独的 grader agent 把产出与 rubric 对照验证。失败会自动回流重做。

## 编写验证循环

当你已有项目，并发现自己在 Claude 每次实现新功能时都要做同样的几处小修正时，就是把这些步骤转化成自定义验证循环的时候了。第一步是先写下来：把你每次都会做的那点事情一项一项写清楚。

对启动新项目、需要想清楚"这个项目应该如何运作"的场景也一样——先用日常英语把"最佳实践版本"写出来，就像你第一天交给一位新同事那样。

如果你自己难以说清验证检查本身，可以先让 Claude 给出最佳实践版本，再从那里改。你的版本大概率会在几个具体点上不一样，而这些差异正是你最该捕捉的。

**小贴士**：要纳入这里的检查不一定要是定性的。"拒绝任何不附带 backfill 步骤就删除列的迁移脚本"——这是一个通用 linter 抓不到、但项目自定义 linter 能抓到的确定性规则。任何你一直在靠手工强制执行的检查，都值得捕获为一条 loop。

## 把它做成一个 skill

把重复步骤编码进验证循环最常见的方式是写成一个 [skill](https://claude.com/blog/complete-guide-to-building-skills-for-claude)，而创建 skill 最快的方法是安装 `skill-creator` 插件，让 Claude 采访你：

举例：

`/skill-creator Create a skill for verifying frontend changes end-to-end. Interview me about my workflow.`

你也可以手写一个 skill，把一个 markdown 文件放进项目里的 `.claude/skills/` 目录。最简形式的 verification skill 只需几行 frontmatter 加一段正文：

```
# .claude/skills/verify-log-hygiene/SKILL.md
---
name: verify-log-hygiene
description: Check that error logs include the request ID and never
include the request body. Use when the diff touches error handling
or logging.
allowed-tools: [Read, Edit, Grep]
---
Read the error-handling paths in the current diff.

For each log call on an error path, confirm it includes the request ID
and does not pass the request body, headers, or any user-supplied payload.

Report each violation with file:line, then fix it: add the request ID
where it's missing and strip the payload from the log call.
```

完整的 schema 与它背后的设计理念，请见我们的 [Skills 构建完整指南](https://claude.com/blog/complete-guide-to-building-skills-for-claude)。

## 让检查匹配它运行的场景

下一步要决定的是验证循环的触发方式：独立触发、内嵌、串联，还是与 PR 挂钩。

### 独立触发（Standalone）

你在产出物已经存在之后主动调用它。独立 skill 适用于那些跨场景、但每次变更都不必触发的检查：pre-commit 的安全扫描、PR 前的可访问性审计、整库的 license header 校验。任何你想在很多工作流里都能用、但又不想每次代码改动都触发的东西。

代价是，每次调用仍然是一个你必须记得去做的事。当你发现自己每次改完都跑这条时，就意味着你已经"超出"了独立模式——这条流程已经赢得了一个固定的归宿：内嵌或者串联。

### 内嵌（Embedded）

作为产出 skill 的一部分自动触发。检查只属于某个特定工作流，而该工作流会在你不必开口的情况下自动跑它。

最简形式就是在产出 skill 的正文末尾加一行：

```
# .claude/skills/scaffold-component/SKILL.md
---
name: scaffold-component
description: Scaffold a new React component under src/components/, including the component file, its co-located test, and an index export. Use when the user asks to create a new component.
allowed-tools: [Read, Write, Edit, Bash, Glob]
---

Given a component name (PascalCase), create the following under `src/components/<Name>/`:

1. `<Name>.tsx`: function component with a typed props interface and a default export.
2. `<Name>.test.tsx`: React Testing Library test that renders the component and asserts it mounts without throwing.
3. `index.ts`: re-export the default and any named exports.

Follow the patterns in `src/components/Button/` as the reference. Match the import alias style (`@/components/...`) used throughout the codebase.

After creating the component file, run eslint on it and
address any errors before reporting completion.
```

通过在一个新任务上调用 skill、确认新增的检查作为输出的一部分运行了，来验证内嵌生效。如果没有，那说明 skill 的 description 或之前的指令没有把追加的检查拉进来。

内嵌只对"你能改的"skill 适用：要么是你自己写的，要么是项目级安装、`SKILL.md` 文件由你掌握的。内置 skill 与由插件管理的 skill（升级时会被覆盖的那种）则不能用这个模式——对这些，要用串联。

跨工作流的检查不要用内嵌——这些场景更适合独立触发，这样你可以在任何上下文里调用它。

### 串联（Chained）

一个 skill 在结束时调用另一个 skill，多个带验证的交接端到端运行。

Anthropic Claude Code 团队的成员在日常工作中就在使用这个模式：`/code-review` 找 bug，`/simplify` 清理 diff，`/verify` skill 确认端到端行为，如果改动涉及 UI，再用一个自定义 `/design` skill 比对 `DESIGN.md` 里的设计规范。

串联也是给那些你无法修改的 skill 加上验证的方法：写一个自定义的 wrapper skill，让它先调用原 skill，再调用你的验证 skill，正如下图所示：

```
# .claude/skills/safe-refactor/SKILL.md
Run /simplify on the current diff first.
When /simplify finishes, invoke /verify-no-public-api-changes.
```

原本只是习惯（"我每次都在 /simplify 之后跑 /verify"）变成了契约（"/simplify 完成后一定跑 /verify"）。这条链自己就能跑完整个开发循环。只有当某件事升级回来找你时，你才需要介入。

当步骤之间相互独立、你有时候只想跑其中某几步时，可以不用串联——串联是用灵活性换自动化。串联验证循环会增加 token 消耗，因此最好在大规模铺开前先测试一下这些 loops。

### 每次 PR 都跑

一旦这条链在你自己的改动上跑顺了，相同的流程也可以在每个 PR 上跑。一位队友的改动和你的一样会通过同一套门槛——不管他们有没有记得调用这条链。基础设施和你已经写好的链子是同一种东西，再往前走一步：相同的 skills、相同的 rubrics、相同的标准，都不再依赖作者是否记得。

在这里，验证循环不再只是"个人基础设施"，而变成了 [团队基础设施](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start)。你写下来、原本只是为了给自己每周省两分钟的检查，现在每周为团队里每位成员每次改动都省两分钟。在链子还没稳定时不要急于在 PR 级别开闸——每调整一次都会变成一次团队可见的事件。

一旦流程跑顺了，你就准备好扩展你的 loop 工程实践。验证循环的创建过程是一致的，无论你自动化的是什么、运行在什么环境里：

- 挑出你这周最常做的那项手工后续检查。
- 先试着用内置的 `/verify` skill，看看它是否对你的流程有帮助。
- 用日常英语把流程写出来，就像你第一天交给新同事那样。
- 把它交给 `skill-creator`，或者自己把 markdown 文件放进 `.claude/skills/`。
- 在新任务上调用它，确认检查作为输出的一部分运行，必要时迭代。
- 尝试 skill 串联，端到端地搭起验证流。

你能为 Claude 多编码一分，Claude 的回答就越可能一上来就贴近你想要的样子。那些你不再需要手动打补丁的修正，把你的注意力腾给了那些没有 skill 能替你写下来的、独属于你的工作。

***[马上在 Claude Code 中开始用验证循环](https://www.anthropic.com/product/claude-code)。***

*本文由 Claude Code 团队成员 Delba de Oliveira 撰写。*