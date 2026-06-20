# 16 · 完整使用案例：构建并评估一个「智能客服 Agent」

> 一句话目标：照着这份文档点一遍，你就能亲手走完 **Spring AI Alibaba Admin（Agent Studio）** 的全部核心链路，并理解它到底是个什么平台、各模块怎么串起来。
>
> 故事线：我们要为一家虚构电商 **SpringBoutique** 做一个智能客服——先写 Prompt 调试，再挂知识库增强，建成可对话的 Agent，最后用「数据集 + 评估器 + 实验」量化它的回答质量。
>
> 阅读约定：每个小节给出 **🖥️ 前端操作**（直接照着点 / 复制粘贴）+ **🔌 等价 API**（curl，给进阶/验证用）+ **✅ 验证**（怎么算成功）+ **📌 逻辑说明**（这步在平台上代表什么）。
> 依赖文档：[01 架构](./01-architecture.md) · [04 接口清单](./04-api-list.md) · [05 数据模型](./05-data-model.md) · [09 上手指南](./09-setup-guide.md) · [10 核心链路](./10-critical-paths.md)。

---

## 0. 案例总览：先搞懂这个平台是干什么的

### 0.1 平台定位

Agent Studio 是一个 **AI Agent 开发与评估平台**，覆盖 Agent 全生命周期：

```
Prompt 工程  →  数据集  →  评估器  →  实验与结果分析
```

外加两条横向能力：**应用可视化构建**（Agent / 工作流 / 知识库 / MCP / 工具）与**可观测**（Trace 链路追踪）。

它有两套并行的子系统，**新手最容易在这里绕晕**，先记牢：

| 子系统 | 在前端的位置 | 模型从哪来 | 干什么 |
|---|---|---|---|
| **构建控制台（builder）** | 侧栏「Agent Builder」「设置」 | `设置 → 模型服务管理`（DB `provider`/`model` 表） | 建 Agent / 工作流 / 知识库 / MCP，并**运行**它们 |
| **评估平台（admin）** | 侧栏「Prompt工程」「评测」 | `model-config.yml` 文件（热加载） | 写 Prompt、做测评集、跑评估实验 |

> ⚠️ **关键易错点**：两套子系统各自的模型配置是**独立**的。Prompt 调试 / 实验 失败，多半是 `model-config.yml` 没配；Agent 对话报错，多半是「模型服务管理」里没启用的供应商。下文 §1 会统一打通。

### 0.2 本案例的全链路地图（对应 [10 核心链路](./10-critical-paths.md)）

| 步骤 | 你做的事 | 对应核心链路 | 涉及模块 / 存储 |
|---|---|---|---|
| §1 | 登录、打通两套模型、拿 token | #1 登录鉴权 | `account` 表 · `TokenAuthInterceptor` |
| §2 | 写 Prompt + Playground 流式调试 | #2 Prompt 调试运行 | `prompt`/`prompt_version` · 进程内 `ChatSession` |
| §3 | 建知识库、传文档、检索 | #3 知识库文档索引 | `knowledge_base`/`document` · RocketMQ · **Elasticsearch** |
| §4 | 建 Agent 应用、绑定模型/知识库、SSE 对话 | #4 对话执行 | graph-core 运行时 · `application` 表 |
| §5 | 工作流编排（LLM 节点 → 测试 → 发布） | #4 工作流执行 | spark-flow 画布 · `application_version` |
| §6 | 测评集 → 评估器 → 实验 → 看分数 | #5 评估实验执行 | `dataset`/`evaluator`/`experiment` · **跨域 join** |
| §7 | 看 Tracing 链路 | #6 Trace 摄取与查询 | OTLP → ES `loongsuite_traces` |
| §8 | 注册 MCP 服务、调试工具 | #7 MCP 工具调试 | `mcp_server` · MCP SDK |

走完这 8 步 = 平台的 7 条核心链路全部覆盖。§7、§8 是扩展（依赖外部上报 / 外部 MCP 服务），跑不通不影响前 6 步。

---

## §1 前置准备：登录 + 打通两套模型 + 拿 token

> 前提：中间件与前后端已按 [09 上手指南](./09-setup-guide.md) 启动——前端 `http://localhost:8000`、后端 `http://localhost:8080`。

### 1.1 登录控制台（前端）

**🖥️ 前端操作**
1. 浏览器打开 `http://localhost:8000` → 自动跳到 `/login`（页头：`🎉 欢迎使用 Spring AI Alibaba Studio`）。
2. 账号 / 密码已预填（`.env` 的 `DEFAULT_USERNAME` / `DEFAULT_PASSWORD`）：**`saa` / `123456`**。
3. 点 **`登录`** → 成功后跳转到 `/app`（应用管理）。

