# CLI 工具成为 AI 能力扩展基础设施研究报告

> **来源**: [@op7418 (歸藏/guizang.ai)](https://x.com/op7418/status/2038450054688915868)
> **日期**: 2026-03-30
> **作者**: 歸藏 (guizang.ai)

---

## 核心观点

**2026 年各大公司（飞书、Google、Stripe、ElevenLabs、网易云音乐）不约而同发布 CLI 工具的根本原因：CLI 可能是当下效率最高的 AI 能力分发方式。**

---

## 一、背景：Karpathy 的观察

Andrej Karpathy 在用 AI 开发 app 的过程中发现，大部分时间不是写代码，而是在浏览器标签之间跳转：配 API Key、改 DNS、填环境变量。

他的结论：
> "你的服务应该有一个 CLI 工具。不要让开发者去访问、查看或点击。直接指示和赋能他们的 AI。"

---

## 二、CLI vs GUI 的本质区别

| 特性 | GUI | CLI |
|------|-----|-----|
| 交互方式 | 看菜单按钮，鼠标点击 | 敲文字命令，按回车 |
| 比喻 | 去餐厅看菜单指给服务员 | 直接对厨房喊"宫保鸡丁，少油，多辣" |
| AI兼容性 | 给眼睛看的，AI 没有眼睛 | 纯文字的，AI 天生在这个世界运作 |

**关键洞察**：人类没有重新爱上命令行，是 AI 原本就生活在命令行里。

---

## 三、AI 的能力边界

AI ≠ 全知全能的大脑，更像：**一个非常聪明的新员工，需要两样东西：工具 + 说明书**

- 装了 ffmpeg → AI 能处理视频
- 装了飞书 CLI → AI 能查日程、发消息
- 装了 Google Workspace CLI → AI 能管邮箱和云盘
- 没装 → "这个我做不了"

**公式**: `AI 的实际能力 = 它能调用的工具 + 它拿到的上下文`

工具越新，AI 越依赖显式说明书（Skills 文件），因为训练数据永远追不上工具发布速度。

---

## 四、CLI 正在被重新发明

### 传统 CLI vs 新一代 CLI

| 维度 | 传统 CLI (ffmpeg, jq, curl) | 新一代 CLI |
|------|---------------------------|-----------|
| 目标用户 | 程序员 | AI + 人 |
| 输出格式 | 给人眼看的彩色文字 | JSON，AI 直接解析 |
| 交互方式 | 弹交互式菜单 | 参数一次性传入，不弹菜单 |
| 文档 | 人读的文档 | Skills 说明书 (Markdown) |
| 预览 | 无 | --dry-run 预览 |
| 自描述 | --help | AI 可问"你有哪些命令？需要什么参数？" |

### 典型案例

- **飞书 CLI**: 200+ 命令，覆盖日历、消息、文档、任务、邮箱等 11 个领域
- **Google Workspace CLI**: 一条命令启动 MCP 服务，操作 Gmail、Drive、Calendar

---

## 五、CLI 成为 AI 的万能插件

### 三个概念的融合

1. **MCP (Model Context Protocol)**: AI 和外部服务之间的标准通信协议（AI 世界的 USB 接口）
2. **Skills**: 告诉 AI "这个工具怎么用"的说明书
3. **Plugin**: 把工具、协议、说明书打包在一起的可安装扩展

**关键洞察**: 新一代 CLI 把这三样全打包了 → **一个 CLI 工具就是一个事实上的 Plugin**

### CLI vs Plugin 的优势对比

| 维度 | Plugin | CLI |
|------|--------|-----|
| 跨平台 | 锁定特定平台（如 Claude Code Plugin） | 任何 AI 都能用：Claude/Cursor/Gemini/DeepSeek/Qwen |
| 审核 | 商城审核流程 | npm publish 就上线，跟发网站一样自由 |
| 组合 | Plugin 之间隔离，无标准组合方式 | Shell 管道：`gws gmail +triage \| jq '.messages[]'` |
| 用户 | 只有 AI 能用 | 人和 AI 都能用，开发者有更大动力维护 |

---

## 六、CLI 的结构性问题

### 1. 安全缺陷
- Plugin 在平台沙箱里跑，有声明式权限控制
- CLI 直接执行 shell 命令，AI 一旦能跑 gws 就能做任何事
- 目前靠 --dry-run 和弹窗确认补救，差距很大

### 2. 实践踩坑

| 问题 | 原因 | 解决方案示例 |
|------|------|-------------|
| 说明书太大 | Skills 文件占掉大量上下文，推理质量下降 | Google Workspace CLI: Skills 文件平均 1.6KB |
| 交互式提示卡死 AI | 弹选择菜单，AI 卡住 | Stripe CLI: 加 --no-interactive |
| 输出太长 | 几万字符 JSON 淹没有用信息 | Google Workspace CLI: field masks 控制返回大小 |

**根源**: "为 AI 设计" 和 "在 AI 中验证" 是两件事。

---

## 七、让 AI 管理自己的工具

歸藏在做 CodePilot 时的思路转变：

**传统软件思路**: 写代码嗅探系统、写 UI 管理工具、写逻辑检测更新

**AI 时代思路**: 给 AI 一个提示词模板，让 AI 读 --help、判断操作系统、处理权限错误、引导认证配置

**核心洞察**: 别用软件帮用户管理 AI 的工具，让 AI 管理自己的工具。

### 5 维 Agent 兼容度评分
1. 是否为 AI 设计
2. 是否支持结构化输出
3. 是否支持自查
4. 是否支持预览
5. 是否注意上下文大小

---

## 八、还缺什么？

| 缺口 | 现状 | 潜在解决方案 |
|------|------|-------------|
| **发现机制** | 靠口口相传，npm/GitHub 没动力做 AI 工具的 App Store | 需要 AI 时代的 npm |
| **认证** | 飞书一套、Google 一套、Stripe 一套，装五个工具登录五次 | 统一认证层 |
| **安装体验** | npm/brew 假设使用者是懂命令行的开发者 | AI 原生的包管理 |

**结论**: 行业不缺工具、不缺协议、不缺说明书，缺的是让这三样东西被发现、被安装、被信任的那一层基础设施。

---

## 九、总结：为什么大家都在做 CLI？

1. **效率最高**: 一个 CLI 同时包含执行能力、通信协议、使用说明 = 完整的 AI 插件
2. **跨平台**: 免审核，人和 AI 都能用
3. **可组合**: Shell 管道让工具之间能串联
4. **务实**: 在新旧交替的混乱时代，CLI 是目前最务实的答案

---

## 引用链接

- [CodePilot GitHub](https://github.com/op7418/CodePilot)
- [过了个年，AI 圈变天了？但没人告诉你为什么](https://mp.weixin.qq.com/s/z7zNi_DayzevcTe0EUTv5g)
- [You Need to Rewrite Your CLI for AI Agents](https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/)
- [Stripe Projects CLI](https://docs.stripe.com/projects)
- [Building CLIs for agents](https://x.com/ericzakariasson/status/2036762680401223946)
- [Karpathy: Vibe coding MenuGen](https://karpathy.bearblog.dev/vibe-coding-menugen/)
- [Google Workspace CLI](https://github.com/googleworkspace/cli)
- [飞书 CLI](https://github.com/larksuite/cli)

---

## 研究笔记

这篇文章提供了一个重要的视角：**CLI 不是复古，而是 AI 原生工具链的基础设施**。

对于 AI Agent 开发者，关键启示：
1. 如果你的服务想被 AI 使用，考虑发布 CLI
2. CLI 设计要为 AI 优化（JSON 输出、无交互、精简 Skills）
3. 安全问题是最大挑战，需要新的权限控制方案

这可能是 2026 年 AI 工具链发展的一个重要趋势。