# 核心待测链路（10-critical-paths）

> 依据：[`04-api-list.md`](./04-api-list.md)（接口）、[`05-data-model.md`](./05-data-model.md)（数据模型）、[`CLAUDE.md`](../CLAUDE.md)（约定）。
> 目的：挑出**改造时最容易出问题**的链路作为回归重点，不是罗列全部链路。原则：宁少勿多。
> 入选标准（满足其一以上）：① 跨多个模块/领域 join；② 依赖外部系统（MQ / ES / 模型 / MCP / Nacos）；③ 有异步或状态机；④ 跨切面（鉴权/流式，爆炸半径大）。

## 总结表

| # | 链路名 | 起点（接口） | 关键节点（service / DB） | 终点（成功状态） | 改造易错点 |
|---|---|---|---|---|---|
| 1 | **登录鉴权**（跨切面） | `POST /console/v1/auth/login` | AuthController → TokenManager（签发 JWT）→ TokenAuthInterceptor（校验+注入用户）→ `account` 表(status) | 返回 `access_token`；任一受保护接口带 token 返回 200 | 拦截范围/排除路径、token 过期、账号 status；一坏全坏 |
| 2 | **Prompt 调试运行**（流式 + 内存会话） | `POST /api/prompt/run`（Flux 流式） | PromptController → PromptRunService → `ChatSession`（进程内 ConcurrentHashMap）→ 模型调用；`prompt`/`prompt_version` 表(status pre/release) | 流式返回多帧；`GET /api/prompt/session` 能取回会话、支持续轮 | Flux 背压/中断；会话**内存态易失**（重启丢）；版本状态切换 |
| 3 | **知识库文档索引**（MQ → ES） | `POST /console/v1/knowledge-bases/{kbId}/documents`（建文档）+ `PUT .../re-index` | DocumentController → DocumentService → **RocketMQ**(`topic_saa_studio_document_index`) → `ElasticSearchVectorStoreService` 写切片；`document.index_status` | `index_status=completed`；`POST .../retrieve` 能从 ES 检出切片 | 异步 MQ 丢失/重复；ES 向量写入；`index_status` 状态机(pending→processing→completed)；切片/分词 |
| 4 | **对话/工作流执行**（SSE 运行时） | `POST /api/v1/apps/chat/completions`、`/workflow/completions` | ChatController(openapi) → **graph-core 运行时** → 模型调用 → `SseEmitter` 流式；async 模式走 `TaskRunResponse` | 流式持续推送至完成、无 5xx；async 任务 `async-results` 可查 | SSE 连接超时/断连；graph 状态/节点异常；模型超时；流式中途中断 |
| 5 | **评估实验执行**（跨域 join + 异步状态机） | `POST /api/experiment`（创建）+ `PUT /api/experiment/{restart,stop}` | ExperimentController → ExperimentService：读 `dataset_version`(输入) × `evaluator_version`(打分器) → 模型打分 → 写 `experiment_result`；`experiment.status/progress` | `status=COMPLETED` 且 `experiment_result` 有 `score`+`reason` | 三域 join；模型批量打分失败/超时；`status` 状态机(DRAFT→RUNNING→COMPLETED/FAILED/STOPPED)；progress 不准；大批结果写入 |
| 6 | **Trace 链路摄取与查询**（OTLP → ES pipeline） | 摄取：外部 Agent 经 OTLP `:4318` → LoongCollector → ES；查询：`GET /api/observability/traces`、`/traces/{traceId}` | LoongCollector → ES ingest pipeline `parsing_loongsuite_traces` → 索引 `loongsuite_traces`；查询侧 `TracingRepository` 查 ES | 上报的 trace 能被 `/traces` 列出、`/traces/{id}` 详情含 span 树 | OTLP→pipeline 字段解析(json flattening/token 提取)；异步索引延迟；时序范围/聚合查询；空索引边界 |
| 7 | **MCP 工具调试**（外部 MCP 集成） | `POST /console/v1/mcp-servers/debug-tools` | McpServerController → **MCP SDK** 连接外部 MCP Server → 调用 tool → `McpServerCallToolResponse`；`mcp_server` 表(deploy_config/凭证) | 连上外部 MCP Server、指定 tool 执行并返回结果 | 外部服务连接/超时；MCP 协议/传输(npx/uvx/sse)；凭证；install_type 差异 |

## 为什么是这 7 条（而非更多）

每条都满足"改造易出问题"标准中的 ≥2 项。刻意**未列入**（集成度低、改造风险小，常规单测覆盖即可）：
- 纯 CRUD 资源：账号 / 工作区 / 插件 / 供应商 / 模型 / API Key / Agent Schema 的增删改查。
- App 发布/版本：虽有状态机(draft/published/publishedEditing)，但集成面窄、无外部系统，改造风险低于上述 7 条。
- 文件上传/下载、OAuth 回调：边界功能，非主干。

## 用法建议
- **回归优先级**：1–5 是主干（产品核心价值 + 高频改造），每次相关改动必测；6–7 改到可观测/MCP 时必测。
- **冒烟基线**：链路 1–2 的入口（login + prompt run）+ 链路 5 的只读查询，可作为最快环境健康探针（见 [`08-smoke-test-result.md`](./08-smoke-test-result.md)）。
- **每条都可映射到** 04 的接口 + 05 的表/实体，便于写针对性用例。
