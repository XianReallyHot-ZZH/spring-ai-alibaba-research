# Issue / PR（中文版）：KnowledgeBaseDocumentRetriever 在 topK 为 null 时 NPE（RAG 对话）

> 提交目标：spring-ai-alibaba（github.com/alibaba/spring-ai-alibaba）。
> 建议作为 **Bug issue** 提（修复有个小设计取舍——topK 为 null 时该怎么处理——所以 issue 先行更稳），也可直接当 PR。文末补丁可直接 `git apply`。
> 英文版见同目录 [19-issue-rag-topk-npe.md](./19-issue-rag-topk-npe.md)。

---

## 标题

`[Bug][admin] 挂知识库的 Agent 对话抛 NPE：FileSearchOptions.getTopK() is null（#3867 引入的回归）`

## 概述

**挂了知识库的 Agent 应用**，首条对话就抛硬 NPE（在 RAG 检索阶段），只要 agent 级 `FileSearchOptions.topK` 没显式设置，RAG 对话就完全不可用：

```
java.lang.NullPointerException: Cannot invoke "java.lang.Integer.intValue()"
  because the return value of "...FileSearchOptions.getTopK()" is null
    at ...core.rag.retriever.KnowledgeBaseDocumentRetriever.retrieve(KnowledgeBaseDocumentRetriever.java:102)
    at ...core.rag.advisor.KnowledgeBaseRetrievalAdvisor.before(KnowledgeBaseRetrievalAdvisor.java:128)
```

根因：公开的 `KnowledgeBaseDocumentRetriever.retrieve(Query)` 对 `getTopK()`（及 `getSimilarityThreshold()`）直接拆箱、没做 null 判断；而**同文件**私有 `retrieve(KnowledgeBase, Query)` 本来就 null 判断了。配套瑕疵：`FileSearchOptions.topK` / `similarityThreshold` 注释写有默认值（`3` / `0.2`）却没给 `@Builder.Default`，不显式设就是 null。

## 环境

| 项 | 值 |
|---|---|
| spring-ai-alibaba | current `main` |
| 模块 | `spring-ai-alibaba-admin-server-core`（RAG 检索器） |
| spring-ai | 1.1.2 |
| 引入提交 | #3867 "Feat[admin]: introduce new admin platform"（Ken Liu，2025-12-22） |

## 现象

任何挂知识库的 Agent 应用，首轮对话即抛上述 NPE（日志里是 `Aggregation Error` / `Stream processing failed` 包着 NPE），对话拿不到正常回复。

## 复现步骤

1. 启动 admin 后端 + 前端。
2. 创建一个 **Agent** 应用，挂一个**知识库**（开启 RAG）。
3. 不要设置 agent 级检索的 `topK`（默认就是不设）。
4. 打开应用对话，发任意消息。
5. 后端日志出现 NPE，对话失败。

## 根因

`KnowledgeBaseRetrievalAdvisor.before(...)` 调 `documentRetriever.retrieve(query)`，落到**公开** `retrieve(Query)`：

```java
List<Document> results = documents.stream()
    .sorted(...)
    .filter(x -> x.getScore() != null && x.getScore() > searchOptions.getSimilarityThreshold()) // similarityThreshold 为 null 即 NPE
    .limit(searchOptions.getTopK())                                                                // topK 为 null 拆箱即 NPE
    .toList();
```

这里的 `searchOptions` 是 agent 级 `FileSearchOptions`（`agentContext.getConfig().getFileSearch()`）。当 `topK`（或 `similarityThreshold`）为 null（默认未配）时，自动拆箱抛 NPE。

不一致点：**同文件私有** `retrieve(KnowledgeBase, Query)` 本来就判了空：

```java
if (searchOptions.getSimilarityThreshold() != null) { searchRequestBuilder.similarityThreshold(...); }
if (searchOptions.getTopK() != null) { searchRequestBuilder.topK(...); }
```

公开方法只是漏了同样的 null 安全。

配套瑕疵：`FileSearchOptions` 里字段注释有默认值却没强制：

