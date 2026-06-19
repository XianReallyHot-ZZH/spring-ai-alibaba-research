# Spring AI Alibaba Admin — 核心数据模型

> 数据来源：`docker/middleware/init/mysql/agentscope-schema.sql`（builder 平台，库 `agentscope`）、`docker/middleware/init/mysql/admin-schema.sql`（评估平台，库 `admin`），并对照 MyBatis-Plus 实体（`admin-server-core/.../core/base/entity/*Entity`）与 DO（`admin-server-start/.../admin/entity/*DO`）。
> 统计：**2 个数据库 · 27 张表**。生成日期：2026-06-19。ER 图见 [06-data-model-er.svg](./06-data-model-er.svg)。
>
> 另有 6 个 API 暴露的领域对象**不落 MySQL**（Elasticsearch 向量库 / Elasticsearch traces / 进程内内存），与 [04-api-list.md](./04-api-list.md) 交叉核对后补录于第四节。

## 目录

- [通用约定](#通用约定)
- [一、Builder 平台（agentscope 库，15 表）](#一builder-平台agentscope-库15-表)
- [二、评估平台（admin 库，12 表）](#二评估平台admin-库12-表)
- [三、关键关系说明（对应 ER 图）](#三关键关系说明对应-er-图)
- [四、API 引用但非 MySQL 持久化的实体（与 04 交叉核对补遗）](#四api-引用但非-mysql-持久化的实体与-04-交叉核对补遗)

---

## 通用约定

### 图例

| 标记 | 含义 |
|---|---|
| `PK` | 主键（自增 BIGINT） |
| `FK` | 外键 / 逻辑外键（引用其它表的业务键，见各表说明） |
| `UK` | 唯一键 |
| `🔢` | 枚举字段（取值见说明列） |

### 两个数据库

- **agentscope 库**（builder 平台）：账号 / 工作区 / 应用 / 工作流 / 插件 / 工具 / 知识库 / 文档 / 模型供应商 / MCP / Agent。**无数据库级外键约束**，关系靠业务键（`workspace_id` / `app_id` / `kb_id` / `plugin_id` / `account_id` / `provider`）+ 索引维系。
- **admin 库**（评估平台）：Prompt / 数据集 / 评估器 / 实验 / 模型配置。**有显式外键约束**（`dataset_*` → `dataset`，`evaluator_version` → `evaluator`）。

### 通用审计字段

| 库 | 审计字段 | 说明 |
|---|---|---|
| agentscope | `gmt_create` / `gmt_modified` (DATETIME) / `creator` / `modifier` (VARCHAR(64)) | 创建/修改时间、创建者/修改者 uid；多数表还有 `status`（逻辑删除 0/1） |
| admin | `create_time` / `update_time` (DATETIME) / `deleted` (TINYINT 0/1) | 创建/更新时间、逻辑删除标识（部分表） |

> 下方每张表的审计字段均列出，描述从简。

### Java 实体映射

| 表 | Java 实体 | 表 | Java 实体 |
|---|---|---|---|
| account | `AccountEntity` | dataset | `DatasetDO` |
| workspace | `WorkspaceEntity` | dataset_version | `DatasetVersionDO` |
| application | `AppEntity` | dataset_item | `DatasetItemDO` |
| application_version | `AppVersionEntity` | evaluator | `EvaluatorDO` |
| plugin | `PluginEntity` | evaluator_version | `EvaluatorVersionDO` |
| tool | `ToolEntity` | evaluator_template | `EvaluatorTemplateDO` |
| knowledge_base | `KnowledgeBaseEntity` | experiment | `ExperimentDO` |
| document | `DocumentEntity` | experiment_result | `ExperimentResultDO` |
| application_component | `AppComponentEntity` | prompt | `PromptDO` |
| reference | `ReferEntity` | prompt_version | `PromptVersionDO` |
| mcp_server | `McpServerEntity` | prompt_build_template | `PromptTemplateDO` |
| provider | `ProviderEntity` | model_config | `ModelConfigDO` |
| model | `ModelEntity` | | |
| agent_schema | `AgentSchemaEntity` | | |
| api_key | `ApiKeyEntity` | | |

---

## 一、Builder 平台（agentscope 库，15 表）

### 1. account　账号（`AccountEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| account_id | VARCHAR(64) | UK | 账号业务 ID |
| username | VARCHAR(255) | | 账号名 |
| email | VARCHAR(255) | | 邮箱 |
| mobile | VARCHAR(255) | | 手机号 |
| password | VARCHAR(255) | | 密码（Argon2 哈希） |
| nickname | VARCHAR(255) | | 昵称 |
| icon | VARCHAR(255) | | 头像 |
| type | VARCHAR(64) | 🔢 | 账号类型：`basic`、`admin` |
| status | TINYINT(4) | 🔢 | 状态：0-已删除，1-正常 |
| gmt_create / gmt_modified | DATETIME | | 创建/修改时间 |
| gmt_last_login | DATETIME | | 最近登录时间 |
| creator / modifier | VARCHAR(64) | | 创建/修改者 uid |

### 2. workspace　工作区（`WorkspaceEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| workspace_id | VARCHAR(64) | UK | 工作区业务 ID |
| account_id | VARCHAR(64) | FK→account | 归属账号 |
| status | TINYINT(4) | 🔢 | 0-已删除，1-正常 |
| name | VARCHAR(255) | | 工作区名称 |
| description | VARCHAR(4096) | | 描述 |
| config | TEXT | | 工作区配置 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

> 工作区是 builder 平台的核心隔离边界，几乎所有资源（应用/插件/知识库/MCP/模型）都挂在 `workspace_id` 下。

### 3. application　应用（`AppEntity`，表名 `application`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT | PK | 自增主键 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| app_id | VARCHAR(64) | UK | 应用业务 ID |
| name | VARCHAR(255) | | 应用名 |
| description | VARCHAR(4096) | | 描述 |
| icon | VARCHAR(255) | | 图标 |
| source | VARCHAR(64) | | 来源 |
| type | VARCHAR(64) | 🔢 | 应用类型：`agent`、`workflow` |
| status | TINYINT(4) | 🔢 | 0-已删除，1-草稿，2-已发布，3-发布编辑中 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 4. application_version　应用版本（`AppVersionEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| app_id | VARCHAR(64) | FK→application | 所属应用 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| config | LONGTEXT | | 应用配置（JSON） |
| status | TINYINT(4) | 🔢 | 0-已删除，1-草稿，2-已发布，3-发布编辑中 |
| version | VARCHAR(32) | | 版本号（默认 `0.0.1`） |
| description | VARCHAR(4096) | | 版本描述 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 5. plugin　插件（`PluginEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| plugin_id | VARCHAR(64) | UK | 插件业务 ID |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| type | VARCHAR(64) | 🔢 | 1-官方，2-自定义 |
| status | TINYINT(4) | 🔢 | 0-已删除，1-正常 |
| name / description | VARCHAR | | 名称/描述 |
| config | TEXT | | 插件配置 |
| source | VARCHAR(64) | | 来源 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 6. tool　工具（`ToolEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| plugin_id | VARCHAR(64) | FK→plugin | 所属插件 |
| tool_id | VARCHAR(64) | UK | 工具业务 ID |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| status | TINYINT(4) | 🔢 | 0-已删除，1-正常 |
| enabled | TINYINT(4) | 🔢 | 0-禁用，1-启用 |
| test_status | TINYINT(4) | 🔢 | 测试状态：1-未测试，2-通过，3-失败 |
| name / description | VARCHAR | | 名称/描述 |
| config | LONGTEXT | | 工具配置 |
| api_schema | LONGTEXT | | 工具 API schema |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 7. knowledge_base　知识库（`KnowledgeBaseEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| kb_id | VARCHAR(64) | UK | 知识库业务 ID |
| type | VARCHAR(64) | 🔢 | 类型：`unstructured` |
| status | TINYINT(4) | 🔢 | 0-已删除，1-正常 |
| name / description | VARCHAR | | 名称/描述 |
| process_config | TEXT | | 处理配置（切分等） |
| index_config | TEXT | | 索引配置（向量库等） |
| search_config | TEXT | | 检索配置 |
| total_docs | BIGINT(20) | | 文档总数 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 8. document　文档（`DocumentEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| kb_id | VARCHAR(64) | FK→knowledge_base | 所属知识库 |
| doc_id | VARCHAR(64) | UK | 文档业务 ID |
| type | VARCHAR(64) | 🔢 | 来源类型：`file`、`url` |
| status | TINYINT(4) | 🔢 | 0-已删除，1-正常 |
| enabled | TINYINT(4) | 🔢 | 0-禁用，1-启用 |
| name | VARCHAR(255) | | 文档名 |
| format | VARCHAR(64) | | 格式（pdf/md/...） |
| size | BIGINT(20) | | 大小 |
| metadata | TEXT | | 元数据 |
| index_status | TINYINT(4) | 🔢 | 索引状态：1-待处理，2-处理中，3-已完成 |
| path / parsed_path | VARCHAR(512) | | 存储/解析后路径 |
| process_config | TEXT | | 切片配置 |
| source / error | VARCHAR/TEXT | | 来源/错误信息 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 9. application_component　应用组件（`AppComponentEntity`）

> 把一个应用封装为可复用组件，供其它应用引用。

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT | PK | 自增主键 |
| code | VARCHAR(64) | | 组件 code（业务标识） |
| name | VARCHAR(128) | | 组件名 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| type | VARCHAR(64) | 🔢 | `agent`、`workflow` |
| app_id | VARCHAR(64) | FK→application | 关联应用（可空） |
| config | LONGTEXT | | 组件配置 |
| description | VARCHAR(4096) | | 描述 |
| status | TINYINT | 🔢 | 0-已删除，1-正常，2-已发布 |
| need_update | TINYINT | 🔢 | 0-无需更新，1-需更新 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 10. reference　引用关系（`ReferEntity`，表名 `reference`）

> 多态引用表：记录任意主实体（`main_*`）引用了哪些被引实体（`refer_*`）。

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| main_code | VARCHAR(64) | | 主实体 code |
| main_type | TINYINT | 🔢 | 主实体类型 |
| refer_code | VARCHAR(64) | | 被引用实体 code |
| refer_type | TINYINT | 🔢 | 被引用实体类型 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区（默认 1） |
| gmt_create / gmt_modified | DATETIME | | 审计字段 |

### 11. mcp_server　MCP 服务器（`McpServerEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| server_code | VARCHAR(64) | | 服务器 code |
| name | VARCHAR(64) | | 名称 |
| description | VARCHAR(1024) | | 描述 |
| source | VARCHAR(128) | | 来源 |
| deploy_env | VARCHAR(16) | 🔢 | 部署环境：`local`、`remote` |
| type | VARCHAR(32) | 🔢 | 服务器类型：`OFFICIAL`、`CUSTOMER` |
| deploy_config | TEXT | | 部署配置 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| account_id | VARCHAR(64) | FK→account | 所属账号 |
| status | TINYINT | 🔢 | 0-不可用，1-正常，3-已删除 |
| biz_type / detail_config | VARCHAR/TEXT | | 业务类型/详情 |
| host | VARCHAR(1024) | | 主机地址 |
| install_type | VARCHAR(32) | 🔢 | 安装方式：`npx`、`uvx`、`sse` |
| gmt_create / gmt_modified | DATETIME | | 审计字段 |

### 12. provider　模型供应商（`ProviderEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT | PK | 自增主键 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| icon / name / description | VARCHAR | | 图标/名称/描述 |
| provider | VARCHAR(255) | | 供应商标识（如 Tongyi、OpenAI） |
| enable | TINYINT(1) | 🔢 | 0-禁用，1-启用 |
| source | VARCHAR(64) | 🔢 | `preset`、`custom` |
| credential | VARCHAR(1024) | | 访问凭证（JSON，加密） |
| supported_model_types | VARCHAR(255) | | 支持的模型类型 |
| protocol | VARCHAR(64) | | 协议（如 `openai`） |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 13. model　模型（`ModelEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT | PK | 自增主键 |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| icon / name | VARCHAR | | 图标/名称 |
| type | VARCHAR(100) | 🔢 | 模型类型：`LLM`、`text_embedding`、`rerank` |
| mode | VARCHAR(100) | | 模式（如 `chat`） |
| model_id | VARCHAR(100) | | 模型标识（如 qwen-max） |
| provider | VARCHAR(100) | FK→provider | 所属供应商 |
| enable | TINYINT(1) | 🔢 | 0-禁用，1-启用 |
| tags | VARCHAR(255) | | 标签（function_call/vision/reasoning...） |
| source | VARCHAR(100) | 🔢 | `preset`、`custom` |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 14. agent_schema　Agent 配置（`AgentSchemaEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| agent_id | VARCHAR(64) | UK | Agent 业务 ID |
| workspace_id | VARCHAR(64) | FK→workspace | 所属工作区 |
| name / description | VARCHAR | | 名称/描述 |
| type | VARCHAR(64) | 🔢 | Agent 类型：`ReactAgent`、`ParallelAgent`、`SequentialAgent`、`LLMRoutingAgent`、`LoopAgent` |
| instruction | TEXT | | 系统指令 |
| input_keys | TEXT | | 输入键（JSON） |
| output_key | VARCHAR(255) | | 输出键 |
| handle | LONGTEXT | | handle 配置（JSON） |
| sub_agents | LONGTEXT | | 子 Agent 配置（JSON） |
| yaml_schema | LONGTEXT | | 生成的 YAML schema |
| status | VARCHAR(64) | 🔢 | `DRAFT`、`PUBLISHED`、`ARCHIVED` |
| enabled | TINYINT(4) | 🔢 | 0-禁用，1-启用 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

### 15. api_key　API 密钥（`ApiKeyEntity`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| account_id | VARCHAR(64) | FK→account | 所属账号 |
| api_key | VARCHAR(512) | UK | API Key |
| status | TINYINT(4) | 🔢 | 0-已删除，1-正常 |
| description | VARCHAR(4096) | | 描述 |
| gmt_create / gmt_modified / creator / modifier | | | 审计字段 |

---

## 二、评估平台（admin 库，12 表）

> 该库是「Agent Studio 评估平台」的核心：Prompt 工程 → 数据集 → 评估器 → 实验 → 结果。表间存在显式外键约束。

### 16. dataset　测评集（`DatasetDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| name | VARCHAR(255) | | 测评集名称 |
| description | TEXT | | 描述 |
| columns_config | LONGTEXT | | 列结构配置（JSON） |
| create_time / update_time | DATETIME | | 创建/更新时间 |
| deleted | TINYINT(1) | 🔢 | 逻辑删除：0-未删除，1-已删除 |

### 17. dataset_version　测评集版本（`DatasetVersionDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| dataset_id | BIGINT(20) | FK→dataset | 所属测评集（外键，级联删除） |
| version | VARCHAR(32) | UK(dataset_id+version) | 版本号 |
| description | TEXT | | 版本描述 |
| data_count | INT(11) | | 该版本数据量 |
| status | VARCHAR(32) | 🔢 | `DRAFT`、`PUBLISHED`、`ARCHIVED` |
| experiments | TEXT | | 关联实验集合（JSON） |
| dataset_items | TEXT | | 数据项集合（JSON） |
| create_time / update_time | DATETIME | | 创建/更新时间 |

### 18. dataset_item　数据项（`DatasetItemDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| dataset_id | BIGINT(20) | FK→dataset | 所属测评集（外键，级联删除） |
| columns_config | LONGTEXT | | 列结构配置（JSON） |
| data_content | LONGTEXT | | 数据内容（JSON） |
| create_time / update_time | DATETIME | | 创建/更新时间 |
| deleted | TINYINT(1) | 🔢 | 逻辑删除 |

### 19. evaluator　评估器（`EvaluatorDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| name | VARCHAR(255) | | 评估器名称 |
| description | TEXT | | 描述 |
| create_time / update_time | DATETIME | | 创建/更新时间 |
| deleted | TINYINT(1) | 🔢 | 逻辑删除 |

### 20. evaluator_version　评估器版本（`EvaluatorVersionDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| evaluator_id | BIGINT(20) | FK→evaluator | 所属评估器（外键，级联删除） |
| description | TEXT | | 描述 |
| version | VARCHAR(32) | UK(evaluator_id+version) | 版本号 |
| model_config | TEXT | | 模型配置 |
| prompt | LONGTEXT | | Prompt 配置（JSON） |
| variables | LONGTEXT | | Prompt 中的变量参数 |
| status | VARCHAR(32) | 🔢 | `DRAFT`、`PUBLISHED`、`ARCHIVED` |
| experiments | TEXT | | 关联实验集合（JSON） |
| create_time / update_time | DATETIME | | 创建/更新时间 |

### 21. evaluator_template　评估模板（`EvaluatorTemplateDO`）

> 内置评估模板，独立表（不与评估器直接关联）。

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| evaluator_template_key | VARCHAR(255) | UK | 模板键 |
| template_desc | VARCHAR(255) | | 描述 |
| template | LONGTEXT | | 模板内容 |
| variables | LONGTEXT | | 变量 |
| model_config | LONGTEXT | | 推荐模型参数 |

### 22. experiment　实验（`ExperimentDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| name | VARCHAR(255) | | 实验名称 |
| description | TEXT | | 描述 |
| dataset_id | BIGINT(20) | FK→dataset | 数据集 |
| dataset_version_id | BIGINT(20) | FK→dataset_version | 数据集版本 |
| dataset_version | VARCHAR(32) | | 数据集版本号（冗余） |
| evaluation_object_config | LONGTEXT | | 被评估对象配置（JSON） |
| evaluator_config | TEXT | | 评估器配置 |
| status | VARCHAR(32) | 🔢 | `DRAFT`、`RUNNING`、`COMPLETED`、`FAILED`、`STOPPED` |
| progress | INT(3) | | 进度百分比 0-100 |
| complete_time | DATETIME | | 完成时间 |
| create_time / update_time | DATETIME | | 创建/更新时间 |

### 23. experiment_result　实验结果（`ExperimentResultDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| experiment_id | BIGINT(20) | FK→experiment | 所属实验 |
| input | LONGTEXT | | 输入内容 |
| actual_output | LONGTEXT | | 被评估对象实际输出 |
| reference_output | LONGTEXT | | 参考输出（用于对比） |
| score | DECIMAL(3,2) | | 评分 0.00-1.00 |
| reason | TEXT | | 评分理由 |
| evaluation_time | DATETIME | | 评估执行时间 |
| evaluator_version_id | BIGINT(20) | FK→evaluator_version | 打分的评估器版本 |
| create_time / update_time | DATETIME | | 创建/更新时间 |

### 24. prompt　Prompt（`PromptDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| prompt_key | VARCHAR(255) | UK | Prompt 业务键 |
| prompt_desc | VARCHAR(255) | | 描述 |
| latest_version | VARCHAR(32) | | 最新版本 |
| tags | VARCHAR(255) | | 标签 |
| create_time / update_time | DATETIME(3) | | 创建/更新时间 |

### 25. prompt_version　Prompt 版本（`PromptVersionDO`）

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| version | VARCHAR(32) | UK(prompt_key+version) | 版本号 |
| prompt_key | VARCHAR(255) | FK→prompt | 所属 Prompt |
| version_desc | VARCHAR(255) | | 版本描述 |
| template | LONGTEXT | | Prompt 模版内容 |
| variables | LONGTEXT | | 模版可变参数 |
| model_config | LONGTEXT | | 调试用的模型参数（JSON） |
| status | VARCHAR(32) | 🔢 | `pre`（预发布）、`release`（正式） |
| previous_version | VARCHAR(32) | | 前置版本（用于对比） |
| create_time | DATETIME(3) | | 创建时间 |

### 26. prompt_build_template　Prompt 构建模板（`PromptTemplateDO`）

> 内置 Prompt 模板，独立表。

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT(20) | PK | 自增主键 |
| prompt_template_key | VARCHAR(255) | UK | 模板键 |
| tags | VARCHAR(255) | | 标签 |
| template_desc | VARCHAR(255) | | 描述 |
| template | LONGTEXT | | 模板内容 |
| variables | LONGTEXT | | 变量 |
| model_config | LONGTEXT | | 推荐模型参数 |

### 27. model_config　模型配置（`ModelConfigDO`）

> 评估平台自身的模型配置（与 builder 的 `provider`/`model` 相互独立）。

| 字段 | 类型 | 键 | 说明 |
|---|---|---|---|
| id | BIGINT | PK | 自增主键 |
| name | VARCHAR(100) | UK | 模型名称 |
| provider | VARCHAR(50) | 🔢 | 提供商（openai、azure 等） |
| model_name | VARCHAR(100) | | 模型标识（gpt-4 等） |
| base_url | VARCHAR(500) | | 模型服务地址 |
| api_key | VARCHAR(500) | | API 密钥 |
| default_parameters | JSON | | 默认参数配置 |
| supported_parameters | JSON | | 支持的参数定义 |
| status | TINYINT | 🔢 | 1-启用，0-禁用 |
| create_time / update_time | DATETIME | | 创建/更新时间 |
| deleted | TINYINT(1) | 🔢 | 逻辑删除 |

---

## 三、关键关系说明（对应 ER 图）

ER 图（[06-data-model-er.svg](./06-data-model-er.svg)）聚焦两域核心关系，省略了独立/叶子表（`evaluator_template`、`prompt_build_template`、`model_config`、`api_key`、`application_component`、`reference`、`agent_schema`），这些见上方字段清单。

### Builder 域（agentscope 库，逻辑外键）

```
account ─1:N─ workspace ─┬─1:N─ application ─1:N─ application_version
                         ├─1:N─ plugin ─1:N─ tool
                         ├─1:N─ knowledge_base ─1:N─ document
                         ├─1:N─ mcp_server
                         └─1:N─ provider ─1:N─ model
account ─1:N─ api_key
application ←(application_component) / ←(reference 多态引用)
```

- **隔离模型**：`workspace_id` 是几乎所有资源的租户边界；`account 1:N workspace` 是顶层归属。
- **应用版本化**：`application 1:N application_version`，版本表持有具体 `config`。
- **工具归插件**：`plugin 1:N tool`，工具携带 `api_schema` 供 Agent 调用。
- **知识库→文档**：`knowledge_base 1:N document`，文档经切片后写入 ES 向量库（`document.index_status` 跟踪）。
- **供应商→模型**：`provider 1:N model`，`provider` 存凭证，`model` 存具体模型标识与能力标签。

### 评估域（admin 库，含显式外键）

```
dataset ─1:N─┬─ dataset_version ─1:N─ experiment ─1:N─ experiment_result
             └─ dataset_item                                    ↑
evaluator ─1:N─ evaluator_version ──────────────────────────────┘（打分）
prompt ─1:N─ prompt_version
（独立）evaluator_template / prompt_build_template / model_config
```

- **三组版本化资产**：`dataset`、`evaluator`、`prompt` 各自 `1:N` 版本表，版本状态统一为 `DRAFT/PUBLISHED/ARCHIVED`（prompt 用 `pre/release`）。
- **实验主轴**：`experiment` 关联一份 `dataset_version` 作输入、若干 `evaluator_version` 作打分器；逐条数据在 `experiment_result` 落分（`score` + `reason`），由 `evaluator_version_id` 指明打分者。
- **模板表独立**：`evaluator_template` / `prompt_build_template` 为内置模板种子数据，不参与外键关系。

> 两域通过模型配置松耦合：评估域用自有的 `model_config` 驱动评估调用，builder 域用 `provider`/`model` 驱动应用运行时；二者 schema 互不依赖。

---

## 四、API 引用但非 MySQL 持久化的实体（与 04 交叉核对补遗）

> 本节由 [04-api-list.md](./04-api-list.md) 与本文件交叉核对得出。04 中引用的实体型名词，除前两节 27 张 MySQL 表覆盖的外，还有 **6 个领域对象不落 MySQL**——它们在 API 中被 CRUD 或返回，但存储于 Elasticsearch 或进程内内存。已逐个到源码验证其真实存储，补录如下，使两份文档一致。

### 核对结论

| 实体（04 引用） | 04 出现位置 | 本文件原定义？ | 实际存储（已验证） | 是否需补录 |
|---|---|---|---|---|
| DocumentChunk | DocumentChunkController CRUD、KnowledgeBaseController.retrieve 返回 | ❌ | Elasticsearch 向量库 | ✅ 已补 |
| ChatSession | PromptController GET/DELETE session | ❌ | 进程内 `ConcurrentHashMap`（易失） | ✅ 已补 |
| App（generator `/graph-studio`） | ApplicationController CRUD | ❌（≠ builder `application` 表） | 进程内 `AppMemorySaver`（易失） | ✅ 已补 |
| TraceSpanDTO / TraceDetailDTO | ObservabilityController traces、traces/{traceId} | ❌ | Elasticsearch 索引 `loongsuite_traces` | ✅ 已补 |
| ServicesResponseDTO / OverviewStatsDTO | ObservabilityController services、overview | ❌ | Elasticsearch `loongsuite_traces` 聚合 | ✅ 已补 |

> 说明：`McpServerDetail`、`Tool`、`PromptTemplate` 等是 VO/DTO 包装，底层仍对应已定义的表（mcp_server / tool / prompt_build_template），不计为缺口。

### 4.1 DocumentChunk　文档切片（Elasticsearch 向量库）

> 类：`admin-server-runtime/.../runtime/domain/knowledgebase/DocumentChunk.java`。由 `core/rag/vectorstore/elasticsearch/ElasticSearchVectorStoreService` 经 `VectorStoreService` 读写；`document` 表只存文档元数据，**切片正文与向量存 ES**。API：DocumentChunkController 增删改查、KnowledgeBaseController `/retrieve` 检索返回。无传统主键，`chunk_id` 为逻辑键。

| 字段（JSON 名 / Java 名） | 类型 | 说明 |
|---|---|---|
| doc_id / docId | String | 所属文档 ID |
| doc_name / docName | String | 文档名 |
| title | String | 切片标题 |
| text | String | 切片正文 |
| score | Double | 检索相关度得分 |
| page_number / pageNumber | Integer | 原文档页码 |
| chunk_id / chunkId | String | 切片唯一 ID（逻辑键） |
| enabled | Boolean | 是否启用 |
| workspace_id / workspaceId | String | 所属工作区 |

> ES 文档中同时存储向量 embedding（由 `knowledge_base.index_config` 指定的向量字段），不在 Java 字段中体现。

### 4.2 ChatSession　Prompt 调试会话（进程内内存，易失）

> 类：`admin-server-start/.../admin/dto/ChatSession.java`。存储于 `ChatSessionServiceImpl` 的 `ConcurrentHashMap<String, ChatSession> sessionStore`（非 Redis、非 DB），**进程重启即丢失**。API：PromptController `/api/prompt/session` GET/DELETE、`/api/prompt/run` 维护。

| 字段 | 类型 | 说明 |
|---|---|---|
| sessionId | String | 会话 ID（键） |
| promptKey | String | Prompt 键 |
| version | String | Prompt 版本 |
| template | String | Prompt 模板 |
| variables | String | 变量配置（JSON） |
| modelConfig | ModelConfigInfo | 模型配置 |
| messages | List&lt;ChatMessage&gt; | 消息历史 |
| mockTools | List&lt;MockTool&gt; | 模拟工具 |
| createTime / lastUpdateTime | Long | 创建 / 最后更新时间戳 |

### 4.3 App　generator 工作台应用（进程内内存，易失）

> 类：`admin-server-start/.../admin/builder/generator/model/App.java`。存储于 `AppMemorySaver`（`ConcurrentHashMap<String, App>`），由 `AppSaverConfiguration` 装配为唯一 `AppSaver` Bean。**与 builder 的 `application` MySQL 表是两套独立对象**（builder 的应用落 `application`，generator 工作台的 App 仅内存）。API：ApplicationController `/graph-studio/api/app` CRUD、RunnerController 运行。

| 字段 | 类型 | 说明 |
|---|---|---|
| metadata | AppMetadata | 应用元数据（name / type / version 等） |
| spec | Object | 应用规格（Agent / Workflow / Chatbot 定义） |

### 4.4 观测 DTO（Elasticsearch traces 索引）

> 类：`admin-server-start/.../admin/dto/{TraceSpanDTO,TraceDetailDTO,ServicesResponseDTO,OverviewStatsDTO}.java`。数据来自 `TracingRepository` + `TracingQueryBuilder` 查询 Elasticsearch 索引 `loongsuite_traces`（`elasticsearch.yml` 中 `app.tracing.index.traces-index`）。该索引由外部 SAA Agent 应用经 OTLP（:4318）上报的 Span 写入，**非本应用写入的 MySQL/业务表**。API：ObservabilityController 的 traces / traces/{traceId} / services / overview。

| DTO | 含义 | 数据来源 |
|---|---|---|
| TraceSpanDTO | 单条 Span（traceId / spanId / service / 起止时间 / 属性） | ES `loongsuite_traces` 文档 |
| TraceDetailDTO | 单个 Trace 的完整 Span 树 | ES `loongsuite_traces` 聚合 |
| ServicesResponseDTO | 服务列表（按 service 聚合） | ES `loongsuite_traces` 聚合 |
| OverviewStatsDTO | 可观测概览统计（trace 数 / 错误率等） | ES `loongsuite_traces` 聚合 |

> 小结：04 与 05 现已一致——MySQL 落库的 27 张表见第一、二节；API 另外暴露的 4 类非 MySQL 领域对象（DocumentChunk / ChatSession / generator App / 观测 DTO）在本节按真实存储补录，不再存在“API 有、数据模型无”的悬空引用。
