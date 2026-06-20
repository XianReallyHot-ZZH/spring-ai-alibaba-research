# 补测试计划（13-test-plan）

> 依据：[`12-test-gaps.md`](./12-test-gaps.md)。把 P0 缺口拆成批次（每批 1–2 个，尽量 1 个）。
> 排序原则：**改造路径上的 Characterization > 核心链路集成 > 复杂逻辑单元**。简单 CRUD 不进计划。
> 说明：P0 五项**全为集成测试、无 Characterization**；为遵循上述排序，把 12 里 2 个 **P1 Characterization**（#9 ES pipeline、#7 实验状态机）作为**前置批次**纳入、排最前（标记 *P1-前置*，可按需取舍）。其余为 P0 集成。

## 批次总表（按执行顺序）

| 批次 | 测试类型 | 覆盖核心链路 | 内容（缺口#） | 来源 | 预期工作量 |
|:--:|---|---|---|---|---|
| **1** | **Characterization** | ⑥ Trace 摄取与查询 | #9 ES ingest pipeline `parsing_loongsuite_traces` 对样例 trace 的字段/token 解析（json flattening、usage 提取） | P1-前置 | **S**（≈0.5–1d） |
| **2** | **Characterization** | ⑤ 评估实验执行 | #7 实验状态机与控制（`DRAFT/RUNNING/COMPLETED/FAILED/STOPPED`、`stop`/`restart`、`progress`） | P1-前置 | **M**（≈1–2d） |
| **3** | **集成测试** | ① 登录鉴权 | #1 登录全流程 + #2 拦截器校验（有效→token；错密/禁用→拒；过期伪造→401；排除路径放行） | P0 | **M**（≈1–2d） |
| **4** | **集成测试** | ⑤ 评估实验执行 | #5 实验 happy 全流程（建 experiment → 跑 dataset_version×evaluator_version → 模型打分 → result 有 score → `COMPLETED`） | P0 | **L**（≈2–3d） |
| **5** | **集成测试** | ③ 知识库文档索引 | #3 异步索引主链路（建/重索引 → RocketMQ → ES → `index_status` completed → `retrieve` 命中） | P0 | **L**（≈2–3d） |
| **6** | **集成测试** | ④ 对话/工作流执行 | #4 执行入口请求处理（合法路由到 runtime/流式/async；非法/缺 app/缺参→正确 4xx） | P0 | **L**（≈2–4d） |

> 工作量口径：S≈0.5–1 人日 / M≈1–2 / L≈2–4，假设开发已熟悉相关代码。合计 ≈ **9–15 人日**。

## 排序理由

1. **批次 1–2（Characterization）排最前**：`#9`（ES pipeline）、`#7`（实验状态机）逻辑复杂、且"改了会静默坏/状态语义易改"，是**重构前先锁现状**的典型场景——只加测试不改语义，给后续改造兜底。`#9` 先做（更独立、最小），`#7` 后做（依赖对实验流的理解）。
2. **批次 3（鉴权）在集成里排第一**：①爆炸半径最大；②它是**后续集成测试的基础设施**——批次 4/5/6 调受保护接口都要 token，先做出可复用的"登录拿 token"测试助手。
3. **批次 4–6（其余 P0 集成）按 风险×可隔离性 排**：实验执行（最复杂、0 覆盖）→ KB 索引（异步 MQ+ES）→ 对话执行（依赖外部 graph-core runtime + 模型，最难隔离，放最后）。
4. **无"复杂逻辑单元"批次**：现有 17 个单测已覆盖叶子组件（切片/读取/重排/加密等），缺口不在单元层。

## 前置基础设施（开工前一次性准备）

- **集成测试基座**：`@SpringBootTest` + 一个 `test` profile 指向本机 docker 中间件（MySQL/ES/MQ/Nacos/Redis 已能起），或用 **testcontainers**（ES/RocketMQ/MySQL）使测试自包含、不依赖手动起栈。
- **Mock 模型助手**：批次 4/6 需要——把模型调用 stub 成固定返回，避免依赖真实 API Key/网络。
- **鉴权助手**（批次 3 产出，4/5/6 复用）：封装"用种子账号登录拿 access_token + 注入 `Authorization: Bearer`"。
- **种子数据**：批次 4 需要 dataset/dataset_version/evaluator/evaluator_version 的种子行；批次 5 需要 knowledge_base + 样例文档。

## 交付与验收（每批）

- 每批产出可独立运行（`mvn -pl :<module> -Dtest=... test`）的测试类 + 必要的种子/助手。
- 验收：本批测试在新环境能稳定绿（无 flaky）；并补一条到 [`11-test-status.md`](./11-test-status.md) 的对应链路覆盖升级（🔴→🟡/🟢）。
- 范围护栏：每批**只测该链路的关键路径与边界**，不横向扩到无关 CRUD（保持宁少勿多）。

## 建议落地节奏
- **先做批次 3（鉴权）**：投入中等、收益最大（解锁其余集成测试 + 兜住爆炸半径最大的链路）。
- **再做批次 4（实验）+ 批次 1（ES pipeline Char）**：覆盖最高风险链路 + 锁住即将改的 pipeline。
- 批次 2/5/6 视迭代节奏排期。
