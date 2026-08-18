# Anthropic 如何用 Claude Code 跑大规模代码迁移

*原文标题：How Anthropic runs large-scale code migrations with Claude Code*

> 原文链接：https://claude.com/blog/ai-code-migration

一份用 AI agent 跑大型代码迁移的逐步指南——含 Bun 的百万行 Zig 到 Rust 移植。

代码迁移——把生产代码库移植到新语言的项目——直到最近都还是多年期的工程。

上个月，Anthropic 的个别开发者用 Claude Fable 5、Claude Opus 4.8 与 [dynamic workflows](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) 迁移了 10 个代码包，合计几万到几十万行。本文会介绍其中两个例子，并总结从这些项目里提炼的最佳实践。

Bun 的联合创始人、Anthropic 技术人员 Jarred Sumner 用 Claude Code 把 [Bun 从 Zig 迁移到 Rust](https://bun.com/blog/bun-in-rust)。不到两周产出了 100 万行代码，Bun 现有测试套件在合并前的 CI 上 100% 通过。合并后浮出 19 处回退，已全部修好。Rust 移植版在六月随 Claude Code 一起发布。

Anthropic Labs 联合负责人 Mike Krieger 在一个周末把一份 Python 代码库迁移到了 165,000 行 TypeScript。期间动用了数百个 agent、八道阶段门、三轮对抗性评审，以及最后一轮 parity check——逐条 diff 每个命令的输出与 Python 原版。

Claude Code 的新能力改变了这些"被一拖再拖"项目的算式。下面是我们现在使用的六步流程，源自这些迁移教给我们的东西。

核心洞察是：你修的并不是代码本身。**你修的是产生这些代码的过程（loop）。**

## 什么是 AI 代码迁移？

AI 代码迁移就是用 AI agent 把生产代码库移植到一门新语言或新框架。工程师不再手工翻译文件，而是写迁移规则与验证循环；agent 则负责翻译、编译、测试，直到新代码的行为与原版一致——把多年期的项目压缩到几周。

## **为何与何时需要做语言迁移**

在直接讲 *怎么做* 之前，先聊聊 *什么时候做* 与 *为什么做*——因为围绕这类项目的假设已经发生了变化。

团队发起迁移，往往是因为"最初构建时"与"当前情况"之间出现了格局变化：要么是某个已知的权衡开始成为瓶颈，要么是有更好的方案出现，要么是原来的生态在萎缩。

例如，Jarred 最初选 Zig 是因为它能提供 C 级性能、同时保持极致的简洁，对一个"在奥克兰的逼仄公寓里、在 LLM 之前，用一年写 Bun"的独立创始人来说特别合适。这种简洁伴随着已知的权衡，[他在文章里专门写到](https://bun.com/blog/bun-in-rust#just-be-really-smart-and-don-t-make-mistakes)。

时间跳到 2026 年。Bun 的 CLI 每月下载量超过 1000 万次，并在 Claude Code 内部被广泛使用。

就在上个季度，这些权衡还不足以让人冻结路线图、为一个跨多季度的项目投入资源。语言迁移确实能换来更小、更快、更安全的系统，但没人愿意为此买单。

软件工程师过去还必须承担这些"昔日巨型项目"自带的职业风险。你可能得在数个季度甚至数年的时间里并行维护两份代码库；一旦最后只有 90% 的对等性，你要面对的麻烦反而比开始时更大。

如今，最坏的情况不过是你删掉分支、再来一遍。

仍然需要一个站得住脚的商业依据。虽然百万行迁移不再需要花上四年的项目周期、烧掉 300–400 万美元的工程资源，但它仍然要花几万到几十万美元才能落地。以 Bun 的迁移为例：消耗了 59 亿未缓存输入 token、6.9 亿输出 token——按 API 价约合 165,000 美元。Mike 移植的主要部分消耗了 2700 万 token。

*Jarred 的百万行 PR。*

**不过，迁移这件事不再必须是"生死存亡"级别的事。** 一年的 changelog 里反复出现的内存 bug，或者一个长期慢性的瓶颈，如今都能为它正名。

Mike 项目的诱因就是编译环节。他的团队负责的内部工具作为单一二进制交付给用户。用 Python 工具链产出这个二进制，在每个平台上大约花 8 分钟——每次发布在 build matrix 上累计要等 30 分钟。移植之后，同样的编译现在大约花 2 秒，二进制启动快 6 倍，团队得以下线一条独立的部署流水线。

## **AI 为何改变了代码迁移的算式**

Claude Fable 5 是我们能力最强的、已 GA 的模型。Fable 与 Opus 4.8 在借助 subagent 委派、指导、验证并行工作流、同时为既定目标寻找多条路径方面尤为出色。

大型代码迁移是这些先进模型一个特别有效的用例，因为：

- **工作是可并行的**。工作可以分布到上千个独立单元（比如文件与 crate），让 agent 可以同时开工，而不是彼此等待。
- **上下文清晰且完备**。老代码本身就是一份出色的 spec，可以作为翻译 agent 遵循的核心参考。
- **存在内置裁判**。许多大型代码库都自带一套测试套件，agent 可以用来核验自己的工作。当验证足够客观时，agent 表现最佳——它能连续几天针对一个 ground truth 死磕，而不需要人来仲裁质量。
- **队列自己会长出来**。当编译器或测试失败时，那条失败就自然成了下一项要被 agent 修掉的任务。
- **它们需要一致性与边界条件处理**：流程被设计成"漂移无处藏身"——评审者会引用每条发现背后的依据，让一次违规变成队列里的一项，而不是悄悄的偏离。当某个 agent 撞上边界情况，修复就会变成一条所有后续 agent 都必须遵守的规则。

下文你会看到，Mike 和 Jarred 在迁移流程的关键环节上都用到了 Fable，特别是在 **"顾问模式"（advisory pattern）** 上——这种模式同时使用多个模型级别来优化 token 消耗。

## **大型代码迁移的六个步骤**

*下文流程已泛化到与多种语言和场景相关。更多细节，请阅读 *[*Jarred 的博客*](https://bun.com/blog/bun-in-rust)*。你也可以访问 *[*Migration starter kit（迁移入门套件）*](https://github.com/anthropics/code-migration-kit-with-claude-code)*。注意：入门套件是上文流程的通用化模板——并不是这些具体移植所用的工具。*

### **前置准备**

在启动迁移项目之前，**先要有一个强力的裁判（judge）**，否则你既没有退出条件，也没有成功的度量。

裁判必须能"平等"地评估原代码与目标代码。用原语言写的测试套件往往会依赖目标代码里不会存在的内部函数。

构建这样的裁判：

- **对已有测试做分类**。让 Claude 识别出哪些测试可以表达为外部调用，哪些依赖无法移植的内部实现。
- **重写以保证可移植性**。把面向外部的测试改写成断言，让它能同时跑在原版与移植版上。用对抗性 agent 来核验改写后的测试没有削弱断言。
- **验证裁判**。让它对原代码运行，确认通过。然后故意让它跑在有缺陷的代码上，确认失败——一个抓不住破坏的裁判不是裁判。

Jarred 有一份用"第三种语言"（TypeScript）写的大型测试套件，这对大多数项目来说并不常见。对他那份 Python → TypeScript 的移植，Mike 搭了一个由 7 个真实场景组成的 parity harness，把任何行为变化都当作必须修复的 bug。

在深入每个阶段之前，下图可能会帮你跟上节奏。它大致遵循 Jarred 的方法，并在每个阶段都设有评审与关卡。Mike 的整体结构类似，使用了类似的 loop 工作流，只是他把整个迁移端到端跑了一遍，根据结果修改规则与工作流，再跑一遍——前两次都把产出扔掉，直到第三次才产出真正的结果。

### **步骤 1 — 创建规则手册、依赖图与差距清单**

这一阶段我们搭建迁移的根基：一份"需要重构而非仅仅翻译"的代码清单、一本"如何翻译代码"的规则手册，以及一张"如何排序并行迁移工作流"的依赖图。

顺序很重要：**规则手册必须先于差距清单**。差距清单由"规则手册默认覆盖不到之处"定义，两者会在一次联合审计中一起被检验。

#### **规则手册**

[规则手册](https://github.com/anthropics/code-migration-kit-with-claude-code/blob/main/templates/RULEBOOK.md) 的具体形态，取决于你一开始就必须做出的关键架构决定。其中最重要的：新代码是沿用同样的结构，还是完全重做。

如果是前者（Jarred 的情况），规则手册主要是"在两种语言之间翻译类型与习惯用法"的查找表，并对那些更难翻译的组件指向差距清单。如果是后者（Mike 的情况），规则手册就是一份设计文档。

Jarred 通过与 Claude 对话来构建规则手册，就每一个有歧义的领域制定一条策略。他还专门设计了 8 个 subagent，根据自己直觉上的"常见失败模式分类"，分别去审查 8 类不同的失败模式。

#### **依赖图**

你需要理解文件之间的依赖关系，才能有效地把并行迁移的工作流拆开，从而知道哪些文件应该先迁移、哪些文件必须放在同一批里。某些语言和代码库有显式的 manifest 列表，让这件事变简单；但对于遗留代码库、以及 C/C++、Python 这样的主流语言，这些依赖需要被发现并绘成图。

Claude Code 可以让 agent 部署并运行一段确定性脚本来产出这张图。[迁移套件中的 prompt](https://github.com/anthropics/code-migration-kit-with-claude-code/blob/main/prompts/01-dependency-map.md) 用的是一个"review + fix"的循环工作流。*注意：入门套件是上文流程的通用化模板——并不是这些具体移植所用的工具。*

#### **差距清单与对抗性审稿人**

新语言有别于旧语言、必须满足的要求。比如从 Zig 到 Rust，差别在于手动内存管理（C 与 C++ 同理）。例如：

**Zig**

```zig
fn readConfig(allocator: std.mem.Allocator) ![]u8 {
  const buf = try allocator.alloc(u8, 1024);
  // ...fill buf...
  return buf; // caller must free this — but only the comment says so
}

// A caller that forgets 'defer allocator.free(buf)' still compiles — the leak only surfaces at runtime.
```

**Rust**

```rust
fn read_config() -> Vec<u8> {
  let buf = vec![0u8; 1024];
  // ...fill buf...
  buf // ownership moves to the caller; memory is freed automatically
}
// Use it after it's moved? Free it twice? Neither compiles.
// Forget to free it? There's no free call to forget — drop is automatic.
```

Python → TypeScript 的差距在于接口与契约。Python 不要求声明一份契约来规定它会接受什么形状的对象、返回什么；TypeScript 则必须。例如：

**Python**

```python
def register(handler):
    handler.setup()
    return handler.run({"retries": 3})
```

**TypeScript**

```typescript
interface RunResult { ok: boolean }

interface Handler
{ setup(): void;
  run(opts: { retries: number }): Promise<RunResult>;
}

function register(handler: Handler): Promise<RunResult> {
  handler.setup();
  return handler.run({ retries: 3 }); }

// The contract must be written down before this compiles
```

Jarred 与 Mike 都创建了"差距清单"文件来记录这些隐含知识。Jarred 是事先就盘点好了这些差距（也就是我们这里采用的做法），Mike 则选择先翻译、再通过事后审计创建差距清单。你可能两种都要做。

这里有一份 [创建差距清单文件的 Claude Code prompt 示例](https://github.com/anthropics/code-migration-kit-with-claude-code/blob/main/prompts/02-gap-inventory.md)。

### **步骤 2 — 对规则进行压测**

这一步是一次"小型迁移"，作为对更大规模迁移的"试航"。

Jarred 在这一步让一个 agent 按规则手册翻译三个文件、让一个 agent"以资深 Rust 工程师的姿态"翻译三个文件、让一个 agent 用 diff 产出新的翻译规则。在这个阶段，他抓到了两个关键问题——如果不发现，等这些规则散播到全部 1,448 个文件时，会造成大量问题。

prompt 大致像 [这个](https://github.com/anthropics/code-migration-kit-with-claude-code/blob/main/prompts/03-stress-test.md)。

这种压测 **只在"保留结构"的迁移中有效**——也就是说，同一份文件的两种翻译可以逐行对照。如果你的规则手册是一份重设计方案（像 Mike 的那样），那对应的测试就是：用对抗性审稿人直接攻击设计文档本身，再用一个一次性的端到端试跑来验证。

无论哪种情况，**扔掉所有翻译出来的文件**。目标是打磨规则，而不是取得渐进式的进展。

### **步骤 3 — 翻译所有内容**

剩下几步里，你跑的是同一种多 agent 循环架构：实现 → 评审 → 修复。

实现工作可以交给更小的模型，评审者继续用大模型。例如，Mike 在主迁移中扇出 12 个 subagent 时，用的就是 Claude Sonnet。

工作队列应当是机械的。一个批处理脚本通过"翻译文件是否已写入磁盘"判定什么是 done，再把待办文件切成批交给实现 agent。因为队列每次都从磁盘重建，所以这次迁移天然可恢复。

在这个阶段，agent 可能会过度谨慎它该做多少工作。修复办法是一段直白、强硬的 prompt 指令，配合一段上下文——编译器会在下一步把错误抓出来。

翻译者不能自信完成的任何东西，都用 `// TODO(port): <reason>` 标记，留到步骤 4 处理。从此以后，待办清单自己会长出来：编译器列出错误、smoke test 抓崩溃、套件汇报失败。

两个对抗性评审者用各自的上下文来评估实现者的输出；评审者之间的分歧被送给第三个 agent。当某位评审者反复在多个文件里抓出同一类错误时，修复方式不是逐文件处理——你在规则手册里加一句话，重新生成受影响的批文件。规则手册在这一步里持续生长；代码从不针对它被手工打补丁。

这一步里有一个值得注意的设计决定：**编译器放在哪里**。Mike 在每一轮循环里都跑 TypeScript 编译器，因为它在几秒内就能查完一个单元；Jarred 则干脆把编译器从循环里移除，全部放到下一步去做，因为 cargo 要花上几分钟。

到这一步，大量重活已经完成，[prompt 也开始变短了](https://github.com/anthropics/code-migration-kit-with-claude-code/blob/main/prompts/04-translation-kickoff.md)。

### **步骤 4、5、6 — 编译、运行、行为对齐**

这三个步骤共享同一种循环架构，且需要的人工判断越来越少，所以放在一起讲。

**步骤 4** 在很多时候会并到步骤 3 里——具体取决于语言与迁移规模。

取决于编译器步骤的规模与难度，agent 也许根本不会跑这一步。Jarred 用一个 orchestrator 脚本一次性把编译器在整个工作区跑了一遍，"修复者 agent"（Fixer agents）并行处理错误列表，并配以对抗性评审。再 build、再 run，往复循环。

审阅错误列表有助于发现可能需要调整的系统性问题。例如，Jarred 遇到了成千上万的 Rust 模块错误——这是因为他修了循环导入，而 Zig 的惰性编译容忍了这些。他通过把"该删、该移、该重划边界"的逻辑编码到循环里，修了这个问题。

**步骤 5** 同样有一个类似编译器错误列表的"机械化 ground truth"：smoke test 里的崩溃。同样，循环修复的思路是把问题按根因分组，让对抗性 subagent 复审每组。

**步骤 6**，也是故事的结尾，是对比两份代码库之间的程序行为。

文件已经翻译、编译、smoke test 过了。现在该做的是把它们切片，跑（前置准备阶段那套）测试套件。用"修复者 agent"对照两份代码库来排查失败；对抗性评审者检查它们的修复。

这一步的下一步是一个 [build daemon](https://github.com/anthropics/code-migration-kit-with-claude-code/blob/main/scripts/build_daemon.sh)，它是唯一允许重建二进制的进程。修复者写补丁；daemon 批量构建、重跑受影响的测试、把结果反馈回去。这把最昂贵的操作串行化了，而不是让多个 agent 各自触发它。

当同一个失败在多个测试里重复出现时，修复就往上回流：修改产出该 bug 的那条规则，只重新生成那条规则触及的文件。

Mike 的方法在这里尤为重要，因为很多开发者没有现成的、或已经移植好的测试套件。Mike 让 Claude 写了一个小脚本，针对新移植版与原 Python 代码库各跑 7 个真实场景，再 diff 结果。每个失败的场景交给自己的修复 agent，循环一直跑到全部 7 个场景通过为止。

然后他又往前迈了一步。Claude 自自己设计了一套端到端测试套件，并整夜自主运行、修好破损的部分、再重跑，连续跑了四晚。结果抓到了任何一份场景清单都预测不到的"切肤之痛"。

教训是：**没有现成测试套件并不会卡住这一步**。如果你继承不了一份裁判，就让 Claude 自己造一份。无论如何，原代码库就是 ground truth。

## **代码迁移最佳实践**

每一次运行都教会我们上一次没有的事。可以放心地说：你的下一次迁移也会教你这篇指南写不下的东西。但在所有项目里都站得住脚的几条实践包括：

- **不要盲目照搬这份指南**。每一次迁移都不同。把这份指南当作起点，在真正投入之前与 Claude 一起规划你这次特定的迁移。
- **不要把注意力放在单次失败上**。单次失败是循环的工作。修复 agent 会把它们一一搞定。你的注意力应当放在**模式**上。
- **把评审做成对抗性、把验证做成机械化**。对抗性评审能撑起更长的任务，往往值得那部分 token 消耗。让脚本——编译器、diff、测试套件——去当裁判。
- **不要把所有事都丢给最大的模型**。你的 token 消耗集中在 loops 里，所以要有意识地设计它们。小模型在高并发的实现扇出阶段表现良好；把最大的模型留给评审者，以及留给"写出其他 agent 都要遵守的规则"的环节。
- **把人的工时前置**。规则手册与压测是最耗时的。之后基本就是队列一项项被"烧"完。
- **让工作队列机械化、可恢复**。"Done"应当意味着"输出文件已经在磁盘上"。

## **看 loop 的结果，而不是代码**

Jarred 的 Bun 迁移已经在生产中跑了，尽管每一次迁移都有取舍。比如 Rust 代码里大约有 4% 位于 `unsafe` 块内，主要是 C/C++ 边界的单行指针操作。

但新代码库在可度量的层面更好了：团队的工具能检测到的每一处内存泄漏都已被修复——2,000 次重复构建的一个基准，内存占用从 6,745 MB 降到了 609 MB。Linux 与 Windows 上的二进制都缩小了 19%。跨语言优化让 HTTP 服务与真实负载（`next build`、`tsc` 等）快了 2–5%。

想想看，是不是时候重新算一算那些你一拖再拖的迁移账了？挑一个你一直在忍受的代码库，去问 Claude 针对它的迁移流程该是什么样。

***相关***

- [*迁移入门套件*](https://github.com/anthropics/code-migration-kit-with-claude-code)* 注意：入门套件是上文流程的通用化模板——并不是这些具体移植所用的工具。*
- [*代码现代化插件*](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-modernization)* — 面向遗留代码现代化与框架升级，而非语言移植*
- [*Claude Code 中的 dynamic workflows*](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code)