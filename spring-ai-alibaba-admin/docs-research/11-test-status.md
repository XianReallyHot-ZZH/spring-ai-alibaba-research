# 测试现状（11-test-status）

> 扫描范围：`spring-ai-alibaba-admin/`（本项目）。方法：find 全部 `src/test`、`src/it`、前端 `*.test/spec`、e2e 目录；grep 集成注解、Controller 引用、核心类引用。
> 对照：[`10-critical-paths.md`](./10-critical-paths.md) 的 7 条核心链路。
> 结论一句话：**测试极其稀疏——仅 8 个纯单测（全在 core 的 RAG/crypto/memory/utils），0 集成、0 前端、0 e2e；32 个 Controller 全无测试；7 条核心链路 0 条被完整覆盖。**

---

## 一、测试文件统计

| 类型 | 数量 | 说明 |
|---|---:|---|
| **单元测试**（Java，`src/test/java`） | **8** | 全部在 `admin-server-core`；纯 JUnit，无 `@SpringBootTest`/`@DataJpaTest` 等集成注解 |
| **集成测试** | **0** | 无 `src/it`，无 Spring 上下文/DB/中间件集成测试 |
| **E2E** | **0** | 前端 0 个 `.test/.spec` 文件，无 playwright/cypress/jest 配置、无 e2e 目录 |

### 8 个单测清单（`admin-server-core/src/test/java`）
| 测试 | 覆盖对象 | 归属链路 |
|---|---|---|
| `ConversationChatMemoryTest` | `ConversationChatMemory`（agent 记忆） | 辅助（非 7 条主干） |
| `PasswordCryptTest` | `PasswordCrypt`（密码哈希） | #1 登录鉴权（底层原语） |
| `RSACryptTest` | `RSACrypt`（RSA 加解密） | #1（底层原语） |
| `KnowledgeBaseIndexPipelineTest` | `KnowledgeBaseIndexPipeline`（RAG 索引管道） | #3 知识库文档索引 |
| `TextDocumentReaderTest` | `TextDocumentReader`（文档读取） | #3 |
| `TextSplitterTest` | `TextSplitter`（切片） | #3 |
| `DashscopeRerankerTest` | `DashscopeReranker`（重排） | #3 |
| `DateUtilsTests` | `DateUtils`（工具） | 辅助 |

### 按模块
- `admin-server-core`：**8** 个（RAG + crypto + memory + utils）
- `admin-server-start`：**0**（Admin 平台业务 + builder/generator 控制器/服务都在此，无测试）
- `admin-server-openapi`：**0**（`ChatController` 运行时入口，无测试）
- `admin-server-runtime`：**0**（领域 DTO/枚举，通常无需测）

---

## 二、Controller 测试覆盖

**0 / 32 个 Controller 有对应测试**（grep 确认：无任何测试文件引用 Controller；无 `*ControllerTest`）。

与 7 条核心链路相关的、**当前无测试的关键 Controller**：
`AuthController`、`PromptController`、`DocumentController`、`ChatController`(openapi)、`ExperimentController`、`ObservabilityController`、`McpServerController`。

---

## 三、核心 Service 测试覆盖

| 状态 | 对象 |
|---|---|
| **有测试** | `ConversationChatMemory`、`PasswordCrypt`、`RSACrypt`、`KnowledgeBaseIndexPipeline`、`TextDocumentReader`、`TextSplitter`、`DashscopeReranker`（+ `DateUtils` 工具） |
| **无测试**（核心链路主干） | `TokenManager`、`TokenAuthInterceptor`、`PromptRunService`、`ChatSessionService`、`DocumentService(Impl)`、`ElasticSearchVectorStoreService`、`ExperimentService`、`TracingRepository(Impl)`、`McpServerService` |

---

## 四、核心链路测试覆盖（对照 10-critical-paths.md）

| # | 核心链路 | 覆盖 | 说明 |
|---|---|:--:|---|
| 1 | 登录鉴权 | 🟡 **部分** | 仅密码/RSA 加密原语有单测；**TokenManager 签发、TokenAuthInterceptor 校验、登录→token 主链路均无测试** |
| 2 | Prompt 调试运行 | 🔴 **没有** | `PromptRunService`、`ChatSessionService`、流式 Flux、内存会话均无测试 |
| 3 | 知识库文档索引 | 🟡 **部分** | RAG 组件（读取/切片/重排/索引管道）有单测；**`DocumentService`→RocketMQ→ES 异步主链路、`document.index_status` 状态机无测试** |
| 4 | 对话/工作流执行 | 🔴 **没有** | admin 侧 `ChatController`(openapi) 无测试；运行时在 `spring-ai-alibaba-graph-core`（外部兄弟模块，本扫描范围内无；其节点单测不在本项目） |
| 5 | 评估实验执行 | 🔴 **没有** | `ExperimentService`、跨域 join、模型打分、状态机、结果写入均无测试 |
| 6 | Trace 链路摄取与查询 | 🔴 **没有** | `TracingRepository`、OTLP→ES pipeline、时序/聚合查询均无测试 |
| 7 | MCP 工具调试 | 🔴 **没有** | `McpServerService`、外部 MCP 连接/工具调用均无测试 |

