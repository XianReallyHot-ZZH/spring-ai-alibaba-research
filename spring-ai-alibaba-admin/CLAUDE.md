# CLAUDE.md — Spring AI Alibaba Admin

> AI 助手在本项目（`spring-ai-alibaba-admin`，对外品牌 **Agent Studio**）工作时的精简指引。
> 详细资料见 [`docs-research/`](./docs-research/)，本文只给定位与链接，不重复其内容。

## 项目定位

基于 Spring AI Alibaba 的 **AI Agent 开发与评估平台**，提供 Agent 全生命周期管理：
**Prompt 工程 → 数据集 → 评估器 → 实验与结果分析**，外加可观测（Trace）与应用可视化构建（Agent / 工作流 / 知识库 / MCP / 工具）。

- 形态：**内部平台 / 控制台**（前后端一体），非 SDK 库。
- 技术栈：Spring Boot 3.3.6 · Java 17 · 前端 Monorepo（Umi 4 + spark-flow）。
- 仓库归属：`spring-ai-alibaba` monorepo 下的子项目；本目录即本项目根。

## 核心架构

分层：**前端（:8000）→ 后端（:8080）→ MySQL / Elasticsearch**，旁挂 **Nacos / Redis / RocketMQ**，对接外部 AI 模型供应商；外部 SAA Agent 应用经 Nacos 拉 Prompt、经 OTLP 上报 Trace。

- 架构图 → [`docs-research/01-architecture.svg`](./docs-research/01-architecture.svg) · [源码](./docs-research/01-architecture.md)
- 对外依赖（Java 依赖 / 中间件 / 外部 API 三类） → [`docs-research/03-external-deps.svg`](./docs-research/03-external-deps.svg) · [源码](./docs-research/03-external-deps.md)

## 关键模块

后端为 4 个 Maven 模块，依赖为**无环 DAG**：`start → openapi → core → runtime`。

| 模块 | 职责 |
|---|---|
| `admin-server-start` | Spring Boot 启动入口与全局装配；承载 Admin 平台业务（Prompt/数据集/评估/实验）、应用代码生成器、可观测接入 |
| `admin-server-openapi` | RESTful API 层：对前端/外部暴露对话等接口与请求拦截器 |
| `admin-server-core` | 核心能力底座：Agent / 模型 / RAG / Workflow 的模型·服务·处理器·持久化（含 ES 向量库扩展） |
| `admin-server-runtime` | 运行时领域对象层：各领域 DTO · 枚举 · 异常 |

前端（`frontend/` Monorepo）：`main`（Umi 4 工作台）/ `spark-flow`（可视化工作流编辑器）/ `spark-i18n`（国际化）。

- 模块依赖图 → [`docs-research/02-module-deps.svg`](./docs-research/02-module-deps.svg) · [源码](./docs-research/02-module-deps.md)

## 关键约定

- **响应包装**：`Result<T>`（admin/builder 模块）、`R<T>`（generator 模块）；分页 `Result<PageResult<T>>`（admin）/ `Result<PagingList<T>>`（builder）。
- **路径前缀**：`/api/v1/apps`（openapi 运行时）、`/api/*`（admin 评估平台）、`/console/v1/*`（builder 控制台）、`/graph-studio/api/*` 与根 `/`（generator 工作台）。
- **存储分工**：两个 MySQL 库——`agentscope`（builder，无 DB 外键，靠业务键维系）/ `admin`（评估，有外键）；文档切片与 Trace 落 **Elasticsearch**；`ChatSession` 与 generator 的 `App` 为**进程内内存**（易失，重启丢失）。
- **代码规范**：Java 17、`jakarta.*`（非 `javax.*`）、Lombok、SLF4J（**禁止 `System.out.println`**）、Apache 2.0 许可头；持久化实体用 MyBatis-Plus `@TableName`（core 模块 `*Entity`）+ DO（admin 模块 `*DO`）。
- **配置入口**：`spring-ai-alibaba-admin-server-start/src/main/resources/application.yml`（profile：`dev` / `local`），中间件地址与密钥走环境变量（`NACOS_SERVER_ADDR` / `SPRING_DATASOURCE_*` 等）。

- 接口清单（32 Controller / ~211 接口） → [`docs-research/04-api-list.md`](./docs-research/04-api-list.md)
- 数据模型（27 表 + 非 MySQL 实体） → [`docs-research/05-data-model.md`](./docs-research/05-data-model.md) · [ER 图](./docs-research/06-data-model-er.svg) · [ER 源码](./docs-research/06-data-model-er.md)

## 怎么跑

前置：**JDK 17 · Maven 3.8+ · Node ≥ 20 · Docker（+ Compose）**，以及一家 AI 模型供应商的 API Key。

```bash
# 1) 中间件（MySQL / Elasticsearch / Nacos / Redis / RocketMQ）
cd docker/middleware && sh run.sh

# 2) 配置模型 API Key（按供应商选模板）
#    编辑 spring-ai-alibaba-admin-server-start/model-config.yaml
#    模板：model-config-dashscope.yaml / -openai.yaml / -deepseek.yaml

# 3) 后端（:8080）
cd spring-ai-alibaba-admin-server-start && mvn spring-boot:run

# 4) 前端（:8000）
cd frontend
npm run re-install            # 首次安装依赖
cd packages/main
cp .env.example .env          # 配 WEB_SERVER / DEFAULT_USERNAME / DEFAULT_PASSWORD
npm run dev
```

访问 http://localhost:8000（默认账号见前端 `.env`）。整体构建：`mvn -B package -DskipTests=true`。

## 禁区

<!-- 待补充：不可改动 / 需特别评审的区域（如许可头、安全相关、外部契约等） -->

## 历史包袱

<!-- 待补充：已知技术债、遗留设计、待重构点（如某些内存态存储、命名不一致等） -->