**📌 逻辑**：登录走 `POST /console/v1/auth/login`，后端 `TokenManager` 签发 JWT；之后所有 `/console/v1/**` 请求被 `TokenAuthInterceptor` 拦截校验。这是核心链路 #1，**一坏全坏**。

### 1.2 打通「评估平台」的模型（model-config.yml）

评估平台（Prompt / 评估器 / 实验）的模型**只能**通过文件配置，接口写操作已禁用（会报「请使用 model-config.yml」）。

**🖥️ 前端无法配置，需改文件**——在 `spring-ai-alibaba-admin-server-start/` 下：

```bash
cd spring-ai-alibaba-admin-server-start
cp model-config-dashscope.yaml model-config.yaml   # 或 -openai.yaml / -deepseek.yaml
# 编辑 model-config.yaml，把 apiKey 填成你自己的真实 Key（或用环境变量占位）
```

`model-config.yaml` 最小内容（DashScope 示例，**`id` 很重要，后面 Prompt 引用它**）：

```yaml
models:
  - id: 1
    name: qwen-plus
    provider: dashscope
    modelName: qwen-plus
    baseUrl: https://dashscope.aliyuncs.com/compatible-mode
    apiKey: ${DASHSCOPE_API_KEY}     # 启动前 export DASHSCOPE_API_KEY=sk-xxx
    status: 1                         # 1=启用
    defaultParameters:
      temperature: 0.7
      maxTokens: 4096
```

> 该文件被 `WatchService` 监听，**保存即热加载**，无需重启。`apiKey` 支持 `${ENV}` 占位符，会被 `Environment.resolvePlaceholders` 替换。**切勿把含真实 Key 的 `model-config.yaml` 提交进 git**（已在 `.gitignore` 中）。

**✅ 验证**：

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/models/enabled
# data 数组非空、status=1 即成功
```

### 1.3 打通「构建控制台」的模型（模型服务管理）

Agent / 工作流 / 知识库运行时的模型来自这里。

**🖥️ 前端操作**
1. 侧栏 **`设置` → `模型服务管理`**（路径 `/setting/modelService`）。
2. 右上角 **`新增模型服务商`**（+ 图标）→ 选供应商（如 DashScope / OpenAI）→ 填 **API Key** 与 **Base URL** → 保存。
3. 在该供应商卡片下 **`新增模型`**（如 `qwen-plus`），类型选 `LLM`，**`启动`** 它（卡片提示 `启动成功`）。

**📌 逻辑**：供应商凭证写入 `provider.credential`（RSA 加密），模型写入 `model` 表；运行时 graph-core 据此建 `ChatClient`。

### 1.4 拿一个 Bearer Token（后续 curl 用）

```bash
export BASE=http://localhost:8080
export TOKEN=$(curl -s -X POST $BASE/console/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"saa","password":"123456"}' \
  | grep -oE '"access_token":"[^"]+"' | sed 's/"access_token":"//;s/"$//')
