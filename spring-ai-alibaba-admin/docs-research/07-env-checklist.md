# 运行环境外部依赖清单（07-env-checklist）

> 综合 [`03-external-deps.md`](./03-external-deps.md)、`application.yml` / `application-dev.yml` / `application-local.yml` / `elasticsearch.yml`、`pom.xml`、`README*.md`、`docker/middleware/`（`docker-compose-prod.yaml`、`mysql.env`、`init/mysql/*.sql`、`init/elasticsearch/init-indices.sh`）整理。
> 覆盖：工具链、中间件服务、外部模型 API。生成日期：2026-06-20。
>
> 关键更正：物理上只有 **一个 MySQL 库 `admin`**——`agentscope-schema.sql`（builder 表）与 `admin-schema.sql`（评估表）都在首次初始化时建入同一个 `admin` 库；`agentscope`/`admin` 只是逻辑域命名，不是两个物理库。

## 关键性图例

- 🔴 **必需**：缺则应用起不来或核心功能不可用。
- 🟡 **功能相关**：缺则对应特性降级（可观测 / RAG 异步索引 / 缓存），主流程仍可跑。
- ⚪ **可选**：按需启用（OSS / MCP / 替换模型供应商）。

---

## 1. 工具链（构建与运行前提）

| 依赖 | 版本要求（主版本） | 用途 | 备注 |
|---|---|---|---|
| JDK | **17** | 后端编译/运行（`java.version=17`） | 必须 17，低于此不编译 |
| Maven | **3**（≥ 3.8） | 后端构建 | README 要求 3.8+ |
| Node.js | **20**（≥ v20） | 前端构建/开发（Umi 4 monorepo） | frontend/README 要求 |
| Docker + Compose | **Compose 2**（≥ 2.0） | 拉起中间件 | README 要求 2.0+ |

> Java 第三方库（Spring Boot 3.3.6、MyBatis-Plus、Druid、Redisson、Spring AI 等）**打包进 jar，非运行期外部依赖**，清单见 [`03-external-deps.md`](./03-external-deps.md)，此处不重复。

---

## 2. 中间件服务（`docker/middleware`，prod 模式全集）

> 启动方式：`make env-start MODE=prod`（或 `cd docker/middleware && ./run.sh prod`）。dev 模式**仅含 MySQL**，跑全功能用 prod。建议 ≥ 8GB 内存。

| 依赖 | 版本（镜像 tag） | 默认端口（宿主） | 连接信息（应用侧） | 初始化要求 | 关键性 |
|---|---|---|---|---|---|
| **MySQL** | **8**（8.0.35） | 3306 | `jdbc:mysql://<host>:3306/admin`，用户 `admin/admin`（root `root/root`）；env `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` | 库 `admin` 由 `mysql.env`（`MYSQL_DATABASE=admin`）自动建；两份 schema（`init/mysql/admin-schema.sql` + `agentscope-schema.sql`）经 `docker-entrypoint-initdb.d` 首启自动执行（共 27 张表）。JPA `ddl-auto=none`，应用不建表。自建中间件时需手工 `CREATE DATABASE admin` 并导入两份 SQL | 🔴 |
| **Elasticsearch** | **9**（9.1.2） | 9200（HTTP）/ 9300（传输） | `http://<host>:9200`，**无鉴权**（`xpack.security.enabled=false`）；env `SPRING_ELASTICSEARCH_URIS/URL` | `elasticsearch-init` 容器自动建 ingest pipeline `parsing_loongsuite_traces` + 索引 `loongsuite_traces`（trace 存储，mapping 见 `init-indices.sh`）。RAG 向量索引由应用按 `knowledge_base.index_config` **运行时**按需创建 | 🔴（RAG/Trace） |
| **Kibana** | **9**（9.1.2） | 5601 | 连接 ES `http://elasticsearch:9200` | 无；仅可视化用 | ⚪ |
| **LoongCollector** | **3**（3.1.4） | 4318（OTLP/HTTP） | OTLP 上报 `http://<host>:4318/v1/traces`；env `MANAGEMENT_OTLP_TRACING_EXPORT_ENDPOINT` | 即「:4318 OTLP Collector」本体；接收应用自身与外部 Agent 应用的 trace，转发写入 ES `loongsuite_traces`。依赖 ES 初始化完成（`depends_on: elasticsearch-init`） | 🟡（可观测） |
| **Nacos** | **2/3**（`nacos-server:latest`；客户端 `nacos-client 3.0.3`） | 8848（gRPC，应用用）/ 7848（旧 HTTP API）/ 7080（控制台） | `nacos.server-addr=<host>:8848`（env `NACOS_SERVER_ADDR`）；鉴权 `admin/admin`（`NACOS_AUTH_IDENTITY_KEY/VALUE`）；**默认命名空间 `public`** | 无需建命名空间/配置导入；Prompt 发布到 Nacos 供 Agent 应用拉取是**可选**特性 | 🟡（Prompt 动态下发） |
| **Redis** | **7**（7.2.5） | 6379 | `<host>:6379`，**无密码**，默认 db 0；env `SPRING_REDIS_HOST/PORT/DATABASE` | 无（仅缓存/会话） | 🟡（缓存/会话） |
| **RocketMQ** | **5**（5.3.2；namesrv+broker+proxy 三容器） | 18080（proxy gRPC，应用用）/ 9876（namesrv）/ 10909/10911/10912（broker） | `rocketmq.endpoints=<host>:18080`（env `ROCKETMQ_ENDPOINTS`） | `init-topic` 容器自动建主题 `topic_saa_studio_document_index` + 消费组 `group_saa_studio_document_index`（与 `application.yml` 一致） | 🟡（文档异步索引） |

