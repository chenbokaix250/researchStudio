# Claude 5 代模型的 Context Engineering 新规则

*原文标题：The new rules of context engineering for Claude 5 generation models*

> 原文链接：https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models

我们为更先进的模型移除了 Claude Code 系统提示中超过 80% 的内容。以及，如何把这些经验应用到你自己在 Claude Code 与自建 agent 中的 context engineering 中。

我此前写过如何最佳地 [给最新一代 Claude 5 模型写 prompt](https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns)，并以迭代方式与它们协作，发现你想构建的东西。

但当你向 Claude 发送消息时，prompt 只是它所拿到上下文的一小部分。上下文的大部分由你的系统提示、Skills、`CLAUDE.md` 文件、记忆以及其他来源共同拼装而成。我们称之为 [context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)，它对你在使用 Claude Code 或构建自己的 agent 时产出的结果有巨大影响。

不像 prompt 那样只服务一次请求，上下文通常会跨许多请求被复用，因此它不能太具体。你要如何为 Claude 构建这些通用的 prompt 和指引——尤其是当你不知道用户会发什么样的 prompt 时？

这可能出奇地难，因为 Claude 自身的能力也在演进。最近，我们注意到对最新一代 Claude 模型的 prompt 方式出现了一次大跳跃：我们在 Claude Opus 5 与 Claude Fable 5 这类模型上移除了 Claude Code 系统提示中超过 80% 的内容，而我们的编码评测没有任何可度量的损失。

下面是我们对这一代模型的 prompt 所学到的经验，以及你可以如何利用它来更新你的 context engineering。我们已把这些最佳实践放进了 `claude doctor`；在 Claude Code 中用 `/doctor` 命令来让你精简 skills 与 `CLAUDE.md`。

## "解除对 Claude 的束缚"

整体而言，我们发现我们对 Claude Code 做了过多约束——无论是在系统提示里，还是在 `CLAUDE.md` 文件和 skills 里。

举个例子，当我们复盘自己在内部使用 Claude Code 的对话记录时，会看到单条请求里出现几条互相冲突的信息，比如"适当保留文档"或"不要添加注释"——这些来自系统提示、skills 与用户请求的指令彼此矛盾。

通常情况下，Claude 能解读用户的意图来得到正确答案，但它必须在行动前更仔细地思考这些重叠与冲突的信息。

虽然这些约束一度是为了避免最坏情况而存在的，但我们后来发现可以删掉其中许多，让模型用上下文和判断力替代它们。

此外，Claude Code 现在多了更多工具。Claude 过去依赖 `CLAUDE.md` 作为记忆、信息与指引的来源。如今我们有了 memory、artifacts 和 skills，Claude 可以用它们来创造出新的方式，在不同会话间加载与共享上下文。

## 过去 vs. 现在

此前的一些 context engineering 最佳实践已经变成了"传说"。包括：

### 过去：给 Claude 规则

### 现在：让 Claude 自己做判断

Claude Code 一开始推出时，我们要确保 Claude 避开最坏的情况，比如删除文件。这意味着我们会给出格外强硬的指引，即使它们并非总是成立。比如我们的系统提示曾经这样说：

*在代码中：默认不写注释。永远不要写多段 docstring 或多行注释块——最多一行。不要主动创建计划、决策或分析类文档，除非用户明确要求——以对话上下文为准，不要靠中间文件。*

但对某些 prompt 来说，这种指引反而是错的。比如对文档来说，用户可能有自己的偏好，或者非常复杂的代码里某些部分确实需要多行注释块。

我们过去在没有这些护栏时，Claude 写的注释在很多情况下是不准确的，我们只能接受这种折衷。但更新的模型有了更好的判断力，能在没有显式规则的情况下也能妥善处理这些决定。

新的系统提示里我们改为：*写出的代码要与上下文里的代码风格一致：匹配它的注释密度、命名风格和习惯用法。*

### 过去：给 Claude 示例

### 现在：设计接口

过去工具使用的头号规则是给 Claude 怎么用工具的示例。在我们最新的模型上，我们发现给示例反而会把模型限制在某个探索空间里。

与其给示例，不如把更多心思花在工具、脚本和文件的设计上——Claude 拿到哪些参数，这些参数又能不能更有表达力？

例如，在 Todo 工具里，把 status 列为 `pending`、`in_progress`、`completed` 这三个枚举值，就是在给 Claude 关于如何使用的暗示。保持"只能有一项处于 in_progress"的指引则进一步界定了我们要求的行为模式。

### 过去：把所有信息一开始就堆上去

### 现在：采用渐进披露（Progressive Disclosure）

Claude Code 早期聚焦于编程，所以系统提示里塞进了大量关于"怎么做代码评审与验证"的细节。这些信息并非总是必要，但一旦用到，就是关键信息。