```java
/** Number of top results to return, default to 3 */
@JsonProperty("top_k")
private Integer topK;                       // 无 @Builder.Default → 不设即 null

/** Minimum similarity threshold for search results, default to 0.2 */
@JsonProperty("similarity_threshold")
private Float similarityThreshold;          // 无 @Builder.Default → 不设即 null
```

## 建议修复

主修复——把公开检索方法改成 null-safe（对齐私有方法；`topK` 为 null 时不做合并后封顶，`similarityThreshold` 为 null 时跳过阈值过滤——各 KB 的检索已在私有方法里按各自 searchConfig 处理过）：

```diff
--- a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-core/src/main/java/com/alibaba/cloud/ai/studio/core/rag/retriever/KnowledgeBaseDocumentRetriever.java
+++ b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-core/src/main/java/com/alibaba/cloud/ai/studio/core/rag/retriever/KnowledgeBaseDocumentRetriever.java
@@ -96,10 +96,13 @@ public class KnowledgeBaseDocumentRetriever implements DocumentRetriever {
 				documents.addAll(future.get(SEARCH_TIMEOUT, TimeUnit.SECONDS));
 			}

+			Integer topK = searchOptions.getTopK();
+			Float similarityThreshold = searchOptions.getSimilarityThreshold();
 			List<Document> results = documents.stream()
 				.sorted(Comparator.comparing(Document::getScore, Comparator.nullsLast(Comparator.reverseOrder())))
-				.filter(x -> x.getScore() != null && x.getScore() > searchOptions.getSimilarityThreshold())
-				.limit(searchOptions.getTopK())
+				.filter(x -> x.getScore() != null
+						&& (similarityThreshold == null || x.getScore() > similarityThreshold))
+				.limit(topK != null ? topK.longValue() : Long.MAX_VALUE)
 				.toList();
```

配套建议——同时给 `FileSearchOptions` 落实注释里的默认值，避免未设项悄悄变 null（双保险，惠及所有假定有默认值的调用方）：

```diff
-		/** Number of top results to return, default to 3 */
-		@JsonProperty("top_k")
-		private Integer topK;
-
-		/** Minimum similarity threshold for search results, default to 0.2 */
-		@JsonProperty("similarity_threshold")
-		private Float similarityThreshold;
+		/** Number of top results to return, default to 3 */
+		@JsonProperty("top_k")
+		@Builder.Default
+		private Integer topK = 3;
+
+		/** Minimum similarity threshold for search results, default to 0.2 */
+		@JsonProperty("similarity_threshold")
+		@Builder.Default
+		private Float similarityThreshold = 0.2f;
```

> 关于设计取舍：`topK` 为 null 时，主补丁返回全部合并结果（不封顶）。若 maintainer 更想要固定默认值，配套的 `@Builder.Default` 改动会让这点显式化。

## 临时 workaround（供现在被卡住的用户）

在 Agent 的知识库 / 检索配置里显式设置 `topK`（最好也设 `similarityThreshold`），让运行时非 null。

## 其它

- current `main` 可复现；由 #3867（Ken Liu，2025-12-22）引入。这是我在你这份 checkout 里发现的**第三个**都源自 #3867 的 bug（另两个：legacy Playground 的 `currentPrompt` ReferenceError、`Date.now()` React key 冲突）。一个「引入新 admin 平台」的大 PR——建议对它新增的 RAG + Playground 链路做一轮回归。
- null-safe 检索器修复是直接解 NPE；`FileSearchOptions` 的默认值是配套加固。

## 参考

- `com.alibaba.cloud.ai.studio.core.rag.retriever.KnowledgeBaseDocumentRetriever#retrieve(Query)`（约 102 行）
- `com.alibaba.cloud.ai.studio.runtime.domain.app.FileSearchOptions`（`topK`、`similarityThreshold`）
- `com.alibaba.cloud.ai.studio.core.rag.advisor.KnowledgeBaseRetrievalAdvisor#before`