> Nacos 端口说明：compose 把容器 `9848`(gRPC)→宿主 `8848`，故应用 `server-addr=localhost:8848` 实际打到 gRPC；控制台 UI 在宿主 `7080`。

---

## 3. 外部 API（模型供应商，必选其一）

> 通过 `spring-ai-alibaba-admin-server-start/model-config.yaml` 配置（按供应商选模板：`model-config-{dashscope|openai|deepseek}.yaml`）。

| 依赖 | 版本要求 | 默认端点 / 连接 | 初始化要求 | 关键性 |
|---|---|---|---|---|
| **DashScope（阿里云百炼）** | qwen 系列模型 | DashScope OpenAI 兼容模式（`dashscope.aliyuncs.com/compatible-mode`） | 设环境变量 `DASHSCOPE_API_KEY`；用 dashscope 模板 | 🔴（默认推荐） |
| **OpenAI** | gpt-4o 等 | OpenAI 官方端点 | 设 `OPENAI_API_KEY`；用 openai 模板 | 🔴（可选其一） |
| **DeepSeek** | deepseek-chat | DeepSeek 端点 | 设 `DEEPSEEK_API_KEY`；用 deepseek 模板 | 🔴（可选其一） |
| **Ollama**（自托管） | — | 本地 Ollama 服务 | 无需 key；装 Ollama 并拉模型 | ⚪ |

### 可选外部服务

| 依赖 | 触发条件 | 初始化要求 | 关键性 |
|---|---|---|---|
| **阿里云 OSS** | 文件上传后端选 OSS（`aliyun-sdk-oss`） | 配 OSS endpoint / AccessKey / Secret / bucket | ⚪ |
| **MCP Servers** | 使用 MCP 工具节点 | 在平台按 server 记录配置（无固定端点） | ⚪ |

---

## 4. 应用端口与 Profile

| 项 | 值 |
|---|---|
| 后端 | `:8080`（`mvn spring-boot:run`） |
| 前端 | `:8000`（`npm run dev`，代理到 `WEB_SERVER=http://127.0.0.1:8080`） |
| Actuator | `/actuator`（health 等） |
| Profile | `dev`（默认，指向远端 `47.239.212.78`）/ `local`（全 `localhost`，`-Dspring.profiles.active=local`）/ `nacos` 等按需 |

> `application-dev.yml` 默认中间件地址为 `47.239.212.78`（MySQL/Redis/ES/Nacos/RocketMQ/OTLP 均指向该机）；本地自建中间件请用 `local` profile 或覆盖对应环境变量。

---

## 5. 从零拉起环境（按序）

1. **工具链**：装 JDK 17、Maven 3.8+、Node 20+、Docker+Compose 2。
2. **中间件**：`make env-start MODE=prod`（自动完成 MySQL 建库+建表、ES 建索引+pipeline、RocketMQ 建主题、LoongCollector 起来）。
3. **模型 Key**：复制对应 `model-config-*.yaml` 为 `model-config.yaml`，导出 API Key 环境变量。
4. **后端**：`cd spring-ai-alibaba-admin-server-start && mvn spring-boot:run`（本地中间件建议加 `-Dspring.profiles.active=local`）。
5. **前端**：`cd frontend && npm run re-install`，`cd packages/main && cp .env.example .env && npm run dev`。
6. **访问**：http://localhost:8000（账号见前端 `.env`）。

---

## 6. 连接配置速查（环境变量 ↔ application*.yml）

| 中间件 | 关键环境变量 | local 默认 |
|---|---|---|
| MySQL | `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` | `localhost:3306/admin` · admin/admin |
| Redis | `SPRING_REDIS_HOST/PORT/DATABASE` | `localhost:6379` · db 0 |
| Elasticsearch | `SPRING_ELASTICSEARCH_URIS`（+ `SPRING_ELASTICSEARCH_URL`） | `http://localhost:9200` |
| Nacos | `NACOS_SERVER_ADDR` | `localhost:8848` |
| RocketMQ | `ROCKETMQ_ENDPOINTS`（+ `ROCKETMQ_DOCUMENT_INDEX_TOPIC/GROUP`） | `localhost:18080` |
| OTLP | `MANAGEMENT_OTLP_TRACING_EXPORT_ENDPOINT` | `http://localhost:4318/v1/traces` |

> 端口速查：3306 MySQL · 6379 Redis · 9200/9300 ES · 5601 Kibana · 4318 OTLP(LoongCollector) · 8848 Nacos(gRPC) / 7080 控制台 · 9876 RocketMQ namesrv / 18080 proxy · 8080 后端 · 8000 前端。
