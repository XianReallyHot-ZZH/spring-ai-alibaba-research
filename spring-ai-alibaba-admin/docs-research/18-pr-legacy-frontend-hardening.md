# PR：fix(admin): harden legacy Playground/Evaluator frontend against crashes

> 提交目标：alibaba/spring-ai-alibaba。直接开 PR（四处修复都显而易见、无设计争议，其中两处直接复用代码库里已有的 `safeJSONParse`）。
> 四个独立的 legacy 前端崩溃 bug，都阻断相关功能、都由 #3867 引入。
> 改动 4 个文件，均在 `frontend/.../legacy/`。

---

## 标题

```
fix(admin): harden legacy Playground/Evaluator frontend against crashes
```

（scope `admin` 在 lint 白名单内；≤72 字符。）

## 正文（直接贴进 PR body）

### Describe what this PR does / why we need it

Four independent crash bugs in the legacy Playground and Evaluator pages (all introduced in #3867), each breaking a core build/eval flow:

1. **Playground — Send crash:** clicking **Send** throws `ReferenceError: currentPrompt is not defined`.
2. **Playground — first-turn mis-render:** the user's own message text is rendered inside the assistant bubble on the first turn (React key collision); later turns are fine.
3. **Evaluator — list crash:** the Evaluator list throws `SyntaxError: "undefined" is not valid JSON` whenever any evaluator's `modelConfig` is unset/invalid.
4. **Evaluator — template-detail crash:** the template `modelConfig` display crashes on invalid JSON (guarded only by `modelConfig &&`, which doesn't stop the literal string `"undefined"`).

### Does this pull request fix one issue?

```
NONE
```

<!-- 若你先开了 issue，把上行替换为：Fixes #xxxx -->

### Describe how you did it

**Bug 1 — undefined `currentPrompt`** (`pages/playground/playground.jsx`): the variable was referenced but never declared. Resolve it from the loaded `prompts` state using the same lookup pattern used elsewhere in the file, and read the version from the correct field (`currentVersion.version`):

```diff
// playground.jsx — runSinglePrompt
     } = promptInstance;

+    const currentPrompt = prompts.find(p => p.promptKey === promptInstance.selectedPromptId);
+
     const config = {
       ...
       promptKey: currentPrompt?.promptKey || 'playground',
-      version: currentPrompt?.latestVersion || '1.0',
+      version: currentPrompt?.currentVersion?.version || '1.0',
```

**Bug 2 — React key collision** (`playground.jsx` + `utils/streamingPrompt.ts`): the user-message id was `Date.now() + prompt.id` and the assistant-message id was `Date.now()`. Since `prompt.id` is a small number and the two `Date.now()` calls land within ~1 ms on the first turn, the ids collide → React reconciles with duplicate keys → user content leaks into the assistant bubble. Prefix each by type so keys never collide:

```diff
// playground.jsx — user message
-          id: Date.now() + prompt.id,
+          id: `user-${Date.now()}-${prompt.id}`,

// streamingPrompt.ts — assistant (streaming) message
-      id: Date.now(),
+      id: `ai-${Date.now()}`,
```

**Bug 3 — unguarded `JSON.parse` in Evaluator list** (`pages/evaluation/evaluator/index.tsx`): guard with a null check + try/catch (the codebase already has a `safeJSONParse` helper and sibling sites already guard; this one missed it):

```diff
// evaluator/index.tsx — modelConfig column render
       render: (modelConfig: string) => {
+        if (!modelConfig) return "-";
+        let modelConfigJson: any;
+        try {
+          modelConfigJson = JSON.parse(modelConfig);
+        } catch {
+          return "-";
+        }
         const name = modelNameMap[modelConfigJson?.modelId];
         return name ? (<Tag color="geekblue">{name}</Tag>) : "-";
       },
```

**Bug 4 — unguarded `JSON.parse` in template detail** (`pages/evaluation/evaluator/evaluator-detail/index.tsx`): use the existing `safeJSONParse` helper:

```diff
// evaluator-detail/index.tsx
+import { safeJSONParse } from '../../../../utils/util';
 ...
-                          {JSON.stringify(JSON.parse(selectedTemplateDetail.modelConfig), null, 2)}
+                          {JSON.stringify(safeJSONParse(selectedTemplateDetail.modelConfig, () => ({})), null, 2)}
```

### Describe how to verify it

1. Start admin backend + frontend (`npm run dev`).
2. **Playground:** configure a prompt → Send → no `ReferenceError`; the first turn's assistant bubble shows only the model reply (not the user's question).
3. **Evaluator:** open the list even when an evaluator has no `modelConfig` → no `SyntaxError`; open a template detail → no crash.

### Special notes for reviews

- Four files changed, all under `frontend/packages/main/src/legacy/`. No new dependencies — Bugs 3 & 4 reuse the existing `safeJSONParse` helper / guard pattern already used in sibling code.
- All four reproduce on current `main`; introduced in #3867 (Ken Liu, 2025-12-22).
- These are part of a cluster of bugs tracing to #3867 (also: backend `outputSchema` `BeanUtils` copy, and RAG `topK` NPE). A regression pass over the RAG + Playground + Evaluator paths that PR added is worthwhile.

---

## 提交流程（参考）

1. Fork `alibaba/spring-ai-alibaba`（若还没有 upstream fork）。
2. 从干净 upstream main 拉分支：`git switch -c fix/legacy-frontend-hardening upstream/main`。
3. 应用本改动（你本地工作区已是该状态——4 个文件四处修复）。
4. **本地先确认**：Playground 发送不崩且首轮渲染正常、Evaluator 列表/详情不崩（已确认 ✓）。
5. `git push -u origin fix/legacy-frontend-hardening` → GitHub 开 PR，base = `alibaba/spring-ai-alibaba:main`。
6. 标题/正文用上面这份；首次 PR 按 CLA bot 引导签个人 CLA。

> 注意：本 PR 只含这 4 个 legacy 前端文件——别把后端修复（outputSchema、RAG topK）或 docs-research 文档混进来。
