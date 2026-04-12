# Karpathy LLM Wiki：用 Obsidian 打造 AI 知识库实战指南

> 来源：老张来了 (@laozhang2579) - 2026-04-05
> 原文：https://x.com/laozhang2579/status/2040732229035585615
> Karpathy Gist：https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

---

## 一、核心洞察：为什么 RAG 不够用？

大多数人用 AI 处理文档的方式是 **RAG**（如 NotebookLM、ChatGPT 文件上传）：
- 上传一堆文件
- AI 临时检索相关片段
- 拼出答案

**Karpathy 指出的根本问题**：**没有积累**

每次提问，AI 都在从头搜寻知识。问一个需要综合五篇文档的问题？AI 要每次现场找碎片、现场拼，**什么都没沉淀下来**。

**替代方案：LLM Wiki**
- 让 AI **增量地构建和维护**一个持久化的 Wiki
- 其实就是互相链接的 Markdown 文件
- 知识越积越厚

---

## 二、实战操作

### 2.1 Obsidian Web Clipper - 素材采集

**步骤：**
1. 安装 Chrome 扩展：Obsidian Web Clipper
2. 打开任意网页 → 点击扩展图标 → Add to Obsidian
3. 文章自动转为 Markdown 保存在 Obsidian

### 2.2 图片本地化 - 告别外链失效

剪藏的文章，图片通常还是外链，过几个月链接一挂，文章就残了。AI 也读不了挂掉的图片链接。

**配置步骤：**

**第一步：统一附件存储路径**
- 设置 → 文件与链接 → 附件存储路径
- 设为「当前文件夹下指定的子文件夹」
- 子文件夹名称：`attachments`

**第二步：绑定下载快捷键**
- 设置 → 快捷键 → 搜索「下载」
- 绑定快捷键：`Ctrl+Shift+D`

以后每次剪藏完，按 `Ctrl+Shift+D`，所有图片自动下载到本地。

**小细节**：LLM 目前没法一次性读取带内嵌图片的 Markdown。变通做法是先让 AI 读文本内容，再让它单独查看文章引用的图片。

### 2.3 Graph View - 知识库全貌

Obsidian 的 **Graph View** 把所有 Wiki 页面以节点形式展示，页面之间的双链关系自动连线。

**打开方式**：左侧边栏图谱图标 或 `Ctrl+G`

**配合 AI 的两个场景：**

1. **Lint 健康检查**
   - 一眼看出哪些页面是孤岛（没有任何链接指向它）
   - 说明交叉引用缺失，需要让 AI 补上

2. **发现知识盲区**
   - 某个概念被很多页面提到但没有独立页面
   - 在图谱里显示为灰色幽灵节点
   - 提醒你应该让 AI 为它创建专页

### 2.4 Dataview - Wiki 自生成报表（可选）

**Dataview** 是 Obsidian 的社区插件，能对页面的 YAML frontmatter 做数据库式查询，自动生成动态表格和列表。

**安装**：设置 → 第三方插件 → 社区插件市场 → 搜索 "Dataview" → 安装启用

**用法：在每个 Wiki 页面的 frontmatter 写结构化元数据**

```yaml
---
type: source
title: "文章标题"
date: 2026-04-05
tags: [AI, knowledge-base]
source_count: 3
---
```

**Dataview 查询示例：**

```dataview
TABLE title, date, tags
FROM "wiki/sources"
SORT date DESC
```

会自动生成按日期倒序排列的来源列表。

### 2.5 Marp - Wiki 内容变幻灯片（可选）

**Marp** 是基于 Markdown 的幻灯片格式，装上 Marp Slides 插件就能直接预览和导出。

**安装**：设置 → 社区插件 → 搜索 "Marp Slides" → 安装启用

**用法：**
- 在 Markdown 文件开头加上 `marp: true`
- 用 `---` 分隔每页幻灯片
- 写完直接在 Obsidian 里预览，可导出为 PDF/HTML/PPTX

**配合 LLM Wiki**：让 AI 从 Wiki 的某个主题页面直接生成 Marp 格式幻灯片草稿，微调后可用。

### 2.6 Git 版本管理 - 必选项

**安装**：设置 → 第三方插件 → 社区插件市场 → 搜索 "git" → 安装启用

**初始化 Git 仓库：**

```bash
cd 你的Vault目录
git init
```

**同步到 GitHub（私有仓库）：**

```bash
git branch -M main
git remote add origin https://github.com/你的用户名/knowledge-base.git
git add .
git commit -m "init: 初始化知识库"
git push -u origin main
```

**配置自动同步：**
- Obsidian Git 插件 → Auto commit-and-sync interval 设为 10 分钟
- 插件会自动 commit + push

**Git 对 LLM Wiki 是必选项**：AI 批量改文件的能力越强，你越需要版本管理来兜底。相当于知识库有了一个**实时备份+完整历史**。

### 2.7 qmd - 搜索利器（可选）

Wiki 规模小的时候，一个 `index.md` 目录文件就够 AI 导航。但页面多了之后，需要真正的搜索能力。

**Karpathy 推荐 qmd**：https://github.com/tobi/qmd - 一个完全本地运行的 Markdown 搜索引擎。

建议：Wiki 到几百个页面之前 `index.md` 完全够用，觉得 AI 找东西变慢了再接入 qmd。

---

## 三、为什么这套方法有效？

**Karpathy 原话：**

> 维护知识库最痛苦的不是阅读和思考，而是**记录**。更新交叉引用、保持摘要最新、标注新旧矛盾、维护几十个页面的一致性。人类放弃 Wiki 是因为维护成本的增长速度超过了价值的增长速度。

**但是 AI 不会厌倦**：
- 不会忘记更新交叉引用
- 一次操作可以碰十五个文件
- 维护成本趋近于零
- 知识库就能真正活下去

**思想精髓：**
- 你把精力放在：选素材、定方向、问好问题、思考意义
- AI 负责其他一切

---

## 四、老张的精简建议

**核心组合就够了**：
- Obsidian Web Clipper（素材采集）
- 图片本地化附件热键
- Git 版本管理
- Claude 集成（Filesystem MCP）

**相关教程**：Claude + Obsidian 最猛方案 | Filesystem MCP 教程
https://x.com/laozhang2579/status/2037106215747280968

---

## 关键要点总结

| 组件 | 作用 | 必要性 |
|------|------|--------|
| Obsidian Web Clipper | 素材采集 | ⭐⭐⭐ 必要 |
| 图片本地化 | AI 能读取图片 | ⭐⭐⭐ 必要 |
| Git 版本管理 | 备份+历史记录 | ⭐⭐⭐ 必要 |
| Graph View | 发现孤岛和盲区 | ⭐⭐ 推荐 |
| Dataview | 元数据查询报表 | ⭐ 可选 |
| Marp | 幻灯片生成 | ⭐ 可选 |
| qmd | 本地搜索引擎 | ⭐ 可选（规模大后） |

---

*整理时间：2026-04-06*