echo $TOKEN    # eyJ... 开头
```

> 下方所有 curl 假设已 `export BASE` 与 `export TOKEN`。`/console/v1/**` 与 `/api/*`（评估 / 可观测）用同一个 token 都能访问（见 [08 冒烟结果](./08-smoke-test-result.md)）。

---

## §2 Prompt 工程与 Playground 调试　〔核心链路 #2〕

> 目标：创建一条客服 Prompt，在 Playground 里流式调试，验证变量替换与多轮会话。

### 2.1 创建 Prompt 与版本（前端）

**🖥️ 前端操作**
1. 侧栏 **`Prompt工程` → `Prompts`**（`/admin/prompts`）→ 点 **`创建`**。
2. 填：
   - **Prompt Key**：`cs-faq`（只允许字母数字 `_ -`）
   - **描述**：`SpringBoutique 智能客服 FAQ`
3. 进入该 Prompt → **`新建版本`**，版本号 `1.0.0`，把下面模板粘进 **`template`**：

```text
你是 SpringBoutique 智能客服助手，负责解答顾客关于商品、订单物流、退换货政策的问题。

回答要求：
1. 仅基于已知信息回答，不编造政策细节；
2. 态度友好、语言简洁（3 句话以内）；
3. 若缺少必要信息（如订单号），请主动追问。

顾客问题：{{question}}
```

4. **变量** 填：`{"question":""}`（声明 `question` 这个变量）。
5. **模型** 从下拉选 §1.2 配好的模型（如 `qwen-plus`）→ **保存**。

**📌 逻辑**：变量用 `{{varname}}` 占位符；运行时 `ModelConfigParser.replaceVariables` 按变量值替换。版本状态 `pre`（预发布）/ `release`（正式）。

### 2.2 Playground 流式调试（前端）

**🖥️ 前端操作**
1. 侧栏 **`Prompt工程` → `Playground`**（`/admin/playground`）→ 选刚建的 `cs-faq` v`1.0.0`。
2. 在变量框填 `question = 退货流程是什么？` → 点 **`运行`**。
3. 观察回答**逐字流出**（SSE 流式），底部显示 token 用量与 traceId。
4. 再发一句 `那需要订单号吗？` → 验证**多轮上下文**被记住（会话存在进程内 `ChatSession`）。

**✅ 验证**：能拿到流式回答 + `traceId` 即成功；多轮能记住上文说明会话生效。

> ⚠️ **易失提醒**：`ChatSession` 存在进程内 `ConcurrentHashMap`，**后端重启会丢**（核心链路 #2 的已知特性）。

### 2.3 等价 API（curl）

```bash
# 流式调试（NDJSON 逐帧返回）：首帧是 session 信息，后续是内容帧，末帧是 metrics
curl -N -X POST $BASE/api/prompt/run \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{
    "newSession": true,
    "promptKey": "cs-faq",
    "version": "1.0.0",
    "variables": "{\"question\":\"退货流程是什么？\"}",
    "modelConfig": "{\"modelId\":1,\"temperature\":0.3}",
    "message": "退货流程是什么？"
  }'

# 取回会话（用首帧里的 sessionId 续轮）
curl -H "Authorization: Bearer $TOKEN" "$BASE/api/prompt/session?sessionId=<上一步的sessionId>"
```

**📌 字段坑**：admin 模块的 DTO 用 **驼峰**；`variables` / `modelConfig` 是**字符串化的 JSON**（要转义）。`modelConfig.modelId` 对应 §1.2 里 yaml 的 `id`。

---

## §3 知识库与文档检索　〔核心链路 #3〕

> 目标：建一个知识库，上传「退换货政策」文档，让系统切片入向量库，再检索验证。这是 RAG 的数据底座。

### 3.1 创建知识库并上传文档（前端）

**🖥️ 前端操作**
1. 侧栏 **`知识库`**（`/knowledge`）→ **`创建知识库`**（+ 图标）：
   - 名称：`cs-policy-kb`；类型默认 `unstructured`；选好**切片配置**（如按固定长度切分）与**索引配置**（向量模型，选 §1.3 启用的 embedding 模型）。
2. 打开该知识库 → **`文件列表`** → 点 **`上传`** → 上传下面这份 `退换货政策.md`（内容可直接复制存为 `.md`）：

```markdown
# SpringBoutique 退换货政策

- 7 天无理由退货：自签收之日起 7 天内，商品未使用、不影响二次销售，可申请退货。
- 退货流程：登录账户 → 我的订单 → 选择订单 → 申请退货 → 等待客服审核（1 个工作日）→ 快递取件。
- 换货：支持 15 天内换货，需商品完好；换货运费由责任方承担。
- 不支持退货商品：贴身衣物、定制商品、已拆封的密封商品。
- 退款到账：审核通过后 3-5 个工作日原路退回。
```

3. 上传后观察文档的 **`索引状态`** 从 `待处理 → 处理中 → 已完成`。

**📌 逻辑**（核心链路 #3）：建文档后，系统发 **RocketMQ** 消息（`topic_saa_studio_document_index`）→ 消费端调 `ElasticSearchVectorStoreService` 切片 + 算向量写入 **ES**。`document` 表只存元数据，**切片正文与向量在 ES**。这是异步状态机，需等 `index_status=completed`。

**✅ 验证**：索引状态变 `已完成` 后，在知识库详情页 **`检索测试`** 输入「定制商品能退货吗」→ 应召回含「定制商品不支持退货」的切片。

### 3.2 等价 API（curl）

```bash
# 检索（kbId 已知，返回命中的 DocumentChunk 列表）
# 注意：检索参数 query + search_options(kb_ids/top_k/enable_search...) 都是 snake_case
curl -X POST $BASE/console/v1/knowledge-bases/retrieve \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"query":"定制商品能退货吗","search_options":{"kb_ids":["<你的kbId>"],"top_k":3,"enable_search":true}}'
```

**📌 字段**：检索入参 `DocumentRetrieverQuery` = `query` + `search_options`（后者是 `FileSearchOptions`，含 `kb_ids`/`top_k`/`similarity_threshold`/`enable_rerank` 等，全 snake_case）。返回的 `DocumentChunk` 是**不落 MySQL** 的实体（见 [05 数据模型 §4](./05-data-model.md)），存于 ES；含 `text`（切片正文）、`score`（相关度）。

---

## §4 构建 Agent 应用并对话　〔核心链路 #4〕

> 目标：把前面的 Prompt + 知识库组装成一个可对外对话的智能体应用，用 SSE 跑起来。

### 4.1 创建并配置 Agent（前端）

**🖥️ 前端操作**
1. 侧栏 **`应用`**（`/app`）→ 右上 **`创建应用`** → 选 **`智能体应用`**（卡片说明「强大的 RAG、MCP、插件…能力」）→ 自动跳到 `/app/assistant/<appId>`。
2. 在 **`配置`** 面板（`AssistantConfig`，表单式，自动保存）：
   - **模型**：选 §1.3 启用的 LLM（如 `qwen-plus`）。
   - **Prompt**：粘贴 §2.1 的客服模板（或直接关联 `cs-faq`）。
   - **知识库**：勾选 §3.1 的 `cs-policy-kb`（开启 RAG）。
   - （可选）**开场白**：`您好，我是 SpringBoutique 客服，请问有什么可以帮您？`
3. 切到 **`发布`** 页 → 点 **`发布`**。
4. **记下地址栏的 `<appId>`**（下一步 curl 要用）。

**📌 逻辑**：应用配置存 `application` + `application_version`（`config` 为 JSON）；状态机 `草稿(1)→已发布(2)→发布编辑中(3)`。发布后才能被运行时调用。

### 4.2 SSE 对话（前端 + curl）

前端：应用详情页内置**调试对话窗**，直接发消息即可看到流式回复（走 `POST /api/v1/apps/chat/completions`）。

**🔌 等价 API（curl，注意 runtime 模块用 snake_case）**：

```bash
curl -N -X POST $BASE/api/v1/apps/chat/completions \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{
    "app_id": "<你的appId>",
    "conversation_id": "demo-001",
    "stream": true,
    "messages": [{"role":"user","content":"定制商品能退货吗？"}]
  }'
```

**✅ 验证**：流式持续推送到结束、无 5xx；回答引用了知识库的退换货政策（说明 RAG 生效）。

**📌 字段坑**：openapi/runtime 模块 DTO 用 **snake_case**（`app_id` / `conversation_id` / `messages` / `stream`）；与 §2 的 admin 模块驼峰**不同**，别混用。

---

## §5 工作流编排（扩展）　〔核心链路 #4 工作流侧〕

> 目标：用 spark-flow 画布拖一个「LLM 节点」工作流，单测 + 发布，体会可视化编排。

**🖥️ 前端操作**
1. **`应用` → `创建应用` → `工作流编排应用`** → 跳到 `/app/workflow/<appId>`（即 spark-flow 画布）。
2. 左侧节点面板拖入节点，连边：
   - **`开始`**（Start）→ 定义输入变量 `question`（String）。
   - **`大模型`**（LLM）→ 右侧配置面板填：**模型**选启用模型、**提示词**（sys）`你是 SpringBoutique 客服，简要回答`、**用户提示词**`{{question}}`。
   - → **`结束`**（End）→ 输出绑定 LLM 节点的输出。
3. 顶部 **`测试`**：填 `question=退款多久到账？` → 观察节点逐个亮起、实时输出（可对单个 LLM 节点点「单测」）。
4. 顶部 **`发布`**（主按钮）→ 成功弹窗可去「发布渠道」。

**📌 逻辑**：画布即 `@spark-ai/flow`（`packages/spark-flow`）；运行走 graph-core；可点 **`导出 SAA 工程代码`** 下载 `spring-ai-alibaba-demo.zip`（Spring Boot 3.5 · Java 17）。

**🔌 等价 API（同步跑工作流）**：

```bash
curl -X POST "$BASE/api/v1/apps/workflow/completions" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"app_id":"<workflowAppId>","stream":false,
       "messages":[{"role":"user","content":"退款多久到账？"}]}'
```

> 节点类型还有：知识检索 / 条件判断 / 意图分类 / 脚本 / 参数提取 / MCP / API / 插件 / 迭代 / 并行——按需拖。

---

## §6 评估闭环：测评集 → 评估器 → 实验　〔核心链路 #5〕

> 目标：把 §2 的 Prompt 当作「被评估对象」，用一批标注数据量化它答得好不好。这是平台**最核心、跨域最复杂**的链路。

> 全程模型用 §1.2 的 `model-config.yml`（id=1）。下面前端步骤为主，curl 给出**完整可复制的嵌套 JSON**。

### 6.1 创建测评集与数据项（前端）

**🖥️ 前端操作**
1. 侧栏 **`评测` → `评测集`**（`/admin/evaluation/gather`）→ **`创建`**：
   - 名称：`cs-eval-dataset`
   - 列结构（columns）：`input`（String / PlainText / 必填）、`reference_output`（String / PlainText）
2. 进入该集 → **`新增数据项`**，逐条录入下表（或批量导入）：

| input（顾客问题） | reference_output（标准答案） |
|---|---|
| 退货流程是什么？ | 登录账户进入我的订单，选订单后申请退货，等客服 1 个工作日审核，通过后快递取件，退款 3-5 个工作日原路退回。 |
| 换货有时间限制吗？ | 支持 15 天内换货，需商品完好，运费由责任方承担。 |
| 定制商品可以退货吗？ | 不可以，定制商品不支持退货。 |
| 退款多久到账？ | 审核通过后 3-5 个工作日原路退回。 |

3. 选中全部数据项 → **`发布版本`**（如 `1.0.0`）。**记下 `datasetId` 与 `datasetVersionId`**。

**📌 逻辑**：`dataset → dataset_version → dataset_item`（外键级联）；数据项的 `data_content` 是**按列顺序的位置数组**，约定列名 `input` / `reference_output` 供实验读取。

**🔌 等价 API（curl）**：

```bash
# 1) 建集
curl -X POST $BASE/api/dataset/dataset \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"cs-eval-dataset","description":"客服FAQ测评集",
       "columnsConfig":[
         {"name":"input","dataType":"STRING","displayFormat":"PLAIN_TEXT","required":true},
         {"name":"reference_output","dataType":"STRING","displayFormat":"PLAIN_TEXT","required":false}
       ]}'
# → 记下 data.id 作为 DATASET_ID

# 2) 建数据项（dataContent 按列顺序：input, reference_output）
curl -X POST $BASE/api/dataset/dataItem \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"datasetId":<DATASET_ID>,
       "columnsConfig":[
         {"name":"input","dataType":"STRING","displayFormat":"PLAIN_TEXT"},
         {"name":"reference_output","dataType":"STRING","displayFormat":"PLAIN_TEXT"}],
       "dataContent":["退货流程是什么？","登录账户进入我的订单，选订单后申请退货，等客服 1 个工作日审核，通过后快递取件，退款 3-5 个工作日原路退回。"]}'

# 3) 发布版本（datasetItems 传要纳入的 item id 列表）
curl -X POST $BASE/api/dataset/datasetVersion \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"datasetId":<DATASET_ID>,"version":"1.0.0","status":"PUBLISHED",
       "columnsConfig":[
         {"name":"input","dataType":"STRING","displayFormat":"PLAIN_TEXT"},
         {"name":"reference_output","dataType":"STRING","displayFormat":"PLAIN_TEXT"}],
       "datasetItems":[<item_id_1>,<item_id_2>,<item_id_3>,<item_id_4>]}'
# → 记下 data.id 作为 DATASET_VERSION_ID
```

### 6.2 创建评估器与版本（前端）

**🖥️ 前端操作**
1. 侧栏 **`评测` → `评估器`**（`/admin/evaluation/evaluator`）→ **`创建`**：名称 `cs-faithfulness`（忠实度评估）。
2. 进入 → **`新建版本`**（`1.0.0`），填：
   - **模型**：§1.2 的 `qwen-plus`（temperature 建议 0）。
   - **评估 Prompt**（judge）：

```text
你是客服回答质量评估员。请判断"模型回答"是否与"参考答案"要点一致、有无事实错误或编造。

用户问题：{{input}}
参考答案：{{reference_output}}
模型回答：{{actual_output}}

请只输出一个 0 到 1 之间的小数评分（1=完全一致且准确，0=完全错误或编造），并在评分后用一句话说明理由。
```

   - **变量**：`{"input":"","reference_output":"","actual_output":""}`。
3. 可先在 **`评测 → 调试`** 用一条样例试评。**记下 `evaluatorId` 与 `evaluatorVersionId`**。

**🔌 等价 API（curl）**：

```bash
# 建评估器
curl -X POST $BASE/api/evaluator/evaluator \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"cs-faithfulness","description":"客服回答忠实度评分"}'
# → 记下 data.id 作为 EVAL_ID

# 建版本
curl -X POST $BASE/api/evaluator/evaluatorVersion \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{
    "evaluatorId":"<EVAL_ID>","version":"1.0.0","status":"PUBLISHED",
    "modelConfig":"{\"modelId\":1,\"temperature\":0}",
    "prompt":"你是客服回答质量评估员……（同上 judge prompt）",
    "variables":"{\"input\":\"\",\"reference_output\":\"\",\"actual_output\":\"\"}"
  }'
# → 记下 data.id 作为 EVAL_VERSION_ID
```

### 6.3 创建并运行实验（前端）

**🖥️ 前端操作**
1. 侧栏 **`评测` → `实验`**（`/admin/evaluation/experiment`）→ **`创建实验`**：
   - **名称**：`cs-exp-v1`
   - **数据集**：选 `cs-eval-dataset` v`1.0.0`
   - **被评估对象**：选 **Prompt** → `cs-faq` v`1.0.0`；把 Prompt 的变量 `question` 映射到数据集列 `input`。
   - **评估器**：选 `cs-faithfulness` v`1.0.0`；变量映射：`input`←数据集列`input`、`reference_output`←数据集列`reference_output`、`actual_output`←`实际输出`。
2. **`运行`** → 观察进度条 `0% → 100%`，状态 `DRAFT → RUNNING → COMPLETED`。

**📌 逻辑**（核心链路 #5，跨域 join）：对数据集**每一条**，实验用数据集 `input` 喂给 Prompt 跑出 `actual_output`，再交给评估器（拿 `input`/`reference_output`/`actual_output`）打分，结果落 `experiment_result`（`score` + `reason`）。

**🔌 等价 API（curl，注意两个 config 字段都是「字符串化的 JSON」，且内层 config 再套一层字符串）**：

```bash
curl -X POST $BASE/api/experiment \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{
    "name":"cs-exp-v1",
    "description":"客服Prompt首轮评估",
    "datasetId":<DATASET_ID>,
    "datasetVersionId":<DATASET_VERSION_ID>,
    "datasetVersion":"1.0.0",
    "evaluationObjectConfig":"{\"type\":\"prompt\",\"config\":\"{\\\"promptKey\\\":\\\"cs-faq\\\",\\\"version\\\":\\\"1.0.0\\\",\\\"variableMap\\\":[{\\\"promptVariable\\\":\\\"question\\\",\\\"datasetVolumn\\\":\\\"input\\\"}]}\"}",
    "evaluatorConfig":"[{\"evaluatorId\":<EVAL_ID>,\"evaluatorVersionId\":<EVAL_VERSION_ID>,\"variableMap\":[{\"evaluatorVariable\":\"input\",\"source\":\"input\",\"dataSource\":\"\"},{\"evaluatorVariable\":\"reference_output\",\"source\":\"reference_output\",\"dataSource\":\"\"},{\"evaluatorVariable\":\"actual_output\",\"source\":\"actual_output\",\"dataSource\":\"\"}]}]"
  }'
```

> ⚠️ **三个必须照抄的字段坑**：
> 1. `evaluationObjectConfig` 与 `evaluatorConfig` 是**字符串**，内部 JSON 要整体转义。
> 2. 内层 Prompt 配置的 `config` **又是一层字符串**（双重转义）。
> 3. 变量映射里的列名字段是 **`datasetVolumn`**（源码如此拼写，**不是** `datasetColumn`，照抄即可）；`source:"actual_output"` 是保留值，表示取 Prompt 的实际输出，其它值按数据集列名读取。

### 6.4 查看实验结果（前端）

**🖥️ 前端操作**：打开实验详情 → **`结果`** 页：
- 概览：按评估器聚合的平均分（如 `cs-faithfulness 平均 0.82`）。
- 明细：逐条看 `输入 / 实际输出 / 参考输出 / 评分 / 评分理由`。

**✅ 验证**：`experiment.status=COMPLETED` 且 `experiment_result` 每条都有 `score`+`reason`。若某条分低，回 §2 调 Prompt，再跑一轮实验对比（这就是 Prompt 迭代闭环）。

**🔌 等价 API（curl）**：

```bash
# 概览（按评估器聚合）
curl -H "Authorization: Bearer $TOKEN" "$BASE/api/experiment/results?experimentId=<EXP_ID>"
# 明细分页
curl -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/experiment/result?experimentId=<EXP_ID>&evaluatorVersionId=<EVAL_VERSION_ID>&current=1&size=10"
```

---

## §7 可观测：链路追踪 Tracing　〔核心链路 #6〕

> 目标：看一次对话/调用的完整 Trace（哪步慢、哪步错）。Trace 来自外部 Agent 经 OTLP 上报，写入 ES。

**🖥️ 前端操作**：侧栏 **`可观测` → `Tracing`**（`/admin/tracing`）→ 选时间范围 → 看 Trace 列表，点单条看 **Span 树**（含各节点耗时、属性）。

> §2 的 Prompt 调试、§4 的对话都会生成 traceId（流式末帧可见），可在本页搜该 traceId 定位。

**🔌 等价 API（curl，⚠️ 时间参数必填）**：

```bash
# 近 30 天的 trace（startTime/endTime 是 epoch 毫秒，必填，否则 400）
START=$(($(date +%s%N)/1000000 - 30*86400000)); END=$(($(date +%s%N)/1000000 + 86400000))
curl -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/observability/traces?startTime=$START&endTime=$END"

# 单条详情（Span 树）
curl -H "Authorization: Bearer $TOKEN" "$BASE/api/observability/traces/<traceId>"
```

**📌 逻辑**（核心链路 #6）：数据**不来自 MySQL**，而是 ES 索引 `loongsuite_traces`（外部 Agent 经 OTLP `:4318` → LoongCollector → ES ingest pipeline）。全新环境索引为空、返回空列表属正常。

---

## §8 MCP 工具集成　〔核心链路 #7〕

> 目标：注册一个外部 MCP 服务器，调试它的工具，之后可在 Agent / 工作流里当节点用。

**🖥️ 前端操作**
1. 侧栏 **`MCP`**（`/mcp`）→ **`创建`**：
   - 名称：`time-mcp`；**安装方式**：`npx` / `uvx` / `sse` 三选一（如填一个 sse 地址或 npx 包名）。
   - **部署环境**：`local` / `remote`；填 `deploy_config`（连接/凭证）。
2. 打开详情 → **`调试工具`** → 选某个 tool → 填入参 → 执行，看返回。

**🔌 等价 API（curl）**：

```bash
# 注册（返回 serverCode / id）
curl -X POST $BASE/console/v1/mcp-servers \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"time-mcp","deployEnv":"remote","type":"CUSTOMER",
       "installType":"sse","host":"http://your-mcp-host:8080/sse","description":"时间/日期工具"}'

# 调试工具
curl -X POST $BASE/console/v1/mcp-servers/debug-tools \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"serverCode":"<serverCode>","toolName":"get_current_time","arguments":{}}'
```

**📌 逻辑**（核心链路 #7）：经 MCP SDK 连外部 MCP Server（传输差异在 `install_type`：npx/uvx/sse），调 tool 返回结果。**需要外部真有可达的 MCP 服务**才能跑通；纯本地环境这步可跳过，不影响前 6 步。

---

## §9 复盘：你刚走过的链路对应平台的什么

| 步骤 | 前端入口 | 核心链路 | 后端模块 | 主要存储 / 中间件 |
|---|---|---|---|---|
| §1 登录 | `/login` | #1 登录鉴权 | openapi 拦截器 | `account` 表 |
| §2 Prompt 调试 | `/admin/prompts`、`/admin/playground` | #2 Prompt 运行 | start(admin) | `prompt*` 表 · 内存 `ChatSession` · 外部模型 |
| §3 知识库 | `/knowledge` | #3 文档索引 | core(rag) | `knowledge_base`/`document` · **RocketMQ** · **ES** |
| §4 Agent 对话 | `/app/assistant/:id` | #4 对话执行 | openapi + graph-core | `application` 表 · 外部模型 |
| §5 工作流 | `/app/workflow/:id`（spark-flow） | #4 工作流执行 | start(builder) + graph-core | `application_version` |
| §6 评估实验 | `/admin/evaluation/*` | #5 评估实验 | start(admin) | `dataset`/`evaluator`/`experiment`（**跨域 join**） |
| §7 可观测 | `/admin/tracing` | #6 Trace 查询 | start(admin) | **ES** `loongsuite_traces`（OTLP 摄取） |
| §8 MCP | `/mcp` | #7 MCP 调试 | start(builder) | `mcp_server` 表 · 外部 MCP Server |

**回头看平台定位**，这次案例其实演练了 Agent Studio 的两条主轴：
- **纵向「构建」**（§2→§3→§4→§5）：把一个想法（Prompt）逐步武装成能检索知识、能编排、能对外服务的应用。
- **横向「评估」**（§6）：用数据集 + 评估器 + 实验，给应用/Prompt 一个**可量化的质量分数**，驱动迭代。加上 §7 可观测看运行时表现、§8 MCP 扩展工具能力，构成完整闭环。

记住那个一图流：**Prompt 工程 → 数据集 → 评估器 → 实验** 是评估主轴；**Agent / 工作流 / 知识库 / MCP / 工具** 是构建主轴；两轴在「应用」处交汇，可观测贯穿全程。

---

## 附录 A：一键复跑脚本（纯 curl）

> 把本文的 API 串起来跑。先完成 §1.2（model-config.yml）与 §1.3（模型服务管理），再 `export BASE` 与 `export TOKEN`（见 §1.4）。占位符（`<...>`）按各自返回的 id 替换。

```bash
set -e
BASE=http://localhost:8080
TOKEN=$(curl -s -X POST $BASE/console/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"saa","password":"123456"}' \
  | grep -oE '"access_token":"[^"]+"' | sed 's/"access_token":"//;s/"$//')
H="Authorization: Bearer $TOKEN"

# 健康探针
curl -s $BASE/actuator/health
curl -s -H "$H" $BASE/api/models/enabled          # 评估平台模型（需 model-config.yml）
curl -s -H "$H" $BASE/api/prompts                  # 应 200
curl -s -H "$H" $BASE/api/dataset/datasets         # 应 200
curl -s -H "$H" $BASE/api/evaluator/evaluators     # 应 200
START=$(($(date +%s%N)/1000000 - 30*86400000)); END=$(($(date +%s%N)/1000000 + 86400000))
curl -s -H "$H" "$BASE/api/observability/traces?startTime=$START&endTime=$END"   # 应 200

# 完整创建链：Prompt → Dataset(+版本) → Evaluator(+版本) → Experiment
# （见 §2.3 / §6.1 / §6.2 / §6.3 的 curl，把 <ID> 依次替换即可）
```

## 附录 B：字段坑与常见问题

| # | 现象 / 坑 | 原因 | 解法 |
|---|---|---|---|
| 1 | Prompt 运行 / 实验报「模型配置不存在/为空」 | 评估平台模型没配 | 配 `model-config.yml`（§1.2），`GET /api/models/enabled` 非空后再跑 |
| 2 | Agent 对话报模型错误 | 构建控制台模型没启用 | `设置 → 模型服务管理` 启用供应商与模型（§1.3） |
| 3 | admin 接口 400「字段缺失」 | DTO 用**驼峰**，且 `variables`/`modelConfig`/两个 `*Config` 是**字符串化 JSON**需转义 | 照 §2.3 / §6.3 的写法，注意双重转义 |
| 4 | openapi 接口字段不认 | runtime 模块用 **snake_case**（`app_id`/`messages`/`stream`） | 别和 admin 驼峰混用（§4.2） |
| 5 | 实验变量映射报错 | 列名字段拼写是 **`datasetVolumn`**（源码笔误，非 `datasetColumn`） | 照抄 `datasetVolumn`（§6.3） |
| 6 | Traces 接口 400 | `startTime`/`endTime` 必填（epoch 毫秒） | 带时间参数（§7） |
| 7 | 多轮对话「失忆」 | `ChatSession` 在进程内内存，**重启即丢** | 勿重启；如需持久化属已知限制（[05 §4.2](./05-data-model.md)） |
| 8 | 知识库检索空 | 文档 `index_status` 还没到 `completed`（异步 MQ+ES） | 等索引完成；检查 RocketMQ / ES 是否正常 |
| 9 | Tracing / MCP 列表空 | Trace 依赖外部 OTLP 上报；MCP 依赖外部可达服务 | 全新本地环境属正常，不影响前 6 步 |
| 10 | 后端启动告警「model-config.yml 以空配置启动」 | 文件没建或路径不对 | 在 `start` 模块根目录建 `model-config.yml`，或设 `MODEL_CONFIG_FILE` 环境变量 |

---

> 写完反馈：本案例的 8 步 = [10 核心链路](./10-critical-paths.md) 的全部 7 条；前端点击路径、默认账号、可复制内容（Prompt / 文档 / 测评数据 / 评估 Prompt）均已给出；curl 与字段坑经源码逐条核对（见各 📌）。如某步因外部依赖（模型 Key / MCP / OTLP）跑不通，属环境而非平台问题，按附录 B 排查。
