# Issue / PR：NPE on null topK in KnowledgeBaseDocumentRetriever (RAG chat)

> Target: spring-ai-alibaba (github.com/alibaba/spring-ai-alibaba).
> File as a **Bug issue** (the fix has a small design choice — what null topK should mean — so issue-first is slightly safer), or as a PR if you prefer. The patch below is directly `git apply`-able.
> 中文版见同目录 [19-issue-rag-topk-npe.zh.md](./19-issue-rag-topk-npe.zh.md).

---

## Title

`[Bug][admin] Agent chat with a knowledge base throws NPE: FileSearchOptions.getTopK() is null (regression from #3867)`

## Summary

Chatting with an **Agent app that has a knowledge base attached** throws a hard NPE on the first message, before/while the RAG retrieval runs, so RAG-backed chat is completely unusable whenever the agent-level `FileSearchOptions.topK` is not explicitly set:

```
java.lang.NullPointerException: Cannot invoke "java.lang.Integer.intValue()"
  because the return value of "...FileSearchOptions.getTopK()" is null
    at ...core.rag.retriever.KnowledgeBaseDocumentRetriever.retrieve(KnowledgeBaseDocumentRetriever.java:102)
    at ...core.rag.advisor.KnowledgeBaseRetrievalAdvisor.before(KnowledgeBaseRetrievalAdvisor.java:128)
```

Root cause: the public `KnowledgeBaseDocumentRetriever.retrieve(Query)` auto-unboxes `getTopK()` (and `getSimilarityThreshold()`) without a null check, while the **private** `retrieve(KnowledgeBase, Query)` in the same file already null-checks both. Contributing factor: `FileSearchOptions.topK` / `similarityThreshold` have no `@Builder.Default` despite their Javadoc claiming defaults (`3` / `0.2`), so they are `null` whenever not explicitly set.

## Environment

| Item | Value |
|---|---|
| spring-ai-alibaba | current `main` |
| Module | `spring-ai-alibaba-admin-server-core` (RAG retriever) |
| spring-ai | 1.1.2 |
| Introduced by | #3867 "Feat[admin]: introduce new admin platform" (Ken Liu, 2025-12-22) |

## Symptom

Any Agent app with a knowledge base fails on the first chat turn with the NPE above (logged as `Aggregation Error` / `Stream processing failed` wrapping the NPE). The chat returns nothing useful.

## Steps To Reproduce

1. Build & start the admin backend + frontend.
2. Create an **Agent** app, attach a **knowledge base** (RAG enabled).
3. Leave the agent-level file-search `topK` unset (the default state).
4. Open the app's chat, send any message.
5. Observe the NPE in the backend log; the chat fails.

## Root cause

`KnowledgeBaseRetrievalAdvisor.before(...)` calls `documentRetriever.retrieve(query)`, which lands in the **public** `retrieve(Query)`:

```java
List<Document> results = documents.stream()
    .sorted(...)
    .filter(x -> x.getScore() != null && x.getScore() > searchOptions.getSimilarityThreshold()) // NPE if similarityThreshold null
    .limit(searchOptions.getTopK())                                                                // NPE if topK null (unbox)
    .toList();
```

`searchOptions` here is the agent-level `FileSearchOptions` (`agentContext.getConfig().getFileSearch()`). When `topK` (or `similarityThreshold`) is null — the default when not configured — auto-unboxing throws NPE.

Inconsistency: the **private** `retrieve(KnowledgeBase, Query)` in the same class already guards both:

```java
if (searchOptions.getSimilarityThreshold() != null) { searchRequestBuilder.similarityThreshold(...); }
if (searchOptions.getTopK() != null) { searchRequestBuilder.topK(...); }
```

So the public method is simply missing the same null-safety.

Contributing factor: in `FileSearchOptions`, the fields document a default but don't enforce it:

```java
/** Number of top results to return, default to 3 */
@JsonProperty("top_k")
private Integer topK;                       // no @Builder.Default → null when unset

/** Minimum similarity threshold for search results, default to 0.2 */
@JsonProperty("similarity_threshold")
private Float similarityThreshold;          // no @Builder.Default → null when unset
```

## Suggested fix

Primary — make the public retriever null-safe (mirrors the private method; `null` topK = no post-merge cap, `null` similarityThreshold = skip the threshold filter — per-KB retrieval already applied its own):

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

Companion suggestion — also enforce the documented defaults on `FileSearchOptions` so unset options don't silently become `null` (belt-and-suspenders; helps any other caller that assumes a default):

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

> Note on the design choice: when `topK` is `null`, the primary patch returns all merged results (no cap). If maintainers prefer a fixed default, the companion `@Builder.Default` change makes that explicit instead.

## Workaround (for users blocked now)

Set `topK` (and ideally `similarityThreshold`) in the Agent's knowledge-base / file-search config so they are non-null at runtime.

## Anything else?

- Reproduces on current `main`; introduced in #3867 (Ken Liu, 2025-12-22). This is the **third** distinct bug I've hit that traces to #3867 (also: legacy Playground `currentPrompt` ReferenceError, and `Date.now()` React key collision). A big "introduce new admin platform" PR — worth a regression pass over the RAG + Playground paths it added.
- The null-safe retriever fix is the direct NPE fix; the `FileSearchOptions` defaults are a complementary hardening.

## References

- `com.alibaba.cloud.ai.studio.core.rag.retriever.KnowledgeBaseDocumentRetriever#retrieve(Query)` (line ~102)
- `com.alibaba.cloud.ai.studio.runtime.domain.app.FileSearchOptions` (`topK`, `similarityThreshold`)
- `com.alibaba.cloud.ai.studio.core.rag.advisor.KnowledgeBaseRetrievalAdvisor#before`
