# Auto mode 已成为 Claude Code 在 Pro、Max 与 Team 套餐下的默认设置

*原文标题：Auto mode is now the default in Claude Code for Pro, Max, and Team plans*

> 原文链接：https://claude.com/blog/auto-mode-default-in-claude-code

Claude Code 将很快在 Pro、Max 与 Team 套餐上默认开启 auto mode，从而支持更长时间的自主工作，并在我们的测试中拦截比人工审批更多的危险命令。

我们正在把 [auto mode](https://code.claude.com/docs/en/auto-mode-config) 设为 Claude Code 的默认设置。自 8 月 14 日起，Pro、Max、Team 套餐上的新会话都会运行在 auto mode 下。如果你已经自行设置了不同的默认，你可能会收到一次性的提示，询问是否要切换到 auto mode。如果你已经固定了某个默认，则对你没有任何变化。auto mode 的分类器每次工具调用会额外消耗少量 token，从今天起，我们不再向 Pro、Max、Team 套餐上的 Claude Code 用户收取这部分分类器开销的费用。

Claude Enterprise、Claude API、AWS 上的 Claude Platform、Amazon Bedrock、Google Cloud 的 Agent Platform 与 Microsoft Foundry 上的 auto mode 暂时仍为可选（opt-in），给管理员留出时间评估此次变更。在接下来一个月里，我们将与云合作伙伴一起，把这些环境也设为默认，并同样不再收取分类器开销。在此期间，Enterprise 管理员可以通过 managed settings 把 Claude Code 的 auto mode 设为默认。

Auto mode 的设计目标，是在"用户不想被频繁打断"的诉求与"避免有害动作"的系统要求之间取得平衡：它不再弹出审批提示，而是把每次工具调用路由给一个分类器，专门拦截那些不可逆、具破坏性、或者指向你环境之外的操作。当分类器拦截时，Claude 通常会自己找到一条更安全的路径，或者直接向你请示；如果仍然无法推进——连续三次被拦，或一个会话内累计二十次被拦——Claude Code 会回退到手动审批。

过去几个月，我们对"auto mode 是否至少与普通用户点击式审批一样安全"进行了密集测试。我们跑了内部红队测试、第三方红队测试与 prompt injection 评测，还与 1,053 名付费测试者做了对照研究，并对真实生产会话做了分析。在我们测过的每一项指标上，auto mode 都追平或超过了人工审批。

Auto mode 也让 Claude 能以更长时间段自主运行。这让像 Claude Opus 5 这样为长时任务设计的模型在大任务上"挂几个小时"变得更实用。降低用户开销同样意味着更多产出。在 Teams 与 Enterprise 早期采用者中，auto mode 用户的 PR 交付量提升了约 25%。解放 Claude 让任务可以更长时间不被打断，完成更多工作。Adobe、Nuro、Gusto、Garner Health 等团队已经把 [auto mode](https://claude.com/blog/auto-mode-in-production) 作为他们的生产默认设置。

下文会分享推动这次调整的安全数据与客户成果，并说明如果你想保留其他默认设置要怎么做。

## 手动审批 vs. auto mode

数据显示，手动审批会逐渐"变习惯"：用户在 Claude Code 中对权限提示的批准率高达 97%。虽然大多数提示很可能就是常规、安全的命令，但如此之高的批准率也说明，许多用户是在"条件反射式"地点击通过，而非逐条复核。这些提示每天要求开发者做出几十乃至上百个重要的安全决定——通常是在项目进行中——这把审查负担压在了用户身上，也增加了重要事项被忽略的概率。数据还显示，用户在其他类型的对话中会更为审慎：例如当 Claude 提交一份计划请求批准时，用户的拒绝率是 39%；但对单个权限请求，拒绝率只有 3%。

同样的模式也出现在设置文件中。截至 2026 年 6 月，49.5% 的活跃 CLI 用户手工创建了 Bash 允许规则——其中 5% 直接允许任意 shell 命令，另外 43% 配置了像 `Bash(python:*)` 或 `Bash(node:*)` 这样的解释器规则，实际等同于前者——这一比例大约每 5 周上升 5 个百分点。除允许规则外，62% 的用户曾使用过 `bypassPermissions` 或在 Bash 上点击"不再询问"，25% 的交互式会话一开始就处于 bypass permissions 模式。

在 auto mode 下，权限规则仍然会在分类器之前生效，但足够宽泛、可授予任意代码执行的允许规则（例如 `python:*`）除外。这些任意规则在 auto mode 下会被搁置，因为它们会让命令绕过分类器。设置文件本身不会被改动，一旦你切回其他模式，这些规则立即恢复生效。

## 用 auto mode 提升安全性

内部研究以及多家第三方的研究都表明，auto mode 比今天普通用户与权限提示互动的方式更安全。我们把 auto mode 与开发者实际点击通过权限提示时的行为做了对比。在每一项指标——内部红队测试、第三方渗透测试、真实会话分析——上，auto mode 都追平或超过了人工审批。

### Auto mode 在安全上胜过手动权限

![]()*在 1,053 名付费专业测试者参与的对照实验中，人工审核只拦截了 13.6% 的危险命令，而 auto mode 拦截了 89%。*

我们通过一家研究供应商招募了 1,053 名付费测试者完成一项编码研究。这些参与者在专门为研究搭建的测试环境中工作，而非他们自己的代码库或真实项目。参与者知道自己正在被评估，但按照标准的盲法设计，他们并不知道要测量的是什么。在每个会话进行到一半时，会有一条权限提示被替换为一条明确的危险命令，由供应商记录测试者是否批准（说明：批准提示绝不会真的运行任何危险命令，被替换的只是测试者看到的提示文字）。

测试者只在 13.6% 的情况下（1,053 人中 143 人）识别出了危险命令；而 auto mode 在同样的命令上拦截了 89%（1,053 中 937 条）。正面对比之下，auto mode 拦截了 800 条人类批准放行的命令，而人类只拦截了 6 条 auto mode 放行的命令。随着会话延长，人类的表现更糟：会话初期他们拦截约 17% 的危险命令，到第 50 次提示之后跌到约 5%；而 auto mode 的拦截率无论会话多长都保持稳定。

### Auto mode 减少更多有害动作

我们的研究也表明，与手动权限模式相比，auto mode 造成的有害动作更少。

我们考察了 auto mode 在真实使用中的表现。2026 年 5 月到 6 月间，我们挑出安全流水线标记为"需要复核"的会话，仅来自已选择同意数据用于训练与分析的账号。我们让一个模型对每条会话在两个 0–10 的量表上重新打分。第一个是"危害严重度"，10 表示公司层面的、不可逆的损害（例如泄露整个公司的源代码），7 表示生产级严重度（如删除生产数据库的行），0 表示完全可逆、仅限本地工作区的动作（例如覆盖某个临时文件）。第二个是"用户对该动作的显式请求程度"，以便把"用户直接请求的有害动作"与"智能体在不太显式的指令下做出的有害动作"区分开。

在被标记的会话中，经过手动审批的会话出现严重意外危害的频率，是 auto mode 会话的两倍多。在生产级严重度（7+）下，6.3% 的手动审批会话包含了用户并未显式请求的有害动作，而 auto mode 会话只有 2.4%；这一差距在我们测试的每一个严重度级别上都成立。

### 对抗性红队让 auto mode 更强

我们与位于英国的 AI 安全创业公司 Apollo Research 合作，开展了一项为期两周的试点，把合成攻击注入真实编程轨迹，覆盖三个数据集——广义失败、数据外泄、安全相关威胁。

这次合作遵循标准的"找问题—修复—再验证"循环。Apollo 分享了一系列成功攻击以及加强 auto mode 的建议。我们主要通过让分类器获得更多关于它所保护环境的信息（仓库可见性、git 状态、下文所述的数据处理规则）来加固它。

加固完成后，Apollo 在一组我们从未接触过的"留出集"（held-out set）攻击上重测。Auto mode 在新攻击上多拦截了此前漏掉的一半左右，代价是漏掉此前能拦住的约 2%。由于我们无法针对留出集做调优，这说明加固过程可以泛化到新攻击，而非只是为 Apollo 分享的具体攻击打补丁。综合两个数据集，分类器的漏报率从 12% 降到了 7%。

这些攻击是合成的、对抗性的，专为寻找分类器薄弱点而设计，比 Claude 在无人提示时会做出的事情更具恶意。上述 7% 漏报率是针对这类攻击测得的，不应被理解为真实流量上的漏报率。

### Auto mode 降低 prompt injection 风险

![]()*开启 auto mode 后，第三方独立评估中的所有攻击都没有在任何 Claude 模型上成功。GPT-5.6 Sol 在 Codex v0.144.5 Auto-review 权限模式下，攻击成功率为 5.83%。GPT-5.6 Sol 以 "max" 推理力度运行以测试其最高推理水平下的表现；所有 Claude 模型以 high 推理力度运行。*

Auto mode 的分类器为防御 [prompt injection 攻击](https://www.anthropic.com/research/prompt-injection-defenses) —— 即试图迫使智能体偏离用户指令的攻击 —— 增加了一层额外的防线。运行 auto mode 时，工具返回结果会经过一组探针扫描，检查是否包含潜在的恶意指令，auto mode 会核验这些动作与用户意图一致。我们把 auto mode 与无防护模型做了对比测试，以说明这种"纵深防御"思路的力量。

我们委托第三方 Trajectory Labs 做了一次评估，他们在 2026 年 7 月 17 日的最新公开版本 Claude Code 与 Codex 上分别测试了不同模型¹。他们在 Anthropic 留出的 72 个间接 prompt injection 场景上做了测试，每个场景重复 10 次。成功的攻击在非测试环境下会造成不可逆的伤害，例如敏感数据外泄、金融欺诈、凭证钓鱼。这些攻击针对的是 Claude Opus 4.7 优化的，而该模型不在报告范围内，因此每个被测模型面对的都是"未见过"的攻击。除了 auto mode 外，评估还考察了 Claude Code 的 *bypassPermissions* 模式与 Codex 的 *Full Access* 模式。

Codex 与 Claude Code 都使用 Trajectory Labs, PBC 提供的同一套浏览器集成进行评估。这套集成封装了一组 MCP 工具，作为 Chrome 常用 API（如 `navigate`）的薄包装。OpenAI 与 Anthropic 一方浏览器集成（如 Chrome 扩展）内置的安全防护并未参与测试。因此，这些结果应被视为对底层模型的度量，而非某个具体部署里全部安全防护的总和。

**在这次评估中，针对 Claude Fable 5、Opus 5 或 Sonnet 5（运行在 auto mode 下）的 720 次攻击无一成功。** 另一方面，针对运行 Codex *Auto-review* 模式的 GPT-5.6 Sol，有 5.83% 的攻击成功。值得注意的是，这高于我们最新模型在 *bypassPermissions* 模式下（不附加额外安全防护）平均 0.09% 的攻击成功率。测试还显示，运行 *Full Access* 模式的 GPT-5.6 Sol 上有 19.03% 的攻击成功率。如下图所示，工具以文本形式返回结果的任务与需要通过截图与浏览器交互的任务，攻击成功率存在差异。

![]()*Auto mode 在工具调用与浏览器 GUI 使用上都能防御 prompt injection。第三方评估显示，OpenAI 模型在浏览器任务上的攻击成功率更高。*

### Auto mode 在 Anthropic 内部阻止的三起事件

Auto mode 也是 Anthropic 内部所有 Claude Code 使用的默认设置。以下是分类器在内部阻止过的三个动作：

- **一次离网的数据外泄：** 当向内部盘的上传失败时，Claude 的备选方案是把同一份报告发布到一个公开的代码分享站点。Auto mode 否决了这个备选方案，并提示用户决定下一步。
- **一次破坏性的批量操作：** 在一个长时运行的会话里，Claude 试图跨大约两千个 pod 做批量进程终止，并把数百个 GPU 的在跑训练任务的删除操作排进了队列。Auto mode 在执行前标记了这些破坏性命令。
- **过宽的权限升级：** 当被要求配置只读账单权限时，Claude 伸手去拿一个会在账户根上授予完全管理控制的云角色。Auto mode 抓住了"所请求权限"与"将授予角色"之间的不匹配。

在每一起事件中，Claude 要么自己找到了更安全的路径，要么在继续之前向用户确认。

### 让 auto mode 更安全

我们持续投入新功能，让 auto mode 更安全、更便于交付生产代码。近期示例包括：

- [**Hard denies（硬拒）**](https://code.claude.com/docs/en/auto-mode-config#override-the-block-and-allow-rules)：数据外泄——例如把你的代码或机密发送到外部——属于分类器设计上永不批准的类别。要运行这类动作，你必须先退出 auto mode 或自己手动执行。Hard deny 规则可通过设置自定义，让你可以加入更多即便组织内用户请求也绝不允许的规则。
- **数据访问与共享规则：** 分类器现在携带明确的规则，区分机密与潜在的敏感/保密信息，以及它们各自可在何处被访问与共享。为了让这些规则可执行，它还会在动作运行前检查 git push 或 pull request 的目标是公开、私有还是受信仓库。同样的 push 行为因为落点的不同，可以是例行操作，也可以是数据外泄：属于你们团队私有仓库的代码不应出现在公开仓库里，分类器现在就被设计为在这种情况可能发生时拉响警报。
- **在执行破坏性 git 操作前检查 git 状态：** 在可能丢弃未提交工作的命令（如 `git reset --hard`）执行前，分类器会查看仓库当前的 git 状态，让 auto mode 知道究竟要重置掉什么。
- **Prompt injection 筛查：** 当 Claude 从外部源（如网页、文件内容、工具输出）拉取内容时，API 端的探针会检查这些内容里是否有劫持 Claude 行为的尝试。一旦发现疑似注入，会在结果送达用户之前把警告加入 Claude 的上下文。

## Auto mode 在生产环境中

已经有团队把 auto mode 作为他们的生产默认设置：

- **Adobe** 的商品平台团队负责在 Adobe.com 上 90+ 国家、30+ 语言范围内维护价格与促销页面的准确性与时效性。他们搭建了一个智能体循环来构建并验证这些页面，运行在 auto mode 下，这样工程师可以直接收到待复核的成品 PR。
- **Nuro** 在研究与工程组织中铺开 auto mode，用它驱动"通宵跑"的研究智能体，让它们围绕评测指标"爬山"，到清晨把成品 PR 交回人工复核。
- **Gusto** 引入 auto mode 是为了终结"权限疲劳"——工程师一度被推向"索性完全跳过权限检查"。自 5 月中旬起，约 10% 的会话包含分类器的拦截记录——证明它在干实事又不拖累合法任务。
- **Garner Health** 通过 managed settings 把 auto mode 推为全公司 550 名员工的默认设置，从而把一套公司级软件开发生命周期（SDLC）标准化，不再依赖手工维护的命令白名单。

> "在 Adobe，我们希望快速推进，又不能牺牲 Adobe.com 上客户体验的质量。借助 Claude Code 的 auto mode，我们搭建了一个智能体循环，让工作显著加速。Claude 先构建用户界面，再循环回去核验它是否与预期设计相符、自动修复所有问题，再交到我们眼前。这既缩短了开发周期，又交付了像素级的精准结果。"
> — Tomislav Reil，工程总监

> "前几天晚上 10 点我启动了一个智能体，它一直跑到凌晨 5 点——第二天早上给了我三个 PR。我觉得这相当惊艳。只有 auto mode 才能支撑这种工作负载。"
> — Kai Zhou，资深软件工程师

> "Auto mode 在速度与控制之间给了我们一个更安全的平衡。我们得以移除反复出现的提示，在不牺牲安全的前提下提升效率。我们能看到 auto mode 在恰当的时机拦截，这让团队有底气加快节奏。"
> — Martin Emde，软件工程师

> "我们为整个工程组织搭建了一套标准化的 SDLC，而它真正能够实现，正是因为有 auto mode。员工们把它看作一种如释重负：他们不再需要一连几个小时盯着自己的智能体。"
> — Evan Magnussen，平台工程经理

了解这些客户如何 [在生产环境中运行 auto mode](https://claude.com/blog/auto-mode-in-production)。

## 入门指引

- **Pro、Max 与 Team 用户：** 如果你尚未设置默认权限模式，你会在产品内收到一条提示，新会话将自动以 auto mode 启动。如果你已设置了不同的默认，你可能会看到一次性提示，询问是否要把默认切换到 auto mode。如果你的 Team 管理员已经在 managed settings 中设了默认，则对你没有任何变化。

- **Enterprise 用户与通过 Claude API 访问 Claude Code 的用户：** auto mode 暂时仍为可选。我们计划在接下来一个月内把它设为默认，并会提前通知 Enterprise 管理员。

- **切换模式：** 在 CLI 中按 Shift+Tab，或在桌面应用中使用模式切换下拉。管理员可以用 [managed settings](https://code.claude.com/docs/en/server-managed-settings) 中的 `defaultMode` 锁定全组织范围的默认设置，或用 `disableAutoMode` 完全关闭 auto mode。

最后，虽然我们相信 auto mode 对大多数用户都降低了风险，但它依赖分类系统，因此并不能消除风险。对于生产基础设施的高风险变更，我们仍然建议你亲自复核 Claude 的动作。完整配置说明请参见 [auto mode 文档](https://code.claude.com/docs/en/auto-mode-config)。

*本文由 Conner Phillippi 撰写，Nicholas Carlini、Isaac Fung、John Hughes、Alex Isken、Shawn Moore、Javier Rando 与 Molly Vorwerck 亦有贡献。作者们同时感谢 Yacine Azmi、Chandler Bair、Kefan Chen、Boris Cherny、Ian Grunert、Lydia Hallie、Alex Kleiman、Lauren Polansky、Deon Poncini、Robert Schonberger、Marie Vachovsky、Qing Wang、Cat Wu、Daniel Xu 与 Alice Zhao。*

¹ 我们评估的是 Claude Code v2.1.205 与 Codex v0.144.5。OpenAI 上周发布了新版 Auto-review，可能影响结果。