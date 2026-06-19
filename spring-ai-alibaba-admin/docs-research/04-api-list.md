# Spring AI Alibaba Admin — REST 接口清单

> 数据来源：扫描 `spring-ai-alibaba-admin` 下全部 32 个 `*Controller`（`openapi` / `admin` / `builder` / `generator` 四个模块目录），逐方法读取 `@GetMapping/@PostMapping/@PutMapping/@DeleteMapping/@PatchMapping/@RequestMapping` 映射后整理。
> 统计：**32 个 Controller · 约 211 个 REST 接口**。生成日期：2026-06-19。

## 目录

- [通用约定](#通用约定)
- [1. openapi 模块（对话 / 工作流运行时 API）](#1-openapi-模块对话--工作流运行时-api)
- [2. admin 模块（Agent Studio 评估与可观测 API）](#2-admin-模块agent-studio-评估与可观测-api)
- [3. builder 模块（应用构建控制台 API）](#3-builder-模块应用构建控制台-api)
- [4. generator 模块（代码生成与运行 API）](#4-generator-模块代码生成与运行-api)
- [附录：已知瑕疵与备注](#附录已知瑕疵与备注)

---

## 通用约定

| 项 | 说明 |
|---|---|
| 路径前缀 | `openapi` → `/api/v1/apps`；`admin` → `/api/*`；`builder` → `/console/v1/*`（另含 `/oauth2`、`/test/api/example`）；`generator` → `/graph-studio/api/*` 与根 `/` |
| 统一响应包装 | `admin` / `builder` 用 `Result<T>`；`generator` 用 `R<T>`。两套结构一致（`code`/`message`/`data`） |
| 分页 | `admin` 用 `Result<PageResult<T>>`；`builder` 用 `Result<PagingList<T>>`；查询入参多为 `*Request` 或 `BaseQuery`（`current`/`size`） |
| 流式响应 | 标注「流式」的接口返回 `SseEmitter`（SSE）或 `Flux<…>`（响应式流），非流式时返回普通 JSON |
| 鉴权 | `builder` 的 `/console/v1/*` 为登录态控制台接口（`AuthController` 颁发 token）；`admin` 的 `/api/*` 为平台内部接口；`generator` 面向工作台与 initializr |
| 实体直传 | 部分接口直接以领域实体（如 `Application`、`Tool`、`Workspace`）作为 `@RequestBody`，未单独建 DTO |

> 表格中类型用行内代码包裹（如 `Result<PromptVO>`），路径变量以 `{var}` 表示。

---

## 1. openapi 模块（对话 / 工作流运行时 API）

> 模块：`spring-ai-alibaba-admin-server-openapi`。面向前端/外部应用的对话与工作流执行入口。

### ChatController　`base: /api/v1/apps`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /api/v1/apps/chat/completions | 对话补全，支持流式与非流式响应 | `@RequestBody AgentRequest` | `Object`（流式为 SseEmitter，流式） |
| POST | /api/v1/apps/workflow/completions | 工作流补全，支持流式与非流式响应 | `@RequestBody WorkflowRequest` | `Object`（流式为 SseEmitter，流式） |
| POST | /api/v1/apps/workflow/async-completions | 异步触发工作流运行 | `@RequestBody WorkflowRequest` | `Result<TaskRunResponse>` |
| POST | /api/v1/apps/workflow/stop-completions | 停止运行中的工作流任务 | `@RequestBody TaskStopRequest` | `Result<Boolean>` |
| POST | /api/v1/apps/workflow/async-results | 查询异步工作流任务执行结果 | `@RequestBody AsyncResultRequest` | `Result<AsyncResultResponse>` |

---

## 2. admin 模块（Agent Studio 评估与可观测 API）

> 模块：`spring-ai-alibaba-admin-server-start` 的 `admin/controller` 目录。Prompt 工程、数据集、评估器、实验、模型配置、可观测（Trace）。

### DatasetController　`base: /api/dataset`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /api/dataset/dataset | 创建测评集 | `@RequestBody DatasetCreateRequest` | `Result<Dataset>` |
| POST | /api/dataset/datasetVersion | 创建测评集新版本 | `@RequestBody DatasetVersionCreateRequest` | `Result<DatasetVersion>` |
| GET | /api/dataset/datasets | 分页查询测评集列表 | `DatasetListRequest`（query） | `Result<PageResult<Dataset>>` |
| GET | /api/dataset/dataset | 查询测评集详情 | `@RequestParam datasetId` | `Result<Dataset>` |
| PUT | /api/dataset/dataset | 更新测评集 | `@RequestBody DatasetUpdateRequest` | `Result<Dataset>` |
| DELETE | /api/dataset/dataset | 删除测评集 | `@RequestParam datasetId` | `Result<Void>` |
| POST | /api/dataset/dataItem | 创建数据项 | `@RequestBody DatasetItemCreateRequest` | `Result<List<DatasetItem>>` |
| GET | /api/dataset/dataItems | 分页查询数据项列表 | `DatasetItemListRequest`（query） | `Result<PageResult<DatasetItem>>` |
| GET | /api/dataset/dataItem | 查询数据项详情 | `@RequestParam id`（见附录瑕疵） | `Result<DatasetItem>` |
| PUT | /api/dataset/dataItem | 更新数据项 | `@RequestBody DatasetItemUpdateRequest` | `Result<DatasetItem>` |
| DELETE | /api/dataset/dataItem | 删除数据项 | `@RequestParam id` | `Result<Void>` |
| GET | /api/dataset/datasetVersions | 分页查询测评集版本列表 | `DatasetVersionListRequest`（query） | `Result<PageResult<DatasetVersion>>` |
| PUT | /api/dataset/datasetVersion | 更新测评集版本 | `@RequestBody DatasetVersionUpdateRequest` | `Result<DatasetVersion>` |
| GET | /api/dataset/experiments | 查询数据集关联的实验列表 | `DatasetExperimentsListRequest`（query） | `Result<PageResult<Experiment>>` |
| POST | /api/dataset/dataItemFromTrace | 从 Trace 创建数据项 | `@RequestBody DataItemCreateFromTraceRequest` | `Result<List<DatasetItem>>` |

### EvaluatorController　`base: /api/evaluator`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /api/evaluator/evaluator | 创建评估器 | `@RequestBody EvaluatorCreateRequest` | `Result<Evaluator>` |
| POST | /api/evaluator/evaluatorVersion | 创建评估器版本 | `@RequestBody EvaluatorVersionCreateRequest` | `Result<EvaluatorVersion>` |
| GET | /api/evaluator/evaluators | 分页查询评估器列表 | `EvaluatorListRequest`（query） | `Result<PageResult<Evaluator>>` |
| GET | /api/evaluator/evaluator | 查询评估器详情 | query: `id` | `Result<Evaluator>` |
| GET | /api/evaluator/evaluatorVersions | 分页查询评估器版本列表 | `EvaluatorVersionListRequest`（query） | `Result<PageResult<EvaluatorVersion>>` |
| PUT | /api/evaluator/evaluator | 更新评估器 | `@RequestBody EvaluatorUpdateRequest` | `Result<Evaluator>` |
| DELETE | /api/evaluator/evaluator | 删除评估器 | `@RequestParam id` | `Result<Void>` |
| POST | /api/evaluator/debug | 调试评估器 | `@RequestBody EvaluatorTestRequest` | `Result<EvaluatorDebugResult>` |
| GET | /api/evaluator/templates | 分页查询评估模板列表 | `EvaluatorTemplateListRequest`（query） | `Result<PageResult<EvaluatorTemplate>>` |
| GET | /api/evaluator/template | 查询评估模板详情 | query: `templateId` | `Result<EvaluatorTemplate>` |
| GET | /api/evaluator/experiments | 分页查询评估器关联的实验 | `EvaluatorExperimentsListRequest`（query） | `Result<PageResult<Experiment>>` |

### ExperimentController　`base: /api`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /api/experiment | 创建实验 | `@RequestBody ExperimentCreateRequest` | `Result<Experiment>` |
| GET | /api/experiments | 分页查询实验列表 | `ExperimentListRequest`（query） | `Result<PageResult<Experiment>>` |
| GET | /api/experiment | 查询实验详情 | `@RequestParam experimentId` | `Result<Experiment>` |
| GET | /api/experiment/results | 查询实验概览结果（按评估器聚合） | `@RequestParam experimentId` | `Result<List<ExperimentEvaluatorResult>>` |
| GET | /api/experiment/result | 分页查询实验明细结果 | `ExperimentEvaluatorResultDetailListRequest`（query） | `Result<PageResult<ExperimentEvaluatorResultDetail>>` |
| PUT | /api/experiment/stop | 停止实验 | `@RequestParam experimentId` | `Result<Experiment>` |
| DELETE | /api/experiment | 删除实验 | `@RequestParam experimentId` | `Result<Void>` |
| PUT | /api/experiment/restart | 重启实验 | `@RequestParam experimentId` | `Result<Void>` |

### ModelConfigController　`base: /api`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /api/model/supported | 获取支持的模型提供商列表 | 无 | `Result<List<String>>` |
| GET | /api/models | 分页查询模型配置列表 | `ModelConfigQueryRequest`（query） | `Result<PageResult<ModelConfigResponse>>` |
| GET | /api/model | 查询模型配置详情 | `@RequestParam id` | `Result<ModelConfigResponse>` |
| GET | /api/models/enabled | 获取已启用的模型配置列表 | 无 | `Result<List<ModelConfigResponse>>` |

### ObservabilityController　`base: /api/observability`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /api/observability/traces | 分页查询 Trace 列表 | `TracesQueryRequest`（query） | `Result<PageResult<TraceSpanDTO>>` |
| GET | /api/observability/traces/{traceId} | 查询单个 Trace 详情 | `@PathVariable traceId` | `Result<TraceDetailDTO>` |
| GET | /api/observability/services | 查询服务列表 | `ServicesQueryRequest`（query） | `Result<ServicesResponseDTO>` |
| GET | /api/observability/overview | 查询可观测性概览统计 | `OverviewQueryRequest`（query） | `Result<OverviewStatsDTO>` |

### PromptController　`base: /api`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /api/prompt | 创建 Prompt | `@RequestBody PromptCreateRequest` | `Result<Prompt>` |
| GET | /api/prompt | 查询 Prompt 详情 | `@RequestParam promptKey` | `Result<Prompt>` |
| GET | /api/prompts | 分页查询 Prompt 列表 | `PromptListRequest`（query） | `Result<PageResult<Prompt>>` |
| PUT | /api/prompt | 更新 Prompt | `@RequestBody PromptUpdateRequest` | `Result<Prompt>` |
| DELETE | /api/prompt | 删除 Prompt | `@RequestParam promptKey` | `Result<Boolean>` |
| POST | /api/prompt/version | 创建 Prompt 版本 | `@RequestBody PromptVersionCreateRequest` | `Result<PromptVersion>` |
| GET | /api/prompt/version | 查询 Prompt 版本详情 | `@RequestParam promptKey`, `@RequestParam version` | `Result<PromptVersionDetail>` |
| GET | /api/prompt/versions | 分页查询 Prompt 版本列表 | `PromptVersionListRequest`（query） | `Result<PageResult<PromptVersion>>` |
| GET | /api/prompt/template | 查询 Prompt 模板详情 | `@RequestParam promptTemplateKey` | `Result<PromptTemplateDetail>` |
| GET | /api/prompt/templates | 分页查询 Prompt 模板列表 | `PromptTemplateListRequest`（query） | `Result<PageResult<PromptTemplate>>` |
| POST | /api/prompt/run | 运行 Prompt 调试（持续交互） | `@RequestBody PromptRunRequest` | `Flux<PromptRunResponse>`（流式，NDJSON） |
| GET | /api/prompt/session | 查询会话信息 | `@RequestParam sessionId` | `Result<ChatSession>` |
| DELETE | /api/prompt/session | 删除会话 | `@RequestParam sessionId` | `Result<Void>` |

---

## 3. builder 模块（应用构建控制台 API）

> 模块：`spring-ai-alibaba-admin-server-start` 的 `admin/builder/controller` 目录。21 个 Controller，覆盖账号/鉴权、应用、工作流、Agent、工具/插件、知识库/文档、模型供应商、MCP、组件、文件等控制台能力。

### AccountController　`base: /console/v1/accounts`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/accounts | 创建新用户账号 | `@RequestBody Account` | `Result<String>` |
| PUT | /console/v1/accounts/{accountId} | 更新指定账号信息 | `@PathVariable accountId`, `@RequestBody Account` | `Result<String>` |
| DELETE | /console/v1/accounts/{accountId} | 根据账号 ID 删除账号 | `@PathVariable accountId` | `Result<Void>` |
| GET | /console/v1/accounts/{accountId} | 根据 ID 获取账号信息 | `@PathVariable accountId` | `Result<Account>` |
| GET | /console/v1/accounts | 分页查询账号列表 | `@ApiModelAttribute BaseQuery query` | `Result<PagingList<Account>>` |
| PUT | /console/v1/accounts/change-password | 修改账号密码 | `@RequestBody ChangePasswordRequest` | `Result<String>` |
| GET | /console/v1/accounts/profile | 获取当前登录用户的账号资料 | 无 | `Result<Account>` |

### AgentSchemaController　`base: /console/v1/agent-schemas`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/agent-schemas | 创建新的 Agent Schema | `@RequestBody AgentSchemaEntity` | `Result<AgentSchemaEntity>` |
| PUT | /console/v1/agent-schemas/{id} | 更新已有的 Agent Schema | `@PathVariable id`, `@RequestBody AgentSchemaEntity` | `Result<AgentSchemaEntity>` |
| DELETE | /console/v1/agent-schemas/{id} | 删除 Agent Schema | `@PathVariable id` | `Result<Void>` |
| GET | /console/v1/agent-schemas/{id} | 根据 ID 获取 Agent Schema | `@PathVariable id` | `Result<AgentSchemaEntity>` |
| GET | /console/v1/agent-schemas | 获取当前工作空间下全部 Agent Schema | 无 | `Result<List<AgentSchemaEntity>>` |
| GET | /console/v1/agent-schemas/page | 分页查询 Agent Schema | `@RequestParam current`(可选), `@RequestParam size`(可选) | `Result<PagingList<AgentSchemaEntity>>` |
| GET | /console/v1/agent-schemas/search | 按名称搜索 Agent Schema | `@RequestParam name` | `Result<List<AgentSchemaEntity>>` |
| PATCH | /console/v1/agent-schemas/{id}/enabled | 启用或禁用 Agent Schema | `@PathVariable id`, `@RequestParam enabled` | `Result<Void>` |

### ApiExampleController　`base: /test/api/example`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /test/api/example/getOrder | GET 方式获取示例订单信息 | `@RequestHeader headers`, `HttpServletRequest` | `Map<String, Object>` |
| POST | /test/api/example/getOrder | POST 方式获取示例订单信息（需 orderId） | `@RequestHeader headers`, `@RequestBody Map body`, `HttpServletRequest` | `Map<String, Object>` |
| POST | /test/api/example/getOrder/{orderId} | 路径含 orderId 的 POST 方式获取订单信息 | `@RequestHeader headers`, `@PathVariable orderId`, `@RequestBody Map body`, `HttpServletRequest` | `Map<String, Object>` |

### ApiKeyController　`base: /console/v1/api-keys`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/api-keys | 创建新的 API Key | `@RequestBody ApiKey` | `Result<String>` |
| PUT | /console/v1/api-keys/{id} | 更新已有 API Key | `@PathVariable id`, `@RequestBody ApiKey` | `Result<String>` |
| DELETE | /console/v1/api-keys/{id} | 删除 API Key | `@PathVariable id` | `Result<Void>` |
| GET | /console/v1/api-keys/{id} | 获取指定 API Key 详情 | `@PathVariable id` | `Result<ApiKey>` |
| GET | /console/v1/api-keys | 分页查询 API Key 列表 | `@ModelAttribute BaseQuery query` | `Result<PagingList<ApiKey>>` |

### AppChatController　`base: /console/v1/apps`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/apps/chat/completions | 聊天补全接口，支持流式与非流式响应 | `@RequestBody AgentRequest`, `HttpServletResponse` | `Object`（流式为 SseEmitter，流式） |

### AppComponentController　`base: /console/v1/component-servers`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /console/v1/component-servers | 分页查询应用组件列表 | `@ApiModelAttribute AppComponentQuery request` | `Result<PagingList<AppComponent>>` |
| GET | /console/v1/component-servers/app-publishable | 分页查询可发布为组件的应用 | `@ApiModelAttribute AppComponentQuery request` | `Result<PagingList<Application>>` |
| POST | /console/v1/component-servers | 发布新的应用组件 | `@RequestBody AppComponentQuery request` | `Result<String>` |
| PUT | /console/v1/component-servers/{code} | 更新已有应用组件 | `@PathVariable code`, `@RequestBody AppComponentQuery request` | `Result<String>` |
| DELETE | /console/v1/component-servers/{code} | 根据组件 code 删除组件 | `@PathVariable code` | `Result<Boolean>` |
| GET | /console/v1/component-servers/{code}/detail-by-code | 按组件 code 获取组件详情（含合并后的配置） | `@PathVariable code` | `Result<AppComponent>` |
| GET | /console/v1/component-servers/{appId}/detail-by-appid | 按应用 ID 获取组件详情（含合并后的配置） | `@PathVariable appId` | `Result<AppComponent>` |
| GET | /console/v1/component-servers/{code}/query-refer | 查询引用了指定组件的组件列表 | `@PathVariable code` | `Result<List<AppComponent>>` |
| GET | /console/v1/component-servers/{appId}/query-config | 按应用 ID 查询组件配置 | `@PathVariable appId` | `Result<AppComponent>` |
| POST | /console/v1/component-servers/query-by-codes | 根据 codes 批量查询组件列表 | `@RequestBody AppComponentQuery request` | `Result<List<AppComponent>>` |
| GET | /console/v1/component-servers/{code}/query-schema | 按 code 查询单个组件的输入输出 schema | `@PathVariable code` | `Result<Map<String, Object>>` |
| POST | /console/v1/component-servers/schema-by-codes | 根据 codes 批量查询组件 schema | `@RequestBody AppComponentQuery request` | `Result<Map<String, Object>>` |

### AppController　`base: /console/v1/apps`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/apps | 创建新应用 | `@RequestBody Application` | `Result<String>` |
| PUT | /console/v1/apps/{appId} | 更新已有应用 | `@PathVariable appId`, `@RequestBody Application` | `Result<String>` |
| DELETE | /console/v1/apps/{appId} | 删除应用 | `@PathVariable appId` | `Result<Void>` |
| GET | /console/v1/apps/{appId} | 根据 ID 获取应用详情 | `@PathVariable appId` | `Result<Application>` |
| GET | /console/v1/apps | 分页查询应用列表 | `@ApiModelAttribute AppQuery query` | `Result<PagingList<Application>>` |
| POST | /console/v1/apps/{appId}/publish | 发布应用（工作流类型会校验配置） | `@PathVariable appId` | `Result<Void>` |
| GET | /console/v1/apps/{appId}/versions | 分页查询应用版本列表 | `@PathVariable appId`, `@ApiModelAttribute AppQuery query` | `Result<PagingList<ApplicationVersion>>` |
| GET | /console/v1/apps/{appId}/versions/{version} | 获取指定版本的详情 | `@PathVariable appId`, `@PathVariable version` | `Result<ApplicationVersion>` |
| POST | /console/v1/apps/{appId}/copy | 复制应用 | `@PathVariable appId` | `Result<String>` |

### AuthController　`base: /console/v1/auth`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/auth/login | 用户登录并返回访问令牌 | `@RequestBody LoginRequest` | `Result<TokenResponse>` |
| POST | /console/v1/auth/refresh-token | 使用 refresh token 刷新访问令牌 | `@RequestBody RefreshTokenRequest` | `Result<TokenResponse>` |
| POST | /console/v1/auth/logout | 登出并使访问令牌失效 | `HttpServletRequest`（从 Authorization 头取 token） | `Result<Void>` |

### DocumentChunkController　`base: /console/v1/documents`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/documents/{docId}/chunks | 创建新的文档切片 | `@PathVariable docId`, `@RequestBody DocumentChunk chunk` | `Result<String>` |
| PUT | /console/v1/documents/{docId}/chunks/{chunkId} | 更新已有文档切片 | `@PathVariable docId`, `@PathVariable chunkId`, `@RequestBody DocumentChunk chunk` | `Result<Void>` |
| DELETE | /console/v1/documents/{docId}/chunks/{chunkId} | 删除单个文档切片 | `@PathVariable docId`, `@PathVariable chunkId` | `Result<Void>` |
| DELETE | /console/v1/documents/{docId}/chunks/batch-delete | 批量删除文档切片 | `@PathVariable docId`, `@RequestBody DeleteChunkRequest request` | `Result<Void>` |
| GET | /console/v1/documents/{docId}/chunks | 分页查询文档切片列表 | `@PathVariable docId`, `@ModelAttribute BaseQuery query` | `Result<PagingList<DocumentChunk>>` |
| POST | /console/v1/documents/{docId}/chunks/preview | 预览索引前的文档切片 | `@PathVariable docId`, `@RequestBody IndexDocumentRequest request` | `Result<List<DocumentChunk>>` |
| PUT | /console/v1/documents/{docId}/chunks/update-status | 批量更新切片启用状态 | `@PathVariable docId`, `@RequestBody UpdateChunkRequest request` | `Result<Void>` |

### DocumentController　`base: /console/v1/knowledge-bases`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/knowledge-bases/{kbId}/documents | 在知识库中创建新文档 | `@PathVariable kbId`, `@RequestBody CreateDocumentRequest request` | `Result<List<String>>` |
| PUT | /console/v1/knowledge-bases/{kbId}/documents/{docId} | 更新已有文档 | `@PathVariable kbId`, `@PathVariable docId`, `@RequestBody Document document` | `Result<Void>` |
| DELETE | /console/v1/knowledge-bases/{kbId}/documents/{docId} | 删除单个文档 | `@PathVariable kbId`, `@PathVariable docId` | `Result<Void>` |
| DELETE | /console/v1/knowledge-bases/{kbId}/documents/batch-delete | 批量删除文档 | `@PathVariable kbId`, `@RequestBody DeleteDocumentRequest request` | `Result<Void>` |
| GET | /console/v1/knowledge-bases/{kbId}/documents/{docId} | 根据 ID 获取单个文档 | `@PathVariable kbId`, `@PathVariable docId` | `Result<Document>` |
| GET | /console/v1/knowledge-bases/{kbId}/documents | 分页查询知识库下的文档列表 | `@PathVariable kbId`, `@ApiModelAttribute DocumentQuery query` | `Result<PagingList<Document>>` |
| PUT | /console/v1/knowledge-bases/{kbId}/documents/{docId}/re-index | 按处理与切片配置对文档重新索引 | `@PathVariable kbId`, `@PathVariable docId`, `@RequestBody IndexDocumentRequest request` | `Result<Void>` |

### FileController　`base: /console/v1/files`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/files/upload | 上传多个文件并返回上传策略 | `@RequestPart files (MultipartFile[])`, `@RequestPart category` | `Result<List<UploadPolicy>>` |
| GET | /console/v1/files/download | 下载文件（支持浏览器预览） | `@RequestParam path`, `@RequestParam preview`(可选, 默认 false), `HttpServletResponse` | `void`（直接写回二进制流） |
| POST | /console/v1/files/upload-policies | 获取多文件 OSS 上传策略 | `@RequestBody WebUploadRequest request` | `Result<List<WebUploadPolicy>>` |
| GET | /console/v1/files/get-preview-url | 获取文件预览 URL | `@RequestParam path` | `Result<String>` |

### KnowledgeBaseController　`base: /console/v1/knowledge-bases`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/knowledge-bases | 创建知识库 | `@RequestBody KnowledgeBase` | `Result<String>` |
| PUT | /console/v1/knowledge-bases/{kbId} | 更新指定知识库 | `@PathVariable kbId`, `@RequestBody KnowledgeBase` | `Result<String>` |
| DELETE | /console/v1/knowledge-bases/{kbId} | 删除指定知识库 | `@PathVariable kbId` | `Result<Void>` |
| GET | /console/v1/knowledge-bases/{kbId} | 获取指定知识库详情 | `@PathVariable kbId` | `Result<KnowledgeBase>` |
| GET | /console/v1/knowledge-bases | 分页列出知识库 | `@ApiModelAttribute BaseQuery` | `Result<PagingList<KnowledgeBase>>` |
| POST | /console/v1/knowledge-bases/query-by-codes | 根据 ID 列表批量查询知识库 | `@RequestBody KnowledgeBaseQuery` | `Result<List<KnowledgeBase>>` |
| POST | /console/v1/knowledge-bases/retrieve | 检索与查询相关的文档分片 | `@RequestBody DocumentRetrieverQuery` | `Result<List<DocumentChunk>>` |

### McpServerController　`base: /console/v1/mcp-servers`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/mcp-servers | 创建 MCP 服务器 | `@RequestBody McpServerDetail` | `Result<String>` |
| PUT | /console/v1/mcp-servers | 更新 MCP 服务器配置 | `@RequestBody McpServerDetail` | `Result<String>` |
| DELETE | /console/v1/mcp-servers/{serverCode} | 删除指定 MCP 服务器 | `@PathVariable serverCode` | `Result<Void>` |
| GET | /console/v1/mcp-servers/{serverCode} | 获取 MCP 服务器详情，可附带工具信息 | `@PathVariable serverCode`, `@RequestParam need_tools` | `Result<McpServerDetail>` |
| GET | /console/v1/mcp-servers | 分页列出 MCP 服务器 | `@ApiModelAttribute McpQuery` | `Result<PagingList<McpServerDetail>>` |
| POST | /console/v1/mcp-servers/query-by-codes | 根据 serverCode 列表批量查询 MCP 服务器 | `@RequestBody McpQuery` | `Result<List<McpServerDetail>>` |
| POST | /console/v1/mcp-servers/debug-tools | 调试执行指定 MCP 服务器的工具 | `@RequestBody McpServerCallToolRequest` | `Result<McpServerCallToolResponse>` |

### ModelController　`base: /console/v1/models`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /console/v1/models/{modelType}/selector | 按模型类型获取已启用供应商及其模型分组 | `@PathVariable modelType` | `Result<List<ModelProviderGroup>>` |
| GET | /console/v1/models/enabled | 获取所有启用模型（兼容旧版 prompt API 格式） | 无 | `Result<List<Map<String, Object>>>` |

### Oauth2Controller　`base: /oauth2`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /oauth2/login/github | 获取 GitHub OAuth2 授权地址 | 无 | `Result<String>` |
| GET | /oauth2/callback/github | GitHub 授权回调，登录并重定向携带 token | `@RequestParam code`, `HttpServletResponse` | `void`（302 重定向） |

### PluginController　`base: /console/v1`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/plugins | 创建插件 | `@RequestBody Plugin` | `Result<String>` |
| PUT | /console/v1/plugins/{pluginId} | 更新指定插件 | `@PathVariable pluginId`, `@RequestBody Plugin` | `Result<Void>` |
| DELETE | /console/v1/plugins/{pluginId} | 删除指定插件 | `@PathVariable pluginId` | `Result<Void>` |
| GET | /console/v1/plugins/{pluginId} | 获取指定插件详情 | `@PathVariable pluginId` | `Result<Plugin>` |
| GET | /console/v1/plugins | 分页列出插件 | `@ModelAttribute BaseQuery` | `Result<PagingList<Plugin>>` |
| POST | /console/v1/plugins/{pluginId}/tools | 为插件创建工具 | `@PathVariable pluginId`, `@RequestBody Tool` | `Result<String>` |
| PUT | /console/v1/plugins/{pluginId}/tools/{toolId} | 更新指定工具 | `@PathVariable pluginId`, `@PathVariable toolId`, `@RequestBody Tool` | `Result<String>` |
| DELETE | /console/v1/plugins/{pluginId}/tools/{toolId} | 删除指定工具 | `@PathVariable pluginId`, `@PathVariable toolId` | `Result<Void>` |
| GET | /console/v1/plugins/{pluginId}/tools/{toolId} | 获取指定工具详情 | `@PathVariable pluginId`, `@PathVariable toolId` | `Result<Tool>` |
| GET | /console/v1/plugins/{pluginId}/tools | 分页列出插件下的工具 | `@PathVariable pluginId`, `@ModelAttribute ToolQuery` | `Result<PagingList<Tool>>` |
| POST | /console/v1/tools/{toolId}/enable | 启用指定工具 | `@PathVariable toolId` | `Result<Void>` |
| POST | /console/v1/tools/{toolId}/disable | 禁用指定工具 | `@PathVariable toolId` | `Result<Void>` |
| POST | /console/v1/plugins/{pluginId}/tools/{toolId}/test | 测试执行工具并更新测试状态 | `@PathVariable pluginId`, `@PathVariable toolId`, `@RequestBody ToolExecutionRequest` | `Result<ToolExecutionResult>` |
| POST | /console/v1/plugins/{pluginId}/tools/{toolId}/publish | 发布指定工具 | `@PathVariable pluginId`, `@PathVariable toolId` | `Result<Void>` |
| POST | /console/v1/tools/query-by-ids | 根据 ID 列表批量查询工具 | `@RequestBody ToolQuery` | `Result<List<Tool>>` |

### ProviderController　`base: /console/v1/providers`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/providers | 新增模型供应商（含凭证加密） | `@RequestBody AddProviderRequest` | `Result<Boolean>` |
| PUT | /console/v1/providers/{provider} | 更新指定供应商配置 | `@PathVariable provider`, `@RequestBody UpdateProviderRequest` | `Result<Boolean>` |
| DELETE | /console/v1/providers/{provider} | 删除指定供应商 | `@PathVariable provider` | `Result<Boolean>` |
| GET | /console/v1/providers | 查询供应商列表（带缓存，脱敏） | `@ModelAttribute QueryProviderRequest` | `Result<List<ProviderConfigInfo>>` |
| GET | /console/v1/providers/{provider} | 获取供应商详情（含凭证结构） | `@PathVariable provider` | `Result<ProviderConfigInfo>` |
| POST | /console/v1/providers/{provider}/models | 为供应商新增模型 | `@PathVariable provider`, `@RequestBody AddModelRequest` | `Result<Boolean>` |
| PUT | /console/v1/providers/{provider}/models/{modelId} | 更新指定模型配置 | `@PathVariable provider`, `@PathVariable modelId`, `@RequestBody UpdateModelRequest` | `Result<Boolean>` |
| DELETE | /console/v1/providers/{provider}/models/{modelId} | 删除指定模型 | `@PathVariable provider`, `@PathVariable modelId` | `Result<Boolean>` |
| GET | /console/v1/providers/{provider}/models | 列出供应商下的所有模型 | `@PathVariable provider` | `Result<List<ModelConfigInfo>>` |
| GET | /console/v1/providers/{provider}/models/{modelId} | 获取指定模型详情 | `@PathVariable provider`, `@PathVariable modelId` | `Result<ModelConfigInfo>` |
| GET | /console/v1/providers/{provider}/models/{modelId}/parameter_rules | 获取模型的参数规则 | `@PathVariable provider`, `@PathVariable modelId` | `Result<List<ParameterRule>>` |
| GET | /console/v1/providers/protocols | 获取支持的供应商协议列表 | 无 | `Result<List<String>>` |

### SystemController　`base: /console/v1/system`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /console/v1/system/global-config | 获取全局登录与上传方式配置 | 无 | `Result<GlobalConfig>` |
| GET | /console/v1/system/health | 健康检查 | 无 | `String` |

### ToolController　`base: /console/v1/tools`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/tools | 创建工具 | `@RequestBody ToolEntity` | `Result<ToolEntity>` |
| PUT | /console/v1/tools/{id} | 更新指定工具 | `@PathVariable id`, `@RequestBody ToolEntity` | `Result<ToolEntity>` |
| DELETE | /console/v1/tools/{id} | 删除指定工具 | `@PathVariable id` | `Result<Void>` |
| GET | /console/v1/tools/{id} | 获取指定工具详情 | `@PathVariable id` | `Result<ToolEntity>` |
| GET | /console/v1/tools | 获取当前工作区的所有工具 | 无 | `Result<List<ToolEntity>>` |
| GET | /console/v1/tools/page | 分页获取工具 | `@RequestParam current`(默认1), `@RequestParam size`(默认10) | `Result<PagingList<ToolEntity>>` |
| GET | /console/v1/tools/search | 按名称搜索工具 | `@RequestParam name` | `Result<List<ToolEntity>>` |
| GET | /console/v1/tools/plugin/{pluginId} | 按 pluginId 获取工具 | `@PathVariable pluginId` | `Result<List<ToolEntity>>` |
| PATCH | /console/v1/tools/{id}/enabled | 启用/禁用工具 | `@PathVariable id`, `@RequestParam enabled` | `Result<Void>` |

### WorkflowController　`base: /console/v1/apps`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/apps/workflow/debug/run-task | 调试模式执行工作流任务 | `@RequestBody TaskRunRequest` | `Result<TaskRunResponse>` |
| POST | /console/v1/apps/workflow/debug/get-task-process | 获取调试任务的执行进度与节点结果 | `@RequestBody ProcessGetRequest` | `Result<ProcessGetResponse>` |
| POST | /console/v1/apps/workflow/debug/init | 初始化工作流调试参数（系统+用户） | `@RequestBody InitRequest` | `Result<List<TaskRunParam>>` |
| POST | /console/v1/apps/workflow/debug/resume-task | 恢复暂停的工作流任务 | `@RequestBody TaskResumeRequest` | `Result<TaskResumeResponse>` |
| POST | /console/v1/apps/workflow/debug/part-graph/run-task | 执行部分工作流子图（用于局部测试） | `@RequestBody TaskPartGraphRequest` | `Result<TaskPartGraphResponse>` |
| POST | /console/v1/apps/workflow/debug/part-graph/stop-task | 停止部分图执行任务 | `@RequestBody TaskStopRequest` | `Result<Boolean>` |
| POST | /console/v1/apps/{appId}/run_stream | SSE 流式执行工作流并实时推送事件 | `@PathVariable appId`, `@RequestBody ApiTaskRunRequest` | `SseEmitter`（流式） |

### WorkspaceController　`base: /console/v1/workspaces`

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /console/v1/workspaces | 创建工作区 | `@RequestBody Workspace` | `Result<String>` |
| PUT | /console/v1/workspaces/{workspaceId} | 更新指定工作区 | `@PathVariable workspaceId`, `@RequestBody Workspace` | `Result<String>` |
| DELETE | /console/v1/workspaces/{workspaceId} | 删除指定工作区 | `@PathVariable workspaceId` | `Result<Void>` |
| GET | /console/v1/workspaces/{workspaceId} | 获取指定工作区详情 | `@PathVariable workspaceId` | `Result<Workspace>` |
| GET | /console/v1/workspaces | 分页列出工作区 | `@ModelAttribute BaseQuery` | `Result<PagingList<Workspace>>` |

---

## 4. generator 模块（代码生成与运行 API）

> 模块：`spring-ai-alibaba-admin-server-start` 的 `admin/builder/generator/controller` 目录。
> 注意：4 个 Controller 的端点均**不在自身声明**——`ApplicationController`/`DSLController`/`RunnerController` 通过 `implements XxxAPI` 继承接口里的 `default` 映射方法；`GeneratorController` 继承自 initializr 的 `ProjectGenerationController`。统一返回包装为 `R<T>`。

### ApplicationController　`base: /graph-studio/api/app`（接口 `AppAPI`）

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /graph-studio/api/app | 创建应用 | `@RequestBody CreateAppParam` | `R<App>` |
| GET | /graph-studio/api/app | 列出全部应用 | 无 | `R<List<App>>` |
| GET | /graph-studio/api/app/{id} | 根据 id 获取应用 | `@PathVariable id` | `R<App>` |
| PUT | /graph-studio/api/app | 同步应用（整体更新） | `@RequestBody App` | `R<App>` |
| DELETE | /graph-studio/api/app/{id} | 删除应用 | `@PathVariable id` | `R<Boolean>` |

### DSLController　`base: /graph-studio/api/dsl`（接口 `DSLAPI`）

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET | /graph-studio/api/dsl/export/{id} | 导出应用为 DSL 字符串 | `@PathVariable id`, `@RequestParam dialect` | `R<String>` |
| GET | /graph-studio/api/dsl/export-file/{id} | 导出应用为 DSL 文件下载（附件流） | `@PathVariable id`, `@RequestParam dialect` | `ResponseEntity<Resource>` |
| POST | /graph-studio/api/dsl/import | 从 DSL 内容导入并保存应用 | `@RequestBody DSLParam` | `R<App>` |
| POST | /graph-studio/api/dsl/import-file | 从上传的 DSL 文件导入并保存应用（multipart） | `@RequestPart file (MultipartFile)`, `@RequestParam dialect` | `R<App>` |

### GeneratorController　`base: /`（继承 `ProjectGenerationController`，initializr-web 0.22.0）

> 入参由 `@ModelAttribute GraphProjectRequest`（请求参数/头）绑定，非 `@RequestBody`。`/pom` 与 `/pom.xml`、`/build` 与 `/build.gradle` 为同一方法的 path 别名。

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| GET/POST | /pom | 生成 Maven `pom.xml`（仅构建文件） | `@ModelAttribute GraphProjectRequest` | `ResponseEntity<byte[]>` |
| GET/POST | /pom.xml | 同上，别名路径 | `@ModelAttribute GraphProjectRequest` | `ResponseEntity<byte[]>` |
| GET/POST | /build | 生成 Gradle `build.gradle`（仅构建文件） | `@ModelAttribute GraphProjectRequest` | `ResponseEntity<byte[]>` |
| GET/POST | /build.gradle | 同上，别名路径 | `@ModelAttribute GraphProjectRequest` | `ResponseEntity<byte[]>` |
| GET/POST | /starter.zip | 生成完整项目并打包为 zip 下载 | `@ModelAttribute GraphProjectRequest` | `ResponseEntity<byte[]>` |
| GET/POST | /starter.tgz | 生成完整项目并打包为 tar.gz 下载 | `@ModelAttribute GraphProjectRequest` | `ResponseEntity<byte[]>` |

### RunnerController　`base: /graph-studio/api/run`（接口 `RunnerAPI`）

| 方法 | 完整路径 | 一句话说明 | 主要入参 | 返回结构 |
|---|---|---|---|---|
| POST | /graph-studio/api/run/app/{id}/stream | 以流式模式运行应用（SSE/响应式流） | `@PathVariable id`, `@RequestBody Map<String, Object> inputs` | `Flux<RunEvent>`（流式） |
| POST | /graph-studio/api/run/app/{id}/sync | 以同步模式运行应用并返回最终事件 | `@PathVariable id`, `@RequestBody Map<String, Object> inputs` | `R<RunEvent>` |

---

## 附录：已知瑕疵与备注

源文件本身存在的小问题（如实记录，未臆造）：

- **`DatasetController.getItem`**：声明 `@PathVariable Long id`，但路径 `/api/dataset/dataItem` 没有 `{id}` 占位符，实际调用会失败；本表按 query 行为标注。
- **`DatasetController` 类注释**：多处将「版本」「关联实验」相关接口的 Javadoc 误写成「测评集」，已按真实方法名重写一句话说明。
- **`EvaluatorController.get` / `getTemplate`**：入参未加 `@RequestParam`，按 Spring 默认的 query 参数标注。
- **`PromptController.deleteSession`**：返回 `Result.success(null)`，声明返回结构为 `Result<Void>`。
- **`ToolController`**：多处工作区 ID 当前硬编码为 `"default"`（源码标注 TODO）。
- **`generator` 模块**：4 个 Controller 自身不含 handler 方法，端点来自 `AppAPI`/`DSLAPI`/`RunnerAPI` 接口（`.../builder/generator/api/`）与 initializr 父类 `io.spring.initializr.web.controller.ProjectGenerationController`（`initializr-web:0.22.0`）。仅读这 4 个文件会误判为「无接口」。
- **`GeneratorController` base 为根 `/`**：父子类都无 `@RequestMapping`，`/pom`、`/build`、`/starter.zip` 等直接挂应用根路径。

> 说明：本清单只列出带 HTTP 映射注解的 handler 方法；`@Bean`、私有方法、流式辅助方法（如 `sendStreamingResponse`）等未映射方法已排除。返回类型已解开 `ResponseEntity` 包装并保留泛型；流式接口（SSE/`Flux`）已显式标注。
