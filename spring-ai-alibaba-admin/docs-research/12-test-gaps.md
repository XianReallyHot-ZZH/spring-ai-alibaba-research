# 测试缺口（12-test-gaps）

> 对照：[`10-critical-paths.md`](./10-critical-paths.md)（该测什么）× [`11-test-status.md`](./11-test-status.md)（已测什么）。
> 原则：**只列核心链路上的缺口**（非主链路不列）；**宁少勿多**（≤20）；**不追覆盖率指标，追"关键路径有兜底"**；每项标 P0/P1。
> 现状摘要：现有 17 个测试全是叶子组件单测，7 条核心链路 **0 完整覆盖**——故缺口几乎=主链路本身。

## 图例
- **P0**：改造相关代码前**必须**先有（否则无护栏、极易引入回归）。
- **P1**：有了更好（加固/锁定，非阻塞）。
- **测试类型**：`集成`（跨层/跨系统，Spring 上下文 + 真/mock 中间件）、`单元`（隔离纯逻辑）、`Characterization`（锁定当前行为，重构前的安全网——不改语义只加测试）。

## 缺口总表

| # | 核心链路 | 场景描述 | 为什么必须 | 建议类型 | 优先级 |
|---|---|---|---|---|:--:|
| 1 | ① 登录鉴权 | **登录全流程**：有效账号→签发 `access_token`；错密码/`account.status`=已禁用→拒绝 | 鉴权是所有受保护接口的入口；账号状态/密码校验一改全站登录坏 | 集成（`@SpringBootTest`+真 `TokenManager`+account 表） | **P0** |
| 2 | ① 登录鉴权 | **拦截器校验**：有效 token 放行并注入用户上下文；过期/伪造→401；`login`/`system` 排除路径放行 | `TokenAuthInterceptor` 跨切面、爆炸半径最大；拦截范围/排除项易在重构中漏改 | 集成（或单元+mock 依赖） | **P0** |
| 3 | ③ 知识库文档索引 | **异步索引主链路**：建/重索引 document → 经 RocketMQ → 切片写 ES → `index_status` pending→completed → `retrieve` 能命中 | 现有单测只测切片/读取等组件，**MQ→ES 主链路 + 状态机零覆盖**；异步丢消息/索引失败会静默坏 | 集成（真 MQ+ES，或 testcontainers） | **P0** |
| 4 | ④ 对话/工作流执行 | **执行入口请求处理**：合法 `AgentRequest`/`WorkflowRequest` 路由到 runtime（流式/async）；非法/缺 app/缺参→正确 4xx | 产品核心运行时入口；参数校验/路由一改即坏，且无任何护栏 | 集成（controller 层 + mock runtime/模型） | **P0** |
| 5 | ⑤ 评估实验执行 | **实验 happy 全流程**：建 experiment → 跑 `dataset_version`×`evaluator_version` → 模型打分 → `experiment_result` 有 score → `status=COMPLETED` | 最复杂链路（三域 join + 模型 + 写结果），**当前 0 覆盖、改造风险最高**却无护栏 | 集成（mock 模型打分） | **P0** |
| 6 | ② Prompt 调试运行 | **流式多轮调试**：`/api/prompt/run` → Flux 多帧 → 会话可续轮（`GET session` 能取回） | 流式背压/中断 + `ChatSession` **内存态易失**；Prompt 引擎改动易坏流式与续轮 | 集成（mock 模型，验 Flux + 会话） | P1 |
| 7 | ⑤ 评估实验执行 | **状态机与控制**：`RUNNING→stop`/`restart`、`FAILED`、`progress` 推进、并发/重复控制 | 状态转换逻辑复杂、即将被改时先用 Characterization 锁住现状，避免改语义 | Characterization（锁定状态迁移矩阵） | P1 |
| 8 | ⑥ Trace 摄取与查询 | **Trace 查询**：`/traces` 列表 + `/traces/{id}` 详情(span 树)；`startTime/endTime` 必填、空结果边界 | 可观测是产品功能；查询字段/时序/聚合在改 ES mapping 或查询逻辑时易坏 | 集成（向 ES 种 trace 后查） | P1 |
| 9 | ⑥ Trace 摄取与查询 | **ES ingest pipeline 解析**：`parsing_loongsuite_traces` 对样例 trace 文档的 token/字段解析（json flattening、usage 提取） | pipeline/mapping 一改就静默坏（写入成功但字段错）；改前用 Characterization 锁定解析结果 | Characterization（固定样例→断言解析后字段） | P1 |
| 10 | ⑦ MCP 工具调试 | **debug-tools**：连外部 MCP Server → 调用 tool → 返回；连接失败/超时/凭证错 → 友好错误 | 外部集成（协议/传输/凭证）最易在 MCP SDK 升级或配置改动时坏 | 集成（mock MCP server，走 MCP SDK 测试桩） | P1 |

## 汇总

| 优先级 | 数量 | 链路分布 |
|---|---:|---|
| **P0**（改造前必须有） | **5** | ①×2（登录/拦截器）、③ KB索引、④ 执行入口、⑤ 实验 happy |
| **P1**（有了更好） | **5** | ② Prompt流式、⑤ 实验状态机、⑥ Trace查询、⑥ ES pipeline、⑦ MCP |
| **合计** | **10** | 覆盖全部 7 条核心链路 |

## 建议测试类型分布
- **集成测试**（8 项）：主链路价值所在——跨 Controller/Service/MQ/ES/模型，单测够不着。当前项目**集成测试=0**，这是最大短板，应优先补。
- **Characterization Test**（2 项：#7 实验状态机、#9 ES pipeline）：针对"逻辑复杂、即将重构、改前先锁现状"的场景，不改语义、只加护栏。
- **单元测试**：本表未单列——现有 17 个单测已覆盖叶子组件，缺口不在单测层。

## 怎么用这份表
1. **排期**：P0 五条是"动相关代码前的前置任务"，进相关迭代的 Definition-of-Done；P1 随改造机会补。
2. **最小有效集**：若资源有限，先补 **#5 实验 happy** + **#1 登录** + **#3 KB 索引** 三条——覆盖最高风险、最常改、爆炸半径最大的链路。
3. **每条都映射到** 10 的接口 + 05 的表，可直接落成具体用例。
