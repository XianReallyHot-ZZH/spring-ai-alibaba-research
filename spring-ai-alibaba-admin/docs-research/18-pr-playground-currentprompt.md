# PR：fix(admin): fix Playground send crash and message key collision

> 提交目标：alibaba/spring-ai-alibaba。直接开 PR（两处修法都显而易见、无设计争议）。
> legacy Playground 对话测试的两个独立 bug，都阻断该功能、都由 #3867 引入。
> 改动 2 个文件：`frontend/.../legacy/pages/playground/playground.jsx` + `frontend/.../legacy/utils/streamingPrompt.ts`。

---

## 标题

```
fix(admin): fix Playground send crash and message key collision
```

（scope `admin` 在 lint 白名单内；≤72 字符。）

## 正文（直接贴进 PR body）

### Describe what this PR does / why we need it

The legacy Playground chat-test has two bugs that together make it unusable:

1. **Send crashes:** clicking **Send** throws `Unhandled Rejection (ReferenceError): currentPrompt is not defined` (inside `runSinglePrompt`), so no message can be sent at all.
2. **First-turn mis-render:** on the first turn, the user's own message text is rendered inside the assistant's reply bubble; subsequent turns render correctly.

Both reproduce on current `main` and were introduced in #3867.

### Does this pull request fix one issue?

```
NONE
```

<!-- 若你先开了 issue，把上行替换为：Fixes #xxxx -->

### Describe how you did it

**Bug 1 — `currentPrompt` undefined.** The variable was referenced (to fill `promptKey`/`version`) but never declared. Resolve it from the already-loaded `prompts` state using the same lookup pattern used elsewhere in the file, and read the version from the correct field (`currentVersion.version` — prompt entries expose no top-level `latestVersion`):

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

**Bug 2 — React key collision.** The user message id was `Date.now() + prompt.id` and the assistant (streaming) message id was `Date.now()`. Since `prompt.id` is a small number (e.g. `1`) and the two `Date.now()` calls land within ~1 ms on the first turn, the two ids collide to the same value. React then reconciles the list with duplicate keys, so the user message content leaks into the assistant bubble. Give each message type a distinct prefix so keys can never collide:

```diff
// playground.jsx — user message
-          id: Date.now() + prompt.id,
+          id: `user-${Date.now()}-${prompt.id}`,

// streamingPrompt.ts — assistant (streaming) message
-      id: Date.now(),
+      id: `ai-${Date.now()}`,
```

### Describe how to verify it

1. Start the admin backend and frontend (`npm run dev`).
2. **Prompt工程 → Playground** → configure a prompt (template + variables + model) → type a message → **Send**.
3. Expectations:
   - No `ReferenceError` (Bug 1 fixed).
   - On the **first** turn, the assistant bubble shows only the model's reply — not the user's question (Bug 2 fixed). Send a few more turns; all render correctly.

### Special notes for reviews

- Two files changed: `frontend/packages/main/src/legacy/pages/playground/playground.jsx` (both fixes) and `frontend/packages/main/src/legacy/utils/streamingPrompt.ts` (assistant message id). No new dependencies.
- The two fixes are independent; both block the Playground chat-test.
- Both reproduce on current `main`; introduced in #3867 (Ken Liu, 2025-12-22).
- `streamingPrompt.ts` is a shared util, so the key-prefix fix also benefits any other caller of `executeStreamingPrompt`.

---

## 提交流程（参考）

1. Fork `alibaba/spring-ai-alibaba`（若还没有 upstream fork）。
2. 从干净 upstream main 拉分支：`git switch -c fix/playground-send-and-render upstream/main`。
3. 应用本改动（你本地工作区已是该状态——两个文件两处修复）。
4. **本地先确认**：首轮发送不崩、助手气泡只显示模型回复（已确认 ✓）。
5. `git push -u origin fix/playground-send-and-render` → GitHub 开 PR，base = `alibaba/spring-ai-alibaba:main`。
6. 标题/正文用上面这份；首次 PR 按 CLA bot 引导签个人 CLA。

> 注意：本 PR 只含这两个前端文件——别把本次会话里其它改动（outputSchema 后端修复、docs-research 文档）混进来。
