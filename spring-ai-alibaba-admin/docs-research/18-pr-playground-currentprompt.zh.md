# PR（中文版）：fix(admin): fix Playground send crash and message key collision

> 提交目标：alibaba/spring-ai-alibaba。直接开 PR（两处修法都显而易见、无设计争议）。
> 英文版见同目录 [18-pr-playground-currentprompt.md](./18-pr-playground-currentprompt.md)。
> legacy Playground 对话测试的两个独立 bug，都阻断该功能、都由 #3867 引入。
> 改动 2 个文件：`frontend/.../legacy/pages/playground/playground.jsx` + `frontend/.../legacy/utils/streamingPrompt.ts`。

---

## 标题

```
fix(admin): fix Playground send crash and message key collision
```

> 标题保持英文以过 `lint-pr-title.yml`（type=`fix`、scope=`admin` 均在白名单）。若想用中文描述，冒号后部分可写中文，依然过 lint——但国际评审场景下英文标题更稳妥。

## 正文（直接贴进 PR body）

### Describe what this PR does / why we need it

legacy 的 Playground 对话测试有两个 bug，合起来让该功能完全不可用：

1. **发送即崩**：点击 **Send** 抛 `Unhandled Rejection (ReferenceError): currentPrompt is not defined`（`runSinglePrompt` 内），任何消息都发不出去。
2. **首轮渲染错位**：首轮对话时，用户自己的消息文本会被渲染进**助手的回复气泡**里；第二轮起恢复正常。

两处均可在 current `main` 复现，由 #3867 引入。

### Does this pull request fix one issue?

```
NONE
```

<!-- 若你先开了 issue，把上行替换为：Fixes #xxxx -->

### Describe how you did it

**Bug 1 — `currentPrompt` 未定义。** 该变量被引用（填充 `promptKey`/`version`）但从未声明。用文件里已有的同款查找模式，从已加载的 `prompts` 状态里解析它，并从正确字段 `currentVersion.version` 读版本（prompt 条目没有顶层 `latestVersion`）：

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

**Bug 2 — React key 冲突。** 用户消息 id 原为 `Date.now() + prompt.id`，助手（流式）消息 id 原为 `Date.now()`。由于 `prompt.id` 是个小数字（如 `1`），且首轮两次 `Date.now()` 调用相距仅 ~1ms，两个 id 会撞到同一个值；React 随后用重复 key 协调列表，导致用户消息内容漏进助手气泡。给两类消息各加类型前缀，key 永不冲突：

```diff
// playground.jsx — 用户消息
-          id: Date.now() + prompt.id,
+          id: `user-${Date.now()}-${prompt.id}`,

// streamingPrompt.ts — 助手（流式）消息
-      id: Date.now(),
+      id: `ai-${Date.now()}`,
```

### Describe how to verify it

1. 启动 admin 后端与前端（`npm run dev`）。
2. **Prompt工程 → Playground** → 配置一个 prompt（模板 + 变量 + 模型）→ 输入消息 → **Send**。
3. 预期：
   - 不再抛 `ReferenceError`（Bug 1 修复）。
   - **首轮**助手气泡只显示模型回复、不混入用户问题（Bug 2 修复）。多发几轮，渲染均正常。

### Special notes for reviews

- 改动 2 个文件：`frontend/packages/main/src/legacy/pages/playground/playground.jsx`（两处修复）+ `frontend/packages/main/src/legacy/utils/streamingPrompt.ts`（助手消息 id）。无新增依赖。
- 两处修复相互独立；都阻断 Playground 对话测试。
- 均可在 current `main` 复现；由 #3867（Ken Liu，2025-12-22）引入。
- `streamingPrompt.ts` 是共享 util，key 前缀修复也惠及 `executeStreamingPrompt` 的其它调用方。

---

## 提交流程（参考）

1. Fork `alibaba/spring-ai-alibaba`（若还没有 upstream fork）。
2. 从干净 upstream main 拉分支：`git switch -c fix/playground-send-and-render upstream/main`。
3. 应用本改动（你本地工作区已是该状态——两个文件两处修复）。
4. **本地先确认**：首轮发送不崩、助手气泡只显示模型回复（已确认 ✓）。
5. `git push -u origin fix/playground-send-and-render` → GitHub 开 PR，base = `alibaba/spring-ai-alibaba:main`。
6. 标题/正文用上面这份；首次 PR 按 CLA bot 引导签个人 CLA。

> 注意：本 PR 只含这两个前端文件——别把本次会话里其它改动（outputSchema 后端修复、docs-research 文档）混进来。
