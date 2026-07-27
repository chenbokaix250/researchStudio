# 700萬人下載的 grill-me，Matt Pocock 到底寫了什麼？

> **分類**: ai-tech
> **更新**: 2026-07-27
> **來源**: YouTube - Gary Chen
> **影片連結**: https://www.youtube.com/watch?v=aR97E7aKEgg

---

## 影片概述

這支影片由 Gary Chen 製作，探討 Matt Pocock 開發的 NPM 套件 **grill-me**，該工具在 NPM 上已累積超過 **700 萬次下載**，引發開發者社區的廣泛關注。

---

## Matt Pocock 是誰？

Matt Pocock 是一位知名的 TypeScript 教育者，以以下內容聞名：

- **Total TypeScript**：全面的 TypeScript 學習平台，提供教程和工作坊
- **Zod 教程**：以其 Zod（Schema 驗證函式庫）教學內容著稱
- **TypeScript 專家內容**：在 YouTube 上發布大量關於 TypeScript、React 和 Node.js 的技術影片

---

## 什麼是 grill-me？

**grill-me** 是一個 NPM 套件（CLI 工具），由 Matt Pocock 開發。它是一個互動式 CLI 工具，透過 AI 自動審查、質問並「烤問」（grill）你的程式碼。

### 核心概念

工具名稱中的 `/` 前綴遵循了所謂的 **Slash Command** 模式，這種模式由 Vercel 的 `vl` 等工具推廣開來。

grill-me 本質上是一個 **AI 程式碼審查者**，與一般只幫你修正或解釋程式碼的 AI 助理不同——它會**要求你為自己的程式碼決策辯護**，透過蘇格拉底式的提問方式，引導開發者深入思考實作選擇。

### 運作方式

當你對自己的程式碼執行 `grill-me` 時，它不會只是審查你的程式碼，而是會問你各種問題，例如：

- 「你為什麼選擇這個方法？」
- 「如果輸入為空會發生什麼？」
- 「你有考慮過 X 這個邊界情況嗎？」

---

## 為何引發熱潮？

### 1. 獨特的定位

與市面上多數 AI 程式碼工具不同，grill-me 不直接告訴你「錯在哪裡」或「怎麼改」，而是**透過提問強迫你反思自己的程式碼決策**。這種 Socratic（蘇格拉底）式的方法在開發者社群中極為罕見。

### 2. 教育理念的體現

Matt Pocock 的教學哲學強調：理解程式碼**為什麼**能運作，而不僅僅是**因為什麼**而能運作。grill-me 完美體現了這一理念。

### 3. NPM 700 萬次下載的現象

這個下載量說明了：
- CLI 工具在開發者群體中仍有強大需求
- AI + 程式碼教育的結合極具市場潛力
- 互動式程式碼審查工具填補了市場空白

---

## 技術細節

- **發布平台**: NPM（`grill-me`）
- **GitHub**: 可能開源於 Matt Pocock 的 GitHub 帳號 (@mattpocock)
- **技術棧**: 可能使用 Node.js + TypeScript（符合 Matt Pocock 的技術品牌）
- **AI 整合**: 使用 LLM（如 GPT-4 或類似模型）處理提問邏輯

---

## 安裝方式

```bash
npm install -g grill-me
```

---

## 總結

grill-me 是 Matt Pocock 將其「透過提問促進深度學習」理念具象化的作品。不同於一般 AI 工具直接給出答案，grill-me 扮演一個嚴格的「面試官」角色，用問題來挑戰開發者的程式碼假設。這種工具的成功（700 萬下載）反映出一個趨勢：開發者社群對於能促進深度思考的工具需求遠比預期更大。

---

*資料來源：YouTube 影片 by Gary Chen | 2026-07-27*