**汇总**：7 条核心链路 → **0 完整覆盖 / 2 部分（#1、#3）/ 5 完全没有（#2、#4、#5、#6、#7）**。

---

## 五、缺口与建议（按风险优先级）

按 [`10-critical-paths.md`](./10-critical-paths.md) 的回归优先级，建议优先补：
1. **#5 评估实验执行**——主干、最复杂（三域 join + 状态机 + 批量写），当前 0 测试，改动风险最高却无任何护栏。
2. **#1 登录鉴权**——跨切面爆炸半径大；补 `TokenAuthInterceptor` + login 集成测试（`@WebMvcTest` 或 `@SpringBootTest`）。
3. **#3 知识库文档索引**——已有 RAG 组件单测，但缺 **MQ→ES 异步主链路**集成测试（最易在改造中坏）。
4. **#2 Prompt 调试运行 / #7 MCP 调试**——流式/外部集成，建议加针对性测试。
5. **#4 对话/工作流执行**——admin 侧 `ChatController` 至少加冒烟级测试；graph-core 运行时测试归属外部模块。

> 优先补**集成测试**（当前 0 个）而非更多单测——核心链路的价值在跨层/跨系统集成，单测覆盖不到。

---

## 六、实际运行结果（`mvn test` 实跑）

> 命令：`mvn test -B`（admin 根）｜ 时间：2026-06-20 16:57｜ 结果：**BUILD SUCCESS**｜未修复任何测试（仅汇报）

### 总览

| 指标 | 值 |
|---|---|
| 测试方法数 | **17**（8 个测试类，全部在 `admin-server-core`） |
| 通过 | **17** |
| 失败 | **0** |
| 跳过 | **0** |
| 总耗时 | **59.5 s** |
| 构建 | BUILD SUCCESS（5 模块全过） |

### 各测试类明细

| 测试类 | 方法数 | 结果 | 耗时 |
|---|---:|:--:|---|
| ConversationChatMemoryTest | 3 | ✅ | 1.28s |
| PasswordCryptTest | 2 | ✅ | 0.56s |
| RSACryptTest | 2 | ✅ | 0.05s |
| KnowledgeBaseIndexPipelineTest | 3 | ✅ | 0.14s |
| TextDocumentReaderTest | 1 | ✅ | 0.03s |
| DashscopeRerankerTest | 2 | ✅ | 0.05s（走 mock，未真连 DashScope） |
| TextSplitterTest | 2 | ✅ | 0.12s |
| DateUtilsTests | 2 | ✅ | 0.03s |

> `runtime` / `openapi` / `start` 三模块无测试（"No tests to run"）。

### 失败分类

**无失败**（Failures: 0, Errors: 0），故无"代码 bug / 测试坏了 / 环境问题"分类。

> ⚠️ 日志里 `DateUtilsTests` 出现一段 `java.text.ParseException: Unparseable date: "invalid-date"` 堆栈——**不是失败**：它是负面用例 `parseDateStringReturnsNullOnParseFailure` 故意传入非法日期、断言返回 null；被测方法捕获异常时打了 WARN 日志（loud 但符合预期），该用例通过。

### 测试健康度

| 维度 | 结论 |
|---|---|
| 通过率 | **100%（17/17）** |
| 健康度 | 🟢 **绿**（≥90% 通过） |
| 备注 | **绿而稀疏**——现有测试质量 OK（全过、无 flaky、无外部环境依赖：`DashscopeRerankerTest` 走 mock，不需网络/key），但**总量仅 17、全是叶子组件单测**；按第五节，7 条核心链路仍 0 完整覆盖。"绿"指现有测试都健康，不等于项目被充分测试。 |

**口径**：单看 `mvn test` → 全绿、可放心合入；但作为质量信号 → 信号很弱（测得少、且没碰到任何主链路），真正的风险（第五节列出的实验执行/鉴权/索引等）当前没有任何自动化护栏。
