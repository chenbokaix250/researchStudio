# AI/ML 核心技术深度解析报告

> 基于面试知识要点扩展 | 2026/05/25

---

## 目录

1. [Chroma 向量数据库深入解析](#1-chroma-向量数据库深入解析)
2. [RAG 检索增强生成系统](#2-rag-检索增强生成系统)
3. [多智能体系统记忆机制](#3-多智能体系统记忆机制)
4. [长期记忆与短期记忆](#4-长期记忆与短期记忆)
5. [长期记忆管理工程实践](#5-长期记忆管理工程实践)
6. [文档切分策略](#6-文档切分策略)
7. [语义意图识别](#7-语义意图识别)
8. [LoRA 微调技术](#8-lora-微调技术)
9. [外延知识补充](#9-外延知识补充)

---

## 1. Chroma 向量数据库深入解析

### 1.1 向量数据库核心原理

向量数据库是专为高维向量数据设计的数据库系统，主要用于 **语义相似性检索** 场景。

```
传统数据库: 精确匹配 (WHERE id = 1)
向量数据库: 近似最近邻搜索 (ANN) - 找到最相似的 Top-K
```

**核心概念**：
- **Embedding（嵌入）**：将文本/图像映射为固定维度的向量
- **相似度度量**：余弦相似度 (Cosine)、点积 (Dot Product)、欧氏距离 (L2)
- **ANN 算法**：HNSW、IVF、PQ 等近似搜索算法

### 1.2 Chroma 技术架构

```
┌─────────────────────────────────────────────────────────┐
│                      Chroma Client                        │
├─────────────────────────────────────────────────────────┤
│  Collection (相当于 Table)                               │
│  ├── embeddings: 存储向量                                 │
│  ├── documents: 原始文本                                  │
│  ├── metadatas: 元数据 (可过滤)                           │
│  └── ids: 唯一标识                                        │
├─────────────────────────────────────────────────────────┤
│  Query Engine                                             │
│  ├── 过滤条件处理                                         │
│  ├── 向量相似度计算                                       │
│  └── 结果排序与返回                                       │
└─────────────────────────────────────────────────────────┘
```

**Chroma 核心 API**：

```python
import chromadb

# 创建持久化客户端
client = chromadb.PersistentClient(path="./chroma_db")

# 创建集合 (可配置 embedding 函数)
collection = client.create_collection(
    name="documents",
    metadata={"description": "文档集合"},
    embedding_function=embedding_functions.OpenAIEmbeddingFunction(
        api_key="xxx",
        model_name="text-embedding-3-small"
    )
)

# 添加文档 (自动 embedding)
collection.add(
    documents=["文档内容1", "文档内容2"],
    metadatas=[{"source": "report"}, {"source": "article"}],
    ids=["doc1", "doc2"]
)

# 相似度查询
results = collection.query(
    query_texts=["查询内容"],
    n_results=5,
    where={"source": "report"},  # 元数据过滤
    include=["documents", "distances"]  # 返回内容
)
```

### 1.3 评估维度详解

#### 1.3.1 数据量评估

| 规模级别 | 向量数量 | 推荐方案 | 注意事项 |
|---------|---------|---------|---------|
| 原型/实验 | <10万 | Chroma (内存模式) | 快速验证 |
| 小规模生产 | 10-100万 | Chroma (持久化) / Qdrant | 关注召回率 |
| 中等规模 | 100-1000万 | Milvus / Qdrant | 需要分片 |
| 大规模 | >1000万 | Pinecone / Weaviate Enterprise | 分布式架构 |

#### 1.3.2 过滤能力

Chroma 支持 **元数据过滤**，在查询前或查询后进行过滤：

```python
# 方式1: 预过滤 (推荐大数据量)
results = collection.query(
    query_texts=["query"],
    n_results=10,
    where={"category": "tech"},  # 先过滤再搜索
    where_document={"$contains": "keyword"}  # 文档内容过滤
)

# 支持的操作符
where = {
    "category": {"$eq": "tech"},      # 等于
    "price": {"$gte": 100},            # 大于等于
    "tags": {"$in": ["AI", "ML"]},    # 包含任意一个
    "$and": [                          # 组合条件
        {"category": {"$eq": "tech"}},
        {"date": {"$gte": "2024-01-01"}}
    ]
}
```

#### 1.3.3 持久化机制

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **内存模式** | 全部存储在 RAM | 原型验证、数据量小 |
| **持久化** | 磁盘存储 + 内存缓存 | 生产环境 |
| **客户端/服务端** | Chroma Server 模式 | 多客户端访问 |

```python
# 服务端模式
# 服务端: chroma run --host 0.0.0.0 --port 8000
# 客户端:
client = chromadb.HttpClient(host="localhost", port=8000)
```

#### 1.3.4 并发处理

- **连接池**：Chroma 支持多客户端并发连接
- **写入优化**：批量写入 `collection.add()` 比单条写入快 10-100x
- **读并发**：向量查询本身可并行，QPS 取决于硬件

#### 1.3.5 可观测性

```python
# 获取集合统计信息
collection.count()           # 向量数量
collection.peek()            # 查看部分数据

# Heartbeat 检查
client.heartbeat()           # 检查服务是否存活
```

### 1.4 向量索引算法对比

| 算法 | 原理 | 精度 | 速度 | 内存 | 适用场景 |
|------|------|------|------|------|---------|
| **HNSW** | 分层可导航小世界图 | 高 | 极快 | 较高 | 需要高召回 |
| **IVF** | 倒排索引 | 中高 | 快 | 中 | 聚类数据 |
| **PQ** | 乘积量化 | 中 | 极快 | 低 | 内存受限 |
| **Brute Force** | 暴力搜索 | 100% | 慢 | - | 小数据集 |

Chroma 默认使用 HNSW 算法。

---

## 2. RAG 检索增强生成系统

### 2.1 RAG 完整架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAG 系统流程                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────┐ │
│  │  文档加载  │ -> │  文档切分  │ -> │  向量化   │ -> │   存储到向量库 │ │
│  └──────────┘    └──────────┘    └──────────┘    └──────────────┘ │
│       │                                                     │     │
│       │           Indexing (离线)                          │     │
│       │                                                     │     │
├───────────────────────────────────────────────────────────────┤
│                                                                  │
│       │           Retrieval (在线)                            │     │
│       │                                                     │     │
│  ┌────▼────┐    ┌──────────┐    ┌──────────┐    ┌──────────────┐ │
│  │ 用户查询  │ -> │  向量化   │ -> │  相似度检索 │ -> │   重排序     │ │
│  └─────────┘    └──────────┘    └──────────┘    └──────────────┘ │
│                                                             │     │
│       │                                          Augmentation│     │
│       │                                                     ▼     │
│  ┌────▼────────────────────────────────────────────────────┐   │
│  │                    Prompt 组装                           │   │
│  │  System: 你是一个助手，基于以下上下文回答问题              │   │
│  │  Context: {检索到的文档片段}                               │   │
│  │  Question: {用户问题}                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│                      ┌──────────────┐                           │
│                      │  LLM 生成答案  │                           │
│                      └──────────────┘                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Chunking 切分策略

#### 2.2.1 固定大小切分

最简单的策略，按字符/词数量切分：

```python
def fixed_chunk(text: str, chunk_size: int = 500, overlap: int = 50) -> list[str]:
    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunk = text[start:end]

        # 在单词边界处截断，避免打断词语
        if end < len(text):
            last_space = chunk.rfind(' ')
            if last_space > chunk_size // 2:
                chunk = chunk[:last_space]
                end = start + len(chunk)

        chunks.append(chunk.strip())
        start = end - overlap  # 重叠区域保持上下文连续性
    return chunks
```

**缺点**：
- 可能切断句子、段落语义
- 不考虑文档结构

#### 2.2.2 递归字符切分

LangChain 默认策略，递归尝试不同分隔符：

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    separators=["\n\n", "\n", "。", "！", "？", " ", ""],  # 按优先级尝试
    chunk_size=500,
    chunk_overlap=100,
    length_function=len,
)

chunks = splitter.split_text(long_document)
```

**优点**：优先按大段分割（段落），小段不够时再按句子，最终按字符

#### 2.2.3 语义切分

根据语义内容自动识别边界：

```python
from langchain_experimental.text_splitter import SemanticChunker
from langchain_community.embeddings import OpenAIEmbeddings

chunker = SemanticChunker(
    embeddings=OpenAIEmbeddings(),
    breakpoint_threshold_type="percentile",  # 或 "standard_deviation"
    breakpoint_threshold_amount=95,  # 语义断点阈值
)

chunks = chunker.split_text(document)
```

#### 2.2.4 层次切分

保留文档层级结构：

```python
from langchain.text_splitter import MarkdownTextSplitter

# Markdown 按标题层级切分
splitter = MarkdownTextSplitter(chunk_size=500, chunk_overlap=50)

# 或按文档结构 (章节 -> 段落 -> 句子)
class HierarchicalSplitter:
    def split(self, document):
        # L1: 按章节切分
        chapters = self.split_by_headers(document)
        # L2: 按段落切分
        paragraphs = [self.split_by_paragraph(c) for c in chapters]
        # L3: 按句子切分 (如果段落过长)
        chunks = []
        for para in paragraphs:
            if len(para) > self.chunk_size:
                chunks.extend(self.split_by_sentence(para))
            else:
                chunks.append(para)
        return chunks
```

#### 2.2.5 切分策略对比

| 策略 | 优点 | 缺点 | 适用场景 |
|------|------|------|---------|
| 固定大小 | 简单可控 | 打断语义 | 通用场景 |
| 递归字符 | 较智能 | 不理解语义 | 通用场景 |
| 语义切分 | 保持完整语义 | 计算成本高 | 结构化文档 |
| 层次切分 | 保留层级信息 | 实现复杂 | 论文、报告 |
| 特殊格式 | 保留格式信息 | 需定制 | PDF、代码 |

#### 2.2.6 切分参数选择

| 参数 | 建议范围 | 说明 |
|------|---------|------|
| chunk_size | 300-1000 | Token 数，建议 500 左右 |
| chunk_overlap | 50-200 | 重叠 10-20%，保持连续性 |
| min_chunk_size | 50-100 | 过小片段过滤 |

### 2.3 Retrieval 召回策略

#### 2.3.1 密集检索 (Dense Retrieval)

使用 Embedding 向量进行语义匹配：

```python
# 单一向量检索
results = collection.query(
    query_embeddings=[query_vector],
    n_results=5
)

# 混合检索 - 多角度查询融合
queries = [
    "原始问题",
    "问题的同义词表述",
    "问题的上位概念"
]

all_results = []
for q in queries:
    results = collection.query(query_texts=[q], n_results=3)
    all_results.extend(results["ids"][0])

# 去重
unique_ids = list(set(all_results))
```

#### 2.3.2 稀疏检索 (Sparse Retrieval)

类似 BM25/TF-IDF 的关键词检索：

```python
# ElasticSearch 示例
from elasticsearch import Elasticsearch

es = Elasticsearch(["localhost:9200"])

# BM25 检索
response = es.search(
    index="documents",
    body={
        "query": {
            "match": {
                "content": "搜索关键词"
            }
        },
        "BM25": {
            "k1": 1.2,  # BM25 参数
            "b": 0.75
        }
    }
)
```

#### 2.3.3 混合检索

```python
# 方案1: 各自检索后融合
dense_results = vector_db.similarity_search(query, k=10)
sparse_results = keyword_search(query, k=10)

# Reciprocal Rank Fusion (RRF)
from collections import defaultdict

rrf_scores = defaultdict(float)
k = 60  # RRF 参数

for rank, doc in enumerate(dense_results):
    rrf_scores[doc.id] += 1 / (k + rank + 1)

for rank, doc in enumerate(sparse_results):
    rrf_scores[doc.id] += 1 / (k + rank + 1)

final_ranking = sorted(rrf_scores.items(), key=lambda x: x[1], reverse=True)
```

```python
# 方案2: 使用向量数据库内置混合检索
# 以 Qdrant 为例
client.search(
    collection_name="docs",
    query_vector=query_vector,
    sparse_threshold=0.5,  # 稀疏向量权重
    limit=10
)
```

#### 2.3.4 重排序 (Rerank)

初筛后用更精确的模型重排：

```python
from sentence_transformers import CrossEncoder

# 使用 Cross-Encoder 重排
reranker = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")

# 初筛获取 20 个候选
candidates = vector_db.similarity_search(query, k=20)

# 重排
pairs = [(query, doc.text) for doc in candidates]
scores = reranker.predict(pairs)

# 按分数排序
ranked = sorted(zip(candidates, scores), key=lambda x: x[1], reverse=True)
top_docs = [doc for doc, _ in ranked[:5]]
```

### 2.4 RAG 评测体系

#### 2.4.1 核心指标

| 指标 | 计算方式 | 目标 |
|------|---------|------|
| **Recall@K** | 相关文档出现在 Top-K 的比例 | 越高越好 |
| **Hit Rate@K** | Top-K 至少有一个相关文档的查询比例 | >0.9 |
| **MRR** | 第一个相关文档的排名倒数均值 | 越高越好 |
| **NDCG** | 考虑排名的归一化折扣收益 | 接近 1 |

```python
def calculate_recall(predictions: list[list[str]], ground_truth: list[list[str]]) -> float:
    """计算 Recall@K"""
    total = 0
    for pred_docs, gt_docs in zip(predictions, ground_truth):
        pred_set = set(pred_docs)
        gt_set = set(gt_docs)
        recall = len(pred_set & gt_set) / len(gt_set) if gt_set else 0
        total += recall
    return total / len(predictions)

def calculate_mrr(predictions: list[list[str]], ground_truth: list[list[str]]) -> float:
    """计算 MRR"""
    total = 0
    for pred_docs, gt_docs in zip(predictions, ground_truth):
        for i, doc in enumerate(pred_docs, 1):
            if doc in gt_docs:
                total += 1 / i
                break
    return total / len(predictions)
```

#### 2.4.2 命中片段质量评估

```python
# 自动评估生成答案质量
from rouge_score import rouge_scorer

scorer = rouge_scorer.RougeScorer(['rouge1', 'rouge2', 'rougeL'], use_stemmer=True)

def evaluate_answer(predicted: str, reference: str) -> dict:
    scores = scorer.score(reference, predicted)
    return {
        "rouge1": scores['rouge1'].fmeasure,
        "rouge2": scores['rouge2'].fmeasure,
        "rougeL": scores['rougeL'].fmeasure
    }
```

#### 2.4.3 RAGAS 评估框架

```python
# 使用 RAGAS 评估
from ragas import evaluate
from ragas.metrics import (
    faithfulness,
    answer_relevancy,
    context_precision,
    context_recall
)

result = evaluate(
    dataset=rag_dataset,
    metrics=[
        faithfulness,        # 生成答案是否忠实于上下文
        answer_relevancy,     # 答案与问题的相关性
        context_precision,    # 上下文的精确度
        context_recall        # 上下文的召回率
    ]
)
```

---

## 3. 多智能体系统记忆机制

### 3.1 Multi-Agent 架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                    Multi-Agent 系统                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│    ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│    │ Agent 1 │    │ Agent 2 │    │ Agent N │              │
│    │ (Planner)│    │ (Search)│    │ (Coder) │              │
│    └────┬────┘    └────┬────┘    └────┬────┘              │
│         │              │              │                    │
│         └──────────────┼──────────────┘                    │
│                        │                                   │
│                 ┌──────▼──────┐                            │
│                 │  共享记忆层   │                           │
│                 │ Shared Memory│                            │
│                 └─────────────┘                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 记忆系统核心目标

| 目标 | 说明 | 实现方式 |
|------|------|---------|
| **压缩 (Compression)** | 减少记忆体积 | 摘要、提取关键信息 |
| **分层 (Layering)** | 按重要性分级 | 热/冷数据分离 |
| **检索 (Retrieval)** | 快速定位 | 索引、向量搜索 |
| **淘汰 (Expiration)** | 清理低价值信息 | LRU、价值驱动删除 |

### 3.3 Agent 记忆分类

```python
from dataclasses import dataclass
from typing import List, Optional
from datetime import datetime
from enum import Enum

class MemoryType(Enum):
    SHORT_TERM = "short_term"      # 短期记忆
    WORKING = "working"             # 工作记忆
    LONG_TERM = "long_term"         # 长期记忆
    EPISODIC = "episodic"           # 情景记忆
    SEMANTIC = "semantic"           # 语义记忆

@dataclass
class Memory:
    content: str
    memory_type: MemoryType
    importance: float              # 0-1 重要性评分
    created_at: datetime
    last_accessed: datetime
    access_count: int = 0
    metadata: dict = None          # 额外元数据

@dataclass
class ShortTermMemory:
    """短期记忆 - 当前会话上下文"""
    max_tokens: int = 128_000      # 上下文窗口限制
    memories: List[Memory] = None

    def __post_init__(self):
        self.memories = self.memories or []

    def add(self, content: str, importance: float = 0.5):
        self.memories.append(Memory(
            content=content,
            memory_type=MemoryType.SHORT_TERM,
            importance=importance,
            created_at=datetime.now(),
            last_accessed=datetime.now()
        ))

    def get_context(self) -> str:
        """获取当前上下文"""
        return "\n".join([m.content for m in self.memories[-10:]])

@dataclass
class LongTermMemory:
    """长期记忆 - 持久化存储"""
    vector_store: any               # 向量数据库
    graph_store: any               # 知识图谱 (可选)

    def store(self, memory: Memory):
        # 存储到向量数据库
        vector = self.embed(memory.content)
        self.vector_store.add(
            vectors=[vector],
            documents=[memory.content],
            metadatas=[{
                "importance": memory.importance,
                "type": memory.memory_type.value,
                "created": memory.created_at.isoformat()
            }]
        )

    def retrieve(self, query: str, top_k: int = 5) -> List[Memory]:
        # 基于向量相似度检索
        results = self.vector_store.similarity_search(query, k=top_k)
        return results
```

### 3.4 记忆流转机制

```
用户输入
    │
    ▼
┌─────────────────────────────────────┐
│  1. 短期记忆 (Short-term Memory)     │
│     - 当前对话上下文                  │
│     - 上下文窗口内的信息               │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  2. 工作记忆 (Working Memory)        │
│     - 当前任务状态                    │
│     - 中间推理结果                    │
└─────────────────┬───────────────────┘
                  │
                  ▼ (定期压缩/总结)
┌─────────────────────────────────────┐
│  3. 长期记忆 (Long-term Memory)       │
│     - 历史摘要                        │
│     - 知识库                          │
│     - 经验沉淀                        │
└─────────────────────────────────────┘
```

---

## 4. 长期记忆与短期记忆

### 4.1 对比详解

| 特性 | 短期记忆 | 长期记忆 |
|------|---------|---------|
| **容量** | 受限于 Context Window (4K-128K tokens) | 几乎无限 |
| **生命周期** | 单次会话 | 跨会话持久化 |
| **内容** | 当前对话、临时状态 | 摘要、知识、经验 |
| **组织形式** | 线性序列 / 列表 | 向量索引 + 图结构 |
| **访问速度** | O(1) 直接访问 | 需要检索 |
| **重要性衡量** | 时效性、上下文相关性 | 使用频率、普遍性 |
| **实现** | InMemory / Redis | Vector DB / KG |

### 4.2 短期记忆实现

```python
from collections import deque
from datetime import datetime, timedelta

class SlidingWindowMemory:
    """滑动窗口短期记忆 - 保留最近 N 条消息"""

    def __init__(self, max_messages: int = 50, max_age_hours: int = 24):
        self.max_messages = max_messages
        self.max_age = timedelta(hours=max_age_hours)
        self.messages = deque(maxlen=max_messages)
        self.importance_cache = {}  # message_id -> importance

    def add(self, role: str, content: str, importance: float = 0.5):
        msg = {
            "role": role,
            "content": content,
            "importance": importance,
            "timestamp": datetime.now()
        }
        self.messages.append(msg)

    def get_recent(self, n: int = 10, min_importance: float = 0) -> list:
        """获取最近 N 条消息，可按重要性过滤"""
        recent = list(self.messages)[-n:]
        if min_importance > 0:
            recent = [m for m in recent if m.get("importance", 0) >= min_importance]
        return recent

    def prune_old(self):
        """清理过期消息"""
        cutoff = datetime.now() - self.max_age
        while self.messages and self.messages[0]["timestamp"] < cutoff:
            self.messages.popleft()
```

### 4.3 长期记忆实现

```python
class LongTermMemory:
    """长期记忆管理系统"""

    def __init__(self, vector_store, kg_store=None):
        self.vector_store = vector_store
        self.kg_store = kg_store  # 知识图谱可选

        # 索引配置
        self.importance_index = "importance_score"
        self.type_index = "memory_type"
        self.time_index = "created_at"

    def store(self, content: str, memory_type: str, importance: float,
              embedding_model=None):
        """存储新记忆"""
        # 1. 生成向量
        vector = embedding_model.embed(content)

        # 2. 存储到向量数据库
        self.vector_store.add(
            vectors=[vector],
            documents=[content],
            metadatas=[{
                "type": memory_type,
                "importance": importance,
                "created": datetime.now().isoformat(),
                "access_count": 0
            }],
            ids=[f"mem_{uuid.uuid4()}"]
        )

    def retrieve(self, query: str, top_k: int = 5,
                 min_importance: float = 0) -> list:
        """检索相关记忆"""
        results = self.vector_store.similarity_search(
            query, k=top_k * 2  # 多取一些用于过滤
        )

        # 按重要性过滤
        filtered = [
            r for r in results
            if r.metadata.get("importance", 0) >= min_importance
        ]

        return filtered[:top_k]

    def summarize_and_compress(self, memory_ids: list, llm):
        """将多条记忆压缩为摘要"""
        memories = self.get_by_ids(memory_ids)
        content = "\n".join([m.content for m in memories])

        prompt = f"""将以下记忆片段压缩为一个简洁的摘要：

{content}

要求：
1. 保留关键信息和核心要点
2. 去除冗余和重复
3. 摘要长度控制在 200 字以内
"""

        summary = llm.complete(prompt)

        # 用摘要替换原记忆
        self.consolidate(memory_ids, summary)
```

---

## 5. 长期记忆管理工程实践

### 5.1 价值打分系统

```python
import math
from datetime import datetime, timedelta

class MemoryValueScorer:
    """记忆价值评估模型"""

    def __init__(self):
        self.recency_weight = 0.3
        self.frequency_weight = 0.3
        self.importance_weight = 0.2
        self.utility_weight = 0.2

    def calculate_score(self, memory: Memory, now: datetime = None) -> float:
        if now is None:
            now = datetime.now()

        # 1. 时效性衰减 (指数衰减)
        age = (now - memory.created_at).total_seconds()
        age_hours = age / 3600
        recency_score = math.exp(-age_hours / (24 * 7))  # 7天半衰期

        # 2. 访问频率 (对数缩放)
        frequency_score = math.log1p(memory.access_count) / 10

        # 3. 初始重要性
        importance_score = memory.importance

        # 4. 实用性分数 (基于最近使用效果)
        utility_score = self._calculate_utility(memory)

        # 综合评分
        total_score = (
            self.recency_weight * recency_score +
            self.frequency_weight * frequency_score +
            self.importance_weight * importance_score +
            self.utility_weight * utility_score
        )

        return round(total_score, 4)

    def _calculate_utility(self, memory: Memory) -> float:
        """计算实用性 - 基于后续任务成功率"""
        if not hasattr(memory, 'utility_history'):
            return 0.5

        if len(memory.utility_history) == 0:
            return 0.5

        return sum(memory.utility_history) / len(memory.utility_history)
```

### 5.2 定期摘要机制

```python
class MemoryConsolidator:
    """记忆整合器 - 定期摘要和清理"""

    def __init__(self, long_term_memory: LongTermMemory, llm,
                 consolidation_interval_hours: int = 24):
        self.ltm = long_term_memory
        self.llm = llm
        self.interval = timedelta(hours=consolidation_interval_hours)
        self.last_consolidation = datetime.now()

    def should_consolidate(self) -> bool:
        return datetime.now() - self.last_consolidation >= self.interval

    def consolidate(self, threshold_importance: float = 0.3):
        """执行整合"""
        # 1. 获取低价值记忆 (可能是冗余的)
        low_value_memories = self.ltm.query_by_importance(
            max_importance=threshold_importance,
            limit=100
        )

        # 2. 按主题/时间聚类
        clusters = self._cluster_memories(low_value_memories)

        # 3. 对每个簇生成摘要
        for cluster in clusters:
            if len(cluster) < 2:
                continue

            summary = self._summarize_cluster(cluster)

            # 4. 用摘要替换簇中的记忆
            self.ltm.consolidate(
                memory_ids=[m.id for m in cluster],
                summary=summary
            )

        self.last_consolidation = datetime.now()

    def _cluster_memories(self, memories: list) -> list:
        """按语义相似性聚类"""
        # 简化实现：按时间窗口聚类
        # 实际可用聚类算法
        clusters = []
        current_cluster = []

        for mem in sorted(memories, key=lambda m: m.created_at):
            if not current_cluster:
                current_cluster.append(mem)
            else:
                time_diff = (mem.created_at - current_cluster[-1].created_at)
                if time_diff < timedelta(hours=6):  # 6小时内归为一簇
                    current_cluster.append(mem)
                else:
                    clusters.append(current_cluster)
                    current_cluster = [mem]

        if current_cluster:
            clusters.append(current_cluster)

        return clusters

    def _summarize_cluster(self, cluster: list) -> str:
        """生成摘要"""
        content = "\n".join([m.content for m in cluster])

        prompt = f"""将以下相关记忆片段整合为一个简洁的摘要：

{content}

摘要要求：
1. 保留所有关键信息和数字
2. 识别并去除重复内容
3. 按时间或逻辑顺序组织
4. 长度控制在原内容的 20-30%
"""

        return self.llm.complete(prompt)
```

### 5.3 冷热分层存储

```python
class TieredMemoryStorage:
    """分层记忆存储 - 热、温、冷三层"""

    def __init__(self):
        # 热数据层 - 内存存储，频繁访问
        self.hot_storage = {}
        # 温数据层 - SSD/快速存储
        self.warm_storage = None  # 指向向量数据库的一类查询
        # 冷数据层 - 归档存储
        self.cold_storage = None  # 指向向量数据库的另一些记录

        self.hot_threshold = 0.7      # 分数 > 0.7 进入热层
        self.cold_threshold = 0.2     # 分数 < 0.2 进入冷层

    def store(self, memory: Memory):
        score = self.calculate_score(memory)

        if score >= self.hot_threshold:
            # 存入热层
            self.hot_storage[memory.id] = memory
        else:
            # 存入向量数据库 (温/冷层由元数据区分)
            self.ltm.store(memory, tier=self._get_tier(score))

    def retrieve(self, query: str) -> list:
        """跨层检索"""
        results = []

        # 1. 先查热层 (最快)
        hot_results = self._search_hot(query)
        results.extend(hot_results)

        # 2. 查询温层 (向量检索)
        warm_results = self.ltm.query(
            query,
            filter={"tier": "warm"},
            limit=10
        )
        results.extend(warm_results)

        # 3. 查询冷层 (如果需要)
        if len(results) < 5:
            cold_results = self.ltm.query(
                query,
                filter={"tier": "cold"},
                limit=5
            )
            results.extend(cold_results)

        return results

    def _get_tier(self, score: float) -> str:
        if score >= self.hot_threshold:
            return "hot"
        elif score <= self.cold_threshold:
            return "cold"
        return "warm"
```

### 5.4 去重合并

```python
class MemoryDeduplicator:
    """记忆去重"""

    def find_duplicates(self, memories: list, similarity_threshold: float = 0.9) -> list:
        """找出近似重复的记忆"""
        duplicates = []

        for i, mem1 in enumerate(memories):
            group = [mem1]
            for mem2 in memories[i+1:]:
                if self._is_similar(mem1, mem2, similarity_threshold):
                    group.append(mem2)

            if len(group) > 1:
                duplicates.append(group)

        return duplicates

    def _is_similar(self, mem1: Memory, mem2: Memory,
                    threshold: float) -> bool:
        """判断两条记忆是否相似"""
        # 1. 向量相似度
        vec_sim = self._vector_similarity(mem1.embedding, mem2.embedding)

        # 2. 语义相似度 (Jaccard 词重叠)
        words1 = set(mem1.content.split())
        words2 = set(mem2.content.split())
        word_sim = len(words1 & words2) / len(words1 | words2)

        # 3. 时间接近度 (同一小时内)
        time_diff = abs((mem1.created_at - mem2.created_at).total_seconds())
        time_sim = 1.0 if time_diff < 3600 else 0.0

        # 综合判断
        return vec_sim * 0.6 + word_sim * 0.3 + time_sim * 0.1 >= threshold

    def merge(self, duplicates: list) -> list:
        """合并重复记忆"""
        merged = []

        for group in duplicates:
            # 保留最重要的，合并元数据
            best = max(group, key=lambda m: m.importance)

            best.access_count = sum(m.access_count for m in group)
            best.metadata["merged_from"] = [m.id for m in group if m.id != best.id]

            merged.append(best)

        return merged
```

---

## 6. 文档切分策略

### 6.1 切分质量问题诊断

```
问题诊断流程:

用户反馈 "答案不准确" 或 "找不到内容"
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│ Step 1: 测召回率  │ -> │ Recall@K < 0.7?  │
│                 │    └────────┬────────┘
└────────┬────────┘             │
         │              Yes     │ No
         │               ▼       ▼
         │     ┌───────────┐  ┌───────────┐
         │     │ 切分问题   │  │ 检索问题   │
         │     └───────────┘  └───────────┘
         ▼
┌─────────────────┐
│ Step 2: 分析错误 │
│  - chunk 太小?  │
│  - chunk 太大?  │
│  - 语义断裂?    │
│  - 信息分散?    │
└─────────────────┘
```

### 6.2 切分问题与解决方案

#### 问题 1: 语义断裂

```python
# 错误示例 - 固定 500 字符切分
text = "Transformer 是 2017 年提出的革命性架构..."
# 可能在这里切断: "...Transformer 是 2017 年提..."
# 导致 "出的革命性架构" 被分离

# 正确做法 - 语义感知切分
from langchain.text_splitter import SemanticChunker

chunker = SemanticChunker(
    embeddings=OpenAIEmbeddings(),
    breakpoint_threshold_type="gradient",  # 基于语义断点
    breakpoint_threshold_amount=0.05,
    min_chunk_size=100
)

chunks = chunker.split_text(document)
```

#### 问题 2: 关键信息分散

```python
# 场景：表格数据被切分到不同 chunk

# 错误：
# Chunk1: "| 模型 | 参数量 |"
# Chunk2: "| GPT-4 | 1.8T |"

# 解决方案1: 保留表格格式的元信息
def split_with_table_awareness(text, chunk_size=500):
    chunks = []
    tables = extract_tables(text)

    for table in tables:
        if table.content_length > chunk_size * 0.8:
            # 表格作为独立 chunk
            chunks.append({
                "content": table.raw_text,
                "metadata": {"type": "table", "table_id": table.id}
            })
        else:
            # 合并到上下文中
            chunks.append(table.raw_text)

    return chunks

# 解决方案2: 重叠切分确保表格完整
# 在切分时检查是否跨越表格边界，如有则调整断点
```

#### 问题 3: 上下文丢失

```python
# 重叠切分策略
def overlap_chunk(text: str, chunk_size: int = 500,
                  overlap: int = 100, stride: int = None):
    """
    重叠切分 - 保持上下文连续性
    stride: 步长，不指定则为 chunk_size - overlap
    """
    if stride is None:
        stride = chunk_size - overlap

    chunks = []
    start = 0

    while start < len(text):
        end = start + chunk_size

        # 在句子边界截断
        chunk = text[start:end]
        if end < len(text):
            chunk = truncate_to_sentence_boundary(chunk)

        chunks.append(chunk.strip())
        start += stride

    return chunks

def truncate_to_sentence_boundary(text: str) -> str:
    """截断到最近的句子边界"""
    # 常见句末标点
    breakpoints = '.。!！?？;；\n'

    last_break = -1
    for i in range(len(text) - 1, len(text) - 100, -1):
        if i < 0:
            break
        if text[i] in breakpoints:
            last_break = i
            break

    if last_break > len(text) * 0.7:  # 确保不切得太短
        return text[:last_break + 1]

    return text
```

### 6.3 修复流程代码实现

```python
class DocumentIndexer:
    """文档索引器 - 处理文档切分和入库"""

    def __init__(self, vector_store, embedding_model):
        self.vector_store = vector_store
        self.embedding_model = embedding_model

    def reindex_with_new_strategy(self, collection_name: str,
                                   new_chunk_size: int = 500,
                                   new_overlap: int = 100):
        """使用新策略重新索引文档"""

        # 1. 获取旧数据统计
        old_stats = self.vector_store.get_collection_stats(collection_name)

        # 2. 导出所有文档
        old_docs = self.vector_store.get_all_documents(collection_name)

        # 3. 删除旧集合
        self.vector_store.delete_collection(collection_name)

        # 4. 使用新策略重新切分和入库
        new_collection = self.vector_store.create_collection(collection_name)

        for doc in old_docs:
            # 重新切分
            new_chunks = self._chunk_document(
                doc.content,
                chunk_size=new_chunk_size,
                overlap=new_overlap
            )

            # 重新生成向量
            for i, chunk in enumerate(new_chunks):
                new_collection.add(
                    documents=[chunk],
                    embeddings=[self.embedding_model.embed(chunk)],
                    metadatas=[{
                        "source_doc_id": doc.id,
                        "chunk_index": i,
                        "chunk_strategy": f"size={new_chunk_size},overlap={new_overlap}"
                    }],
                    ids=[f"{doc.id}_chunk_{i}"]
                )

        # 5. 返回新旧对比
        return {
            "old_stats": old_stats,
            "new_stats": new_collection.stats(),
            "changes": {
                "old_chunk_count": old_stats["document_count"],
                "new_chunk_count": new_collection.count()
            }
        }

    def _chunk_document(self, text: str, **kwargs) -> list:
        """切分文档"""
        from langchain.text_splitter import RecursiveCharacterTextSplitter

        splitter = RecursiveCharacterTextSplitter(
            chunk_size=kwargs.get("chunk_size", 500),
            chunk_overlap=kwargs.get("overlap", 100),
            separators=["\n\n", "\n", "。", "！", "？", " ", ""]
        )

        return splitter.split_text(text)
```

---

## 7. 语义意图识别

### 7.1 方法演进

```
意图识别方法演进:

1. 规则匹配 (Rule-based)
   └── 关键词、正则表达式
       优点: 快速、可控
       缺点: 泛化能力差

2. 传统机器学习
   └── SVM、Naive Bayes、Decision Tree
       优点: 一定的泛化能力
       缺点: 需要特征工程

3. 深度学习
   └── CNN、LSTM、BERT
       优点: 语义理解能力强
       缺点: 需要标注数据

4. 大模型 (LLM)
   └── Prompt Engineering、Fine-tuned LLM
       优点: 零样本/少样本、强大的上下文理解
       缺点: 成本较高、延迟
```

### 7.2 关键词/正则方案

```python
class RuleBasedIntentClassifier:
    """基于规则的意图分类器"""

    def __init__(self):
        self.intent_patterns = {
            "greeting": {
                "patterns": [
                    r"^(你好|您好|hello|hi|hey)",
                    r"(早上|下午|晚上)好",
                    r"在吗|在不在"
                ],
                "weight": 1.0
            },
            "query": {
                "patterns": [
                    r"是什么|什么是",
                    r"怎么|如何",
                    r"多少|几个",
                    r"帮我查"
                ],
                "weight": 1.0
            },
            "action": {
                "patterns": [
                    r"帮我(创建|新建|添加)",
                    r"(修改|更新|删除)",
                    r"执行|运行"
                ],
                "weight": 1.0
            },
            "cancel": {
                "patterns": [
                    r"(取消|撤销|算了|不用了)",
                    r"停止|终止"
                ],
                "weight": 1.5  # 取消意图权重更高
            }
        }

    def classify(self, text: str) -> dict:
        """分类并返回置信度"""
        text = text.lower()
        scores = {}

        for intent, config in self.intent_patterns.items():
            score = 0
            for pattern in config["patterns"]:
                if re.search(pattern, text, re.IGNORECASE):
                    score += config["weight"]

            if score > 0:
                scores[intent] = score

        if not scores:
            return {"intent": "unknown", "confidence": 0.0, "all_scores": {}}

        # 返回最高分意图
        best_intent = max(scores, key=scores.get)
        total_score = sum(scores.values())

        return {
            "intent": best_intent,
            "confidence": scores[best_intent] / total_score,
            "all_scores": scores
        }
```

### 7.3 机器学习方案

```python
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
from sklearn.svm import SVC
from sklearn.pipeline import Pipeline

class MLIntentClassifier:
    """机器学习意图分类器"""

    def __init__(self):
        self.pipeline = Pipeline([
            ('tfidf', TfidfVectorizer(
                ngram_range=(1, 3),
                max_features=5000,
                min_df=2
            )),
            ('classifier', SVC(kernel='rbf', probability=True))
        ])
        self.label_encoder = LabelEncoder()
        self.is_trained = False

    def train(self, texts: list, labels: list):
        """训练模型"""
        X = self._preprocess(texts)
        y = self.label_encoder.fit_transform(labels)

        self.pipeline.fit(X, y)
        self.is_trained = True

    def predict(self, text: str) -> dict:
        """预测意图"""
        if not self.is_trained:
            return {"intent": "unknown", "confidence": 0.0}

        X = self._preprocess([text])
        probas = self.pipeline.predict_proba(X)[0]
        pred_idx = probas.argmax()

        return {
            "intent": self.label_encoder.inverse_transform([pred_idx])[0],
            "confidence": float(probas[pred_idx]),
            "all_intents": {
                intent: float(proba)
                for intent, proba in zip(
                    self.label_encoder.classes_,
                    probas
                )
            }
        }

    def _preprocess(self, texts: list) -> list:
        """文本预处理"""
        # 简化的预处理
        return [t.lower().strip() for t in texts]
```

### 7.4 大模型方案

```python
from anthropic import Anthropic

class LLMIntentClassifier:
    """基于大模型的意图识别"""

    SYSTEM_PROMPT = """你是一个意图分类助手。请分析用户输入，判断其意图类型。

意图类型定义：
- greeting: 问候、打招呼
- query: 询问信息、查询
- action: 请求执行操作（创建、修改、删除等）
- help: 请求帮助
- cancel: 取消、放弃操作
- feedback: 提供反馈
- other: 其他

请只返回意图类型，不要解释。"""

    USER_PROMPT_TEMPLATE = """用户输入: "{user_input}"

意图类型: """

    def __init__(self, model_name: str = "claude-sonnet-4-20250514"):
        self.client = Anthropic()
        self.model = model_name

    def classify(self, text: str) -> dict:
        """使用 LLM 进行意图识别"""
        response = self.client.messages.create(
            model=self.model,
            max_tokens=50,
            system=self.SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": self.USER_PROMPT_TEMPLATE.format(user_input=text)
                }
            ]
        )

        intent = response.content[0].text.strip().lower()

        # 验证返回的意图是否有效
        valid_intents = ["greeting", "query", "action", "help", "cancel", "feedback", "other"]
        if intent not in valid_intents:
            intent = "other"

        return {
            "intent": intent,
            "confidence": 0.95,  # LLM 不直接返回置信度
            "raw_response": response.content[0].text
        }

    def classify_with_confidence(self, text: str, options: list) -> dict:
        """返回置信度的版本"""
        response = self.client.messages.create(
            model=self.model,
            max_tokens=200,
            messages=[
                {
                    "role": "user",
                    "content": f"""分析用户输入，返回意图和置信度。

用户输入: "{text}"

可选意图: {', '.join(options)}

请用以下 JSON 格式返回：
{{"intent": "意图", "confidence": 0.0-1.0, "reason": "简短原因"}}
只返回 JSON，不要其他内容。"""
                }
            ]
        )

        import json
        try:
            result = json.loads(response.content[0].text)
            return result
        except:
            return {"intent": "other", "confidence": 0.0}
```

### 7.5 混合方案 (生产推荐)

```python
class HybridIntentClassifier:
    """混合意图分类器 - 规则 + ML + LLM"""

    def __init__(self):
        self.rule_classifier = RuleBasedIntentClassifier()
        self.ml_classifier = None  # 可选
        self.llm_classifier = LLMIntentClassifier()

        # 置信度阈值
        self.rule_threshold = 0.8    # 规则高置信度直接返回
        self.ml_threshold = 0.7      # ML 高置信度直接返回
        self.llm_fallback_threshold = 0.5  # LLM 兜底

    def classify(self, text: str) -> dict:
        # 1. 规则快速分类
        rule_result = self.rule_classifier.classify(text)

        if rule_result["confidence"] >= self.rule_threshold:
            return rule_result

        # 2. 如果有训练好的 ML 模型，尝试 ML
        if self.ml_classifier and self.ml_classifier.is_trained:
            ml_result = self.ml_classifier.predict(text)

            if ml_result["confidence"] >= self.ml_threshold:
                return ml_result

        # 3. LLM 兜底 (复杂场景)
        llm_result = self.llm_classifier.classify_with_confidence(
            text,
            options=["greeting", "query", "action", "help", "cancel", "other"]
        )

        if llm_result.get("confidence", 0) >= self.llm_fallback_threshold:
            return llm_result

        # 4. 最终兜底
        return {
            "intent": "other",
            "confidence": 0.0,
            "source": "fallback"
        }
```

---

## 8. LoRA 微调技术

### 8.1 LoRA 核心原理

LoRA (Low-Rank Adaptation) 通过在预训练模型旁边添加低秩矩阵来模拟参数更新。

```
预训练权重: W₀ ∈ R^(d × k)
原始前向传播: h = W₀ · x

LoRA 更新:
- 添加并行低秩分支: h = W₀ · x + (A · B) · x
- 其中 A ∈ R^(d × r), B ∈ R^(r × k), r << min(d, k)
- W₀ 冻结不训练，只训练 A 和 B
```

**数学解释**：
- 传统微调更新 ΔW，存储完整 d×k 矩阵
- LoRA 假设 ΔW 是低秩的，分解为 A·B
- 参数量从 d×k 减少到 r×(d+k)

```python
# LoRA 伪代码实现
import torch
import torch.nn as nn

class LoRALinear(nn.Module):
    def __init__(self, in_features, out_features, rank=4, alpha=1.0):
        super().__init__()
        self.rank = rank
        self.alpha = alpha

        # 冻结原始权重
        self.weight = nn.Parameter(
            torch.randn(out_features, in_features),
            requires_grad=False
        )

        # LoRA 低秩矩阵
        self.lora_A = nn.Parameter(torch.randn(rank, in_features))
        self.lora_B = nn.Parameter(torch.zeros(out_features, rank))

        # 初始化 A (B 保持零初始化)
        nn.init.kaiming_uniform_(self.lora_A, a=math.sqrt(5))

    def forward(self, x):
        # W₀x + (α/r) · BA · x
        return torch.nn.functional.linear(x, self.weight) + \
               (self.alpha / self.rank) * torch.nn.functional.linear(
                   torch.nn.functional.linear(x, self.lora_A),
                   self.lora_B
               )
```

### 8.2 LoRA 变体

| 变体 | 原理 | 特点 |
|------|------|------|
| **LoRA** | 基础低秩适应 | 参数量少，效果好 |
| **QLoRA** | LoRA + 量化 | 更低显存，支持大模型 |
| **LoRA+** | 自适应学习率 | 更稳定的训练 |
| **AdaLoRA** | 自适应秩分配 | 动态调整重要性 |
| **DoRA** | 权重分解适应 | 性能更接近全量微调 |
| **LoRAFusion** | Pipeline 并行优化 | 高吞吐训练 |

### 8.3 QLoRA 详解

QLoRA (Quantized LoRA) 将量化与 LoRA 结合，可以在单卡 24GB 显存微调 65B 模型。

```python
from transformers import BitsAndBytesConfig
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training

# 4-bit 量化配置
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_use_double_quant=True,
    bnb_4bit_quant_type="nf4",       # Normal Float 4
    bnb_4bit_compute_dtype=torch.bfloat16
)

# 加载量化模型
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-2-70b-hf",
    quantization_config=bnb_config,
    device_map="auto"
)

# 准备训练
model = prepare_model_for_kbit_training(model)

# LoRA 配置
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=[                      # 关键参数
        "q_proj", "k_proj", "v_proj",
        "o_proj", "gate_proj", "up_proj", "down_proj"
    ],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM"
)

# 应用 LoRA
model = get_peft_model(model, lora_config)

# 打印可训练参数
model.print_trainable_parameters()
# 输出: trainable params: 83,886,080 || all params: 33,791,344,640 || trainable%: 0.248
```

### 8.4 LoRA 配置参数详解

```python
LoraConfig(
    # 核心参数
    r=8,                    # 秩，越大表达能力越强，但参数量增加
    lora_alpha=16,         # 缩放因子，通常设为 r 的 2 倍
    lora_dropout=0.05,     # Dropout，防止过拟合

    # 目标模块
    target_modules=[
        "q_proj",           # Query 投影层
        "v_proj",           # Value 投影层
        # 可选: "k_proj", "o_proj", "gate_proj", "up_proj", "down_proj"
    ],

    # 偏差处理
    bias="none",           # "none": 不训练 bias
                          # "all": 训练所有 bias
                          # "lora_only": 只有 LoRA 的 bias

    # 任务类型
    task_type="CAUSAL_LM"  # CAUSAL_LM / SEQ_CLS / TOKEN_CLS
)
```

**秩 r 的选择**：
| 模型规模 | 推荐 r | 参数量占比 |
|---------|-------|-----------|
| 7B | 4-8 | ~0.1% |
| 13B | 8-16 | ~0.2% |
| 70B | 16-32 | ~0.3% |

### 8.5 LoRA 训练实战

```python
from transformers import TrainingArguments, Trainer
from peft import LoraConfig, get_peft_model

# 完整的 LoRA 微调流程

# 1. 加载模型
model = AutoModelForCausalLM.from_pretrained(
    "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    torch_dtype=torch.float16,
    device_map="auto"
)

# 2. 配置 LoRA
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "v_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM"
)

model = get_peft_model(model, lora_config)

# 3. 准备数据集
def format_prompt(example):
    return f"### Question: {example['question']}\n\n### Answer: {example['answer']}"

train_dataset = dataset.map(
    lambda x: {"text": format_prompt(x)},
    remove_columns=dataset.column_names
)

# 4. 训练参数
training_args = TrainingArguments(
    output_dir="./lora_output",
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=4,
    learning_rate=2e-4,
    warmup_ratio=0.03,
    lr_scheduler_type="cosine",
    fp16=True,
    logging_steps=10,
    save_strategy="epoch",
)

# 5. 开始训练
trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=train_dataset,
    data_collator=data_collator,
)

trainer.train()

# 6. 保存 adapter
model.save_pretrained("./lora_adapter")
```

### 8.6 LoRA 模型合并与部署

```python
# 合并 LoRA 权重到基础模型 (用于部署)
from peft import PeftModel

base_model = AutoModelForCausalLM.from_pretrained(
    "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    torch_dtype=torch.float16,
    device_map="cpu"  # 合并后加载到 CPU
)

# 合并
merged_model = PeftModel.from_pretrained(base_model, "./lora_adapter")
merged_model = merged_model.merge_and_unload()

# 保存合并后的模型
merged_model.save_pretrained("./merged_model")

# 或者只合并指定层
# merged_model = PeftModel.from_pretrained(base_model, "./lora_adapter")
# merged_model.merge_adapter(["q_proj"])  # 只合并 q_proj 的 LoRA
```

---

## 9. 外延知识补充

### 9.1 向量数据库选型对比

| 数据库 | 优点 | 缺点 | 适用场景 |
|-------|------|------|---------|
| **Chroma** | 轻量、API 简洁 | 功能有限 | 原型、实验 |
| **Qdrant** | 性能强、支持过滤 | Rust 实现 | 生产推荐 |
| **Milvus** | 成熟、功能全 | 配置复杂 | 大规模 |
| **Pinecone** | 托管、免运维 | 付费、不可本地 | 企业云部署 |
| **Weaviate** | 混合搜索、内置向量化 | 资源占用高 | 多模态 |
| **Faiss** | 脸书开源、算法丰富 | 纯库非服务 | 研究/嵌入 |

### 9.2 RAG 优化技术

#### 9.2.1 Query 改写

```python
# 查询改写 - 扩展 query
query_enhancer_prompt = """将用户问题改写为更完整的查询，包含同义词和隐含信息。

原问题: {query}

改写要求：
1. 补充省略的主语
2. 添加可能的同义表述
3. 补充隐含上下文
4. 返回 2-3 个改写版本，用 | 分隔

改写:"""

def enhance_query(query: str, llm) -> list:
    response = llm.complete(query_enhancer_prompt.format(query=query))
    queries = [q.strip() for q in response.split("|")]
    return queries if len(queries) > 1 else [query]
```

#### 9.2.2 HyDE (Hypothetical Document Embeddings)

```python
# HyDE - 让 LLM 先生成假设答案，再用答案去找相似文档
def hyde_retrieval(query: str, llm, vector_db) -> list:
    # 1. 让 LLM 生成一个假设答案
    hypothetical_prompt = f"请为以下问题生成一个简短的回答：\n{query}"
    hypothetical_answer = llm.complete(hypothetical_prompt)

    # 2. 用假设答案去找相关文档
    results = vector_db.similarity_search(hypothetical_answer, k=5)

    # 3. 也可以同时用原 query
    results2 = vector_db.similarity_search(query, k=5)

    # 4. 融合结果
    return fusion_results(results, results2)
```

#### 9.2.3 Corrective RAG

```python
# 纠错 RAG - 验证检索结果的相关性
def corrective_rag(query: str, retriever, llm) -> str:
    # 1. 检索
    docs = retriever.get_relevant_documents(query)

    # 2. 检查文档是否真正相关
    relevance_check_prompt = """判断以下文档是否与问题相关。

问题: {query}

文档: {doc}

请返回：YES 或 NO"""

    relevant_docs = []
    for doc in docs:
        response = llm.complete(
            relevance_check_prompt.format(query=query, doc=doc.page_content)
        )
        if "YES" in response.upper():
            relevant_docs.append(doc)

    # 3. 如果都不相关，使用网络搜索补充
    if not relevant_docs:
        web_docs = web_search(query)
        relevant_docs = web_docs

    # 4. 生成答案
    return generate_answer(query, relevant_docs, llm)
```

### 9.3 Agent 架构模式

#### 9.3.1 单 Agent 架构

```
用户 -> Agent (ReAct/Memory) -> Tools -> 外部世界
              |
              +-- Short-term Memory
              +-- Long-term Memory
```

#### 9.3.2 多 Agent 协作模式

```
┌──────────────────────────────────────────────────────┐
│                 Supervisor Agent                     │
│  (任务分解 + 结果整合)                                 │
└──────────────────────┬───────────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌──────────┐    ┌──────────┐    ┌──────────┐
│Researcher│    │  Coder   │    │  Writer  │
│  Agent   │    │  Agent   │    │  Agent   │
└────┬─────┘    └────┬─────┘    └────┬─────┘
     │               │               │
     └───────────────┴───────────────┘
                       │
                  共享知识库
```

#### 9.3.3 Hierarchical Agent

```
                    ┌─────────────┐
                    │   Manager   │ (高层规划)
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
  ┌──────────┐       ┌──────────┐       ┌──────────┐
  │ SubAgent1│       │ SubAgent2│       │ SubAgent3│
  │ (执行)   │       │ (执行)   │       │ (执行)   │
  └──────────┘       └──────────┘       └──────────┘
```

### 9.4 Prompt Engineering 要点

```python
# 结构化 Prompt 模板
class PromptTemplate:
    SYSTEM_TEMPLATE = """你是一个 {role}。

背景信息：
{context}

能力限制：
- {limitations}

请按照以下格式回复：
{output_format}"""

    USER_TEMPLATE = """任务：{task}

要求：
{requirements}

{additional_info}

{'请开始执行。' if is_final else '请确认是否理解任务。'}"""

    @classmethod
    def build(cls, role: str, context: str, task: str,
              limitations: list = None, output_format: str = None,
              requirements: list = None, is_final: bool = True) -> tuple:
        """构建完整的对话 Prompt"""

        system = cls.SYSTEM_TEMPLATE.format(
            role=role,
            context=context,
            limitations="\n".join(f"- {l}" for l in (limitations or [])),
            output_format=output_format or "直接回复"
        )

        user = cls.USER_TEMPLATE.format(
            task=task,
            requirements="\n".join(f"{i+1}. {r}" for i, r in enumerate(requirements or [])),
            additional_info="",
            is_final=is_final
        )

        return system, user

# Few-shot 示例
FEW_SHOT_EXAMPLES = [
    {
        "input": "帮我查下北京的天气",
        "output": '{"intent": "query", "slot": {"city": "北京", "type": "weather"}}'
    },
    {
        "input": "今天适合穿什么",
        "output": '{"intent": "advice", "slot": {"topic": "穿搭建议"}}'
    }
]

def build_few_shot_prompt(query: str) -> str:
    examples = "\n".join([
        f"输入: {e['input']}\n输出: {e['output']}"
        for e in FEW_SHOT_EXAMPLES
    ])

    return f"""请识别用户意图。

示例：
{examples}

现在请识别：
输入: {query}
输出: """
```

### 9.5 相关技术词汇表

| 术语 | 英文 | 解释 |
|------|------|------|
| **向量嵌入** | Vector Embedding | 将数据映射为稠密向量 |
| **近似最近邻** | ANN | Approximate Nearest Neighbor |
| **余弦相似度** | Cosine Similarity | 向量夹角余弦值 |
| **分块/切分** | Chunking | 将大文档分割为小块 |
| **上下文窗口** | Context Window | 模型一次能处理的最大 token 数 |
| **幻觉** | Hallucination | 模型生成看似合理但错误的内容 |
| **提示工程** | Prompt Engineering | 设计 Prompt 引导模型输出 |
| **参数高效微调** | PEFT | Parameter-Efficient Fine-Tuning |
| **检索增强生成** | RAG | Retrieval-Augmented Generation |
| **Agent 记忆** | Agent Memory | Agent 的上下文/历史信息管理 |
| **知识图谱** | Knowledge Graph | 结构化的知识表示 |

---

## 总结

本报告从以下维度对 AI/ML 核心技术进行了深入解析：

| 领域 | 核心要点 | 进阶内容 |
|------|---------|---------|
| **向量数据库** | Chroma 架构、评估维度 | HNSW/IVF 算法对比 |
| **RAG** | Chunking/Retrieval/评测 | HyDE/Corrective RAG |
| **记忆机制** | 分层管理、压缩、淘汰 | 价值打分、冷热分层 |
| **意图识别** | 规则/ML/LLM 演进 | 混合架构 |
| **LoRA** | 原理、配置、变体 | QLoRA、模型合并 |

这些知识点构成了现代 AI 应用的核心技术栈，建议结合实战项目深入理解。