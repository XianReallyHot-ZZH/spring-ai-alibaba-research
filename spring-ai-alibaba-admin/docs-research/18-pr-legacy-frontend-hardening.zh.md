# PR（中文版）：fix(admin): harden legacy Playground/Evaluator frontend against crashes

> 提交目标：alibaba/spring-ai-alibaba。直接开 PR（四处修复都显而易见、无设计争议，其中两处直接复用代码库里已有的 `safeJSONParse`）。
> 英文版见同目录 [18-pr-legacy-frontend-hardening.md](./18-pr-legacy-frontend-hardening.md)。
> 四个独立的 legacy 前端崩溃 bug，都阻断相关功能、都由 #3867 引入。
> 改动 4 个文件，均在 `frontend/.../legacy/`。

---

## 标题

```
fix(admin): harden legacy Playground/Evaluator frontend against crashes
```

> 标题保持英文以过 `lint-pr-title.yml`（type=`fix`、scope=`admin` 均在白名单）。若想用中文描述，冒号后部分可写中文，依然过 lint——但国际评审场景下英文标题更稳妥。

## 正文（直接贴进 PR body）

### Describe what this PR does / why we need it

legacy 的 Playground 与 Evaluator 页面有四个独立的崩溃 bug（均由 #3867 引入），每个都让相关功能不可用：

1. **Playground——发送即崩**：点 **Send** 抛 `ReferenceError: currentPrompt is not defined`。
2. **Playground——首轮渲染错位**：首轮把用户自己的消息文本渲染进助手气泡（React key 冲突），第二轮起正常。
3. **Evaluator——列表崩**：任一评估器的 `modelConfig` 未设/非法时，列表抛 `SyntaxError: "undefined" is not valid JSON`。
4. **Evaluator——模板详情崩**：模板 modelConfig 展示在遇到非法 JSON 时崩（只靠 `modelConfig &&`，挡不住字符串 `"undefined"`）。

### Does this pull request fix one issue?

```
NONE
```

<!-- 若你先开了 issue，把上行替换为：Fixes #xxxx -->

### Describe how you did it

**Bug 1——`currentPrompt` 未定义**（`pages/playground/playground.jsx`）：变量被引用但从未声明。用文件已有的同款查找模式从 `prompts` 状态解析它，版本读 `currentVersion.version`：

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

**Bug 2——React key 冲突**（`playground.jsx` + `utils/streamingPrompt.ts`）：用户消息 id 为 `Date.now() + prompt.id`、助手消息 id 为 `Date.now()`；`prompt.id` 是小数字、首轮两次 `Date.now()` 相距 ~1ms → id 撞同值 → React 同 key 协调 → 用户内容漏进助手气泡。给两类消息加类型前缀，永不冲突：

```diff
// playground.jsx — 用户消息
-          id: Date.now() + prompt.id,
+          id: `user-${Date.now()}-${prompt.id}`,

// streamingPrompt.ts — 助手（流式）消息
-      id: Date.now(),
+      id: `ai-${Date.now()}`,
```

**Bug 3——Evaluator 列表裸 `JSON.parse`**（`pages/evaluation/evaluator/index.tsx`）：判空 + try/catch（代码库已有 `safeJSONParse`、兄弟位置也都有保护，这处漏了）：

```diff
// evaluator/index.tsx — modelConfig 列 render
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

**Bug 4——模板详情裸 `JSON.parse`**（`pages/evaluation/evaluator/evaluator-detail/index.tsx`）：改用现成的 `safeJSONParse`：

```diff
// evaluator-detail/index.tsx
+import { safeJSONParse } from '../../../../utils/util';
 ...
-                          {JSON.stringify(JSON.parse(selectedTemplateDetail.modelConfig), null, 2)}
+                          {JSON.stringify(safeJSONParse(selectedTemplateDetail.modelConfig, () => ({})), null, 2)}
```

### Describe how to verify it

1. 启动 admin 后端与前端（`npm run dev`）。
2. **Playground**：配置 prompt → Send → 不抛 ReferenceError；首轮助手气泡只显示模型回复、不混入用户问题。
3. **Evaluator**：即便有评估器没配 modelConfig 也能打开列表 → 不抛 SyntaxError；打开模板详情 → 不崩。

### Special notes for reviews

- 改动 4 个文件，均在 `frontend/packages/main/src/legacy/`。无新增依赖——Bug 3/4 直接复用已有的 `safeJSONParse` 工具 / 兄弟位置的保护写法。
- 四处均可在 current `main` 复现；由 #3867（Ken Liu，2025-12-22）引入。
- 这是一组源自 #3867 的 bug 的一部分（后端还有：outputSchema 的 `BeanUtils` 拷贝、RAG 的 `topK` NPE）。建议对 #3867 新增的 RAG + Playground + 评估链路做一次回归。

---

## 提交流程（参考）

1. Fork `alibaba/spring-ai-alibaba`（若还没有 upstream fork）。
2. 从干净 upstream main 拉分支：`git switch -c fix/legacy-frontend-hardening upstream/main`。
3. 应用本改动（你本地工作区已是该状态——4 个文件四处修复）。
4. **本地先确认**：Playground 发送不崩且首轮渲染正常、Evaluator 列表/详情不崩（已确认 ✓）。
5. `git push -u origin fix/legacy-frontend-hardening` → GitHub 开 PR，base = `alibaba/spring-ai-alibaba:main`。
6. 标题/正文用上面这份；首次 PR 按 CLA bot 引导签个人 CLA。

> 注意：本 PR 只含这 4 个 legacy 前端文件——别把后端修复（outputSchema、RAG topK）或 docs-research 文档混进来。