从那以后，Claude Code 已经非常擅长使用渐进披露——在恰当的时机加载恰当的上下文。例如，我们把验证与代码评审移到了独立的 skills 中，由 Claude Code 按需调用。

渐进披露不只用于 skills，我们对工具也这么做。我们的一些工具采用"延迟加载"——agent 必须先用 ToolSearch 搜索工具的完整定义才能使用。这让我们可以挂载更多工具（比如 Task 系列工具），而它们在不需要时不会占用上下文。

同样的方法可以应用到你自己 `CLAUDE.md` 与 `Skill.md` 文件上。一个常见的误区是：把"可能用到的所有已知做法"集中放进这些文件当中央仓库，因为 Claude 不然就找不到。换个思路——[考虑用一棵文件树，让 Claude 在合适的时候按需加载](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)。

### 过去：重复自己

### 现在：简洁的工具描述

更早的 Claude 模型有时需要被反复指示，或者更容易听进上下文窗口末尾的指令而不是开头的。这意味着我们的系统提示有时会在主提示里提到工具，再在工具描述里重复一遍用法。

我们后来发现，可以删掉这些重复，把"怎么用工具"的说明放到工具描述里，而不是系统提示里。

### 过去：把记忆存在 CLAUDE.md 文件里

### 现在：自动记忆（Auto-memory）

我们曾鼓励用户用 `#` 快捷键把东西写入 [CLAUDE.md](http://claude.md)，从而保存到 Claude 的记忆里。现在 Claude 会自动保存与工作以及与你相关的记忆。

### 过去：简单的规范文档

### 现在：丰富的参考资料

在 plan mode 中，Claude Code 严重依赖 Markdown 文件来承载计划。把这些计划存成文件帮助 Claude 在需要时回查。另一个类似的最佳实践是把规范存在代码库里，让 Claude 在更长的项目中工作时可以查阅。

但我们发现 Claude 能处理越来越复杂的参考资料。它不再只能读简单的 Markdown 文件，而可以引用我们新 artifacts 功能生成的 HTML artifacts。

你也可以把"参考资料"以代码的形式给到 Claude。一个规范可能是一份详尽的测试用例集合，也可能是另一个代码库里的某个函数——Claude 可能要把这个函数移植过来。

Rubric 是另一种形式的参考资料。Rubric 让 Claude 通过 [dynamic workflows](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code) 来尝试并验证你在某个特定领域的"口味"（比如"好的 API 设计长什么样"），它会带着这些 rubric 拉起 verifier agent。

## 把这些方法应用到你的上下文

把所有这些整合起来——当你拼装自己的上下文时，它看起来像什么？

### System Prompt（系统提示）

系统提示与产品本身强绑定。它告诉 Claude 它运行在哪个产品里、在做什么。对 Claude Code 而言，你大概率永远不会去改它；但如果你在自建 agent harness，这块才是你该投入最多时间打磨的地方。

### CLAUDE.md

保持 `CLAUDE.md` 精简，只简要描述你的仓库是做什么的，把大部分 token 花在代码库里的"陷阱"上。例如，你的代码可能把所有类型都集中在一个大文件里、绝不放别处。在 `CLAUDE.md` 里避免陈述那些 Claude 看文件系统或仓库就能知道的事情。

大量使用渐进披露。比如如果你有几条独特的"如何验证工作"指令，把它们做成一个 verification skill，再在 `CLAUDE.md` 里引用它。

### Skills

把 skills 视为"让 Claude 按需找到信息的轻量指南"。除非是极重要领域，否则不要把它们写得过死。

对较长的 skills，尽量多用渐进披露——把它拆成多个文件、按需加载。

最好的 skills 应该把那些对你、对你的团队或产品独特的观点、知识或最佳实践编码进去。

### References

你可以通过 `@` 提及文件来把它们作为引用纳入。References 让 Claude 能够在需要时查阅与当前计划相关的深度信息。

这些信息可能在规范文件里、原型设计稿里、甚至整个代码库里。一般来说，优先选那些以代码形式存在的文件，因为它们为 Claude 提供清晰、高保真的指令，且使用它最熟悉的语言。比如一个 HTML 设计原型通常会比你用文字描述这个设计或截一张图产生更好的效果。

## 试着做简化

在你的系统提示、skills 和 `CLAUDE.md` 文件里，你也许需要像我们一样做一次精简。我们推出了一个新命令 `claude doctor`，帮你自动完成这件事。关于如何针对更先进的模型做 prompt 的更多细节，请参考我们的 [Fable 实战指南](https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns)。

*本文由 Anthropic 技术人员 Thariq Shihipar 撰写。*