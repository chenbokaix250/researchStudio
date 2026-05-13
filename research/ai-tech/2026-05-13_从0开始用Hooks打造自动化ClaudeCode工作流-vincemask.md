# 从 0 开始：用 Hooks 打造自动化 Claude Code 工作流

> **来源**: Vince 聊开发 (@vincemask)  
> **发布时间**: Wed May 13 07:04 2026  
> **原始链接**: https://x.com/vincemask/status/2054457804057100405  
> **平台**: X (Twitter)

---

你让 Claude Code 写功能、补测试、格式化文件，最后顺手提交。
它功能写了，测试也补了大半，格式化跑了两个文件，但偏偏漏了一个。然后它很自然地告诉你：“搞完了。”
你一看：没提交，格式也没完全对齐。
但这些问题，其实不该靠你事后检查。在 Claude Code 里，它们都可以配置成自动流程。
这就是 Hook 存在的理由。

## Hook 是什么
Claude Code hooks 是在 Claude 生命周期的固定节点自动执行的 shell 命令。不需要你给 Claude 下任何指令，Hook 就已经跑完了。
Claude 可能不跑格式化工具。挂在 PostToolUse 上的 Hook 会在每次文件编辑后跑 Prettier。
Claude 可能忘了通知你。挂在 Notification 上的 Hook 每次 Claude 需要你介入时都会弹窗。
Hook 把行为从 Claude 的判断里抽出来，放到你的项目规则里。代码质量、通知、安全检查。这些最要紧的事应该放在 Hook 里，不是 prompt 里。
GitButler 的指南：从三个开始：PostToolUse 自动格式化、PreToolUse 拦截危险命令、Stop 桌面通知，覆盖最广，上手最容易。

## 先看这 5 个生命周期事件
Claude Code 有 20多个生命周期事件，SessionStart 到 SessionEnd。不用全记。下面 5 个是实际工作中真会用的：
PostToolUse：Claude 用完工具后触发。自动格式化、跑 linter、记变更日志。
PreToolUse：Claude 调工具之前触发，可以拦截。保护敏感文件（.env、package-lock.json）、阻止危险命令、在 Claude 写任何东西之前卡一刀。
Notification：Claude 需要你关注时触发。弹桌面通知，你不用盯着终端，该干嘛干嘛。
Stop：Claude 回复结束时触发。跑测试、跑 CI、自动提交——Claude 说「搞完了」之后自动执行。
SessionStart：会话启动或恢复时触发。压缩（compaction）之后重新灌上下文，或者加载环境相关的提醒。
剩下事件（SubagentStart、WorktreeCreate、InstructionsLoaded 等）给更复杂的流程。先从上面 5 个上手。

## 三种值得用的 Hook type
除了标准的 shell 命令 Hook（"type": "command"），还有三种：
Prompt Hook（"type": "prompt"）把 Hook 的输入丢给 Claude 模型（默认用 Haiku）做判断，返回是/否。适合需要模型理解的场景，比如在 Claude 停止前检查是不是所有任务都完成了：
比写正则强。
Agent Hook（"type": "agent"）起一个子代理，能读文件、搜代码、跑工具，最多 50 轮。适合需要对照实际代码状态做判断的情况——比如 Claude 停之前确认测试确实过了。
HTTP Hook（"type": "http"）把事件数据 POST 到 URL，不跑 shell。适合团队审计日志、共享通知服务、webhook 集成。
多数场景 "type": "command" 够用。

## 怎么配 Hook
Hook 配置放在三个位置之一：
结构都一样：
Matcher 是正则，过滤触发条件。在 PostToolUse 和 PreToolUse 里匹配工具名称："Edit|Write" 在文件编辑后触发，"Bash" 在 shell 命令后触发，"mcp__github_.*" 在任意 GitHub MCP 工具调用后触发。
最简单的方式是用 /hooks 交互菜单。在 Claude Code 里敲 /hooks，选事件、设 matcher、填命令，不用手写 JSON。加了就生效。

## 立即能配好的 5 个 Hook
1. Claude 需要你时弹通知
别盯终端了。每次 Claude 等你输入——权限确认、空闲等待、任何需要你介入的时刻——自动弹：
放 ~/.claude/settings.json。这个要全局生效。
2. Claude 碰过的文件自动格式化
每次 Edit 或 Write 之后跑 Prettier。Claude 逐文件改代码导致的格式不一致，一劳永逸：
需要 jq 做 JSON 解析，macOS 上安装
放项目的 .claude/settings.json 并提交。这是团队规范。
3. 不让 Claude 碰受保护文件
拦住 .env、package-lock.json、.git/。被拦后 Claude 会收到反馈说明原因：
chmod +x .claude/hooks/protect-files.sh，然后注册：
4. 压缩后把上下文填回去
上下文窗口满了，Claude 会压缩对话总结。有时候重要细节被丢掉了。这个 Hook 在每次压缩后触发，提醒 Claude 最核心的事：
echo 换成动态命令也行：git log --oneline -5 看最近提交，或 cat .claude/sprint-context.md 加载独立上下文文件。
5. Git 提交强制规范
Claude 有时候按自己喜好写 commit message——type 前缀不对、用了句子大小写、末尾拖个句号。这个 Hook 在提交落地前拦一道：
这是 Prompt Hook——不写 shell 脚本，不写正则，让 Haiku 模型读命令、对照你的规范判断，直接返回结果。
放 ~/.claude/settings.json，所有项目生效。

## 退出码怎么用
Hook 脚本通过三个通道和 Claude Code 通信：
PreToolUse Hook 真正的威力就靠这个退出码体系：你的脚本读到 Claude 即将执行的操作，对照规则判断，要么放行，要么返回具体原因。

## 三步上手
第一步：全局加通知 Hook
打开 ~/.claude/settings.json，贴上面 macOS 通知的配置。最实用、零风险，纯附加行为，不拦截任何东西。让 Claude 做一件会触发权限确认的事，看看弹没弹。
第二步：当前项目加 Prettier 格式化
在项目根目录打开 .claude/settings.json（没有就新建），加 PostToolUse 格式化 Hook。没装 jq 先装。让 Claude 改个文件，确认自动格式化了。
第三步：打开 /hooks 翻一翻
交互菜单列出全部 事件和说明。想想你的工作流里还有哪些可以自动化。Stop 事件（Claude 完成后跑测试）和 PreToolUse（拦截特定模式）是下一个选择。

## Hook 的使用总结
没有 Hook 时，你可能需要结束后追问和检查：格式化做了吗？测试跑了吗？代码提交了吗？
配置 Hook 之后，这些问题解决。格式化一定会执行，测试一定会运行，通知一定会弹出。它们不再依赖 Claude 是否记得、是否理解、是否照做，而是变成项目环境本身的默认行为。
不要把关键流程寄托在 prompt 约束上。应通过环境机制强制执行关键动作，确保它们在每次运行中稳定执行。


---

## 互动数据

| 指标 | 数值 |
|------|------|
| 浏览 | 11,861 |
| 转发 | 27 |
| 点赞 | 119 |
| 书签 | 183 |

---

*来源：X (Twitter) @vincemask*
