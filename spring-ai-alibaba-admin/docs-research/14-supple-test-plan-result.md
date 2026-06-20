# 补测试结果（14-supple-test-plan-result）

> 对应：[`13-test-plan.md`](./13-test-plan.md) **批次 1**（Characterization，#9 ES ingest pipeline 解析）。
> 执行：2026-06-20｜`mvn test -B`｜**18/18 通过，BUILD SUCCESS**（17 → 18）。

## 产出

新增测试：`spring-ai-alibaba-admin-core/src/test/java/com/alibaba/cloud/ai/studio/core/observability/LoongsuiteTracesPipelineCharacterizationTest.java`
- 类型：**Characterization Test**（先实测记录行为，再固化断言；不写"应该是什么"）。
- 被测对象：ES ingest pipeline `parsing_loongsuite_traces` + `loongsuite_traces` 映射（定义在 `docker/middleware/init/elasticsearch/init-indices.sh`，改造它/映射时易静默坏）。
- 手法：向本地 ES 的 `_ingest/pipeline/<id>/_simulate` 投放代表性 OTLP trace 文档，断言 pipeline **实际**产出。
- 健壮性：无 ES 时 `Assumptions.assumeTrue` 跳过（不致 `mvn test` 失败）；本次 ES 在跑，**实际执行并通过**（0.44s）。

## 场景 / 预期（实测锁定）/ 实际跑出

| # | 场景 | 预期结果（2026-06-20 实测锁定） | 实际跑出 | 状态 |
|---|---|---|---|:--:|
| 0 | pipeline 探活 | ES 中 `parsing_loongsuite_traces` 存在（GET 200）；`_simulate` 返回 200 | GET 200；simulate 200 | ✅ |
| 1 | `contents` rename | 整体改名 `metadata`；span 字段(traceID/name/service/duration/otlp…)保留；`attribute/resource/links/logs` 子字段被 remove | 完全一致 | ✅ |
| 2 | `contents.attribute` → `attributes` | 解析 JSON 串为扁平对象；**token 值保持 String**（`"10"`/`"20"`，json processor 不转 long） | `"10"`/`"20"`/`v` | ✅ |
| 3 | `contents.resource` → `resources` | 扁平：`service.name=agent-svc` | 一致 | ✅ |
| 4 | `contents.links`/`logs` → `spanLinks`/`spanEvents` | nested 数组：links[0].traceID=`t2`、logs[0].name=`log1` | 一致 | ✅ |
| 5 | `usage` 计算 | script 把 String token 转 **long** 并求和：`input=10 / output=20 / total=30` | 10/20/30 (long) | ✅ |
| 6 | 顶层无关字段 | pipeline 不触碰：`time=1000`、`tags.env=test` 原样保留 | 一致 | ✅ |

> 关键锁定点（Characterization 的价值）：**`attributes` 里 token 是 String、而 `usage` 里是 long**——两者不一致是有意为之（script 读 String 做 `Long.parseLong`）。若有人"顺手"把 attributes 也改成 long，script 的解析会坏；此测试能在改造时拦住这类静默回归。

## mvn test 总览

| 指标 | 之前（11-test-status） | 现在 |
|---|---|---|
| 测试方法数 | 17 | **18**（+1） |
| 通过 / 失败 / 跳过 | 17 / 0 / 0 | **18 / 0 / 0** |
| 构建 | SUCCESS | **SUCCESS** |
| 新增测试类 | — | `LoongsuiteTracesPipelineCharacterizationTest`（1 个方法） |

各测试类均绿（无 flaky）。新增测试 0.44s（含一次 ES simulate HTTP 往返）。

## 结论

- **批次 1 完成**：核心链路 ⑥（Trace 摄取与查询）的"ES pipeline 解析"行为已被 Characterization 锁定——改造 `parsing_loongsuite_traces` / `loongsuite_traces` 映射时有护栏了。
- **覆盖升级**：对应 [`11-test-status.md`](./11-test-status.md) 链路 ⑥ 由 🔴 没有 → 🟡 部分（pipeline 解析侧有兜底；查询侧 `TracingRepository` 仍无，留待后续批次）。
- **复跑命令**：`mvn test -pl :spring-ai-alibaba-admin-server-core -Dtest=LoongsuiteTracesPipelineCharacterizationTest`（需本地 ES + pipeline 已装入）。

---

## 批次 2：实验状态机（Characterization）— 已完成

新增测试：`spring-ai-alibaba-admin-server-start/src/test/java/.../service/impl/ExperimentStateMachineCharacterizationTest.java`
- 类型：**Characterization Test**（Mockito 单元级；刻画不依赖模型/异步的同步状态逻辑）。
- 被测：`ExperimentServiceImpl` 的状态转换规则（create / stop / delete）。
- 手法：@Mock 全部协作者 + @InjectMocks；create 用 `evaluationObjectConfig.type="other"` 使异步执行空转、不触模型。

| 场景 | 预期（实测锁定） | 实际跑出 | 状态 |
|---|---|---|:--:|
| create | status 立即置 **RUNNING**（非 DRAFT），progress=0，insert | RUNNING + insert | ✅ |
| stop(RUNNING) | → STOPPED（updateById） | STOPPED | ✅ |
| stop(终态 COMPLETED/FAILED/STOPPED) | no-op，不改状态、不 update | 不变 + 不 update | ✅ |
| delete(RUNNING) | 抛 IllegalStateException（禁删运行中） | 抛 IllegalStateException | ✅ |
| delete(非 RUNNING) | 正常删除 | 删除 | ✅ |

mvn test：**5/5 通过**（0.44–2s）。关键锁定点：**create 后即 RUNNING（非 DRAFT）**、stop 对终态是 no-op、delete 对 RUNNING 有守卫——这些是改造状态机时易改坏的语义。
> 未覆盖：RUNNING→COMPLETED/FAILED（经异步模型调用 `executeExperiment`→`ChatClient.call`），属批次 4，需模型（见下"阻塞"）。

---

## 批次 3：鉴权集成（#1+#2）— 已完成

新增测试：`spring-ai-alibaba-admin-server-start/src/test/java/.../builder/AuthIntegrationTest.java`
- 类型：**集成测试**（`@SpringBootTest` + `@AutoConfigureMockMvc` + `@ActiveProfiles("local")`，起完整应用上下文，连真实 MySQL/Redis/Nacos；MockMvc 走含拦截器的 Spring MVC 层，打种子账号 saa）。
- 被测：`AuthController.login` + `TokenAuthInterceptor`（核心链路 ①）。
- 上下文启动 19.3s；4 个用例全过。

| 场景 | 预期（实测） | 实际跑出 | 状态 |
|---|---|---|:--:|
| 正确登录 saa/123456 | 200 + `data.access_token` 非空 | 200 + token | ✅ |
| 错误密码 | 401（BizException→全局处理） | 401 | ✅ |
| 受保护 `/console/v1/accounts/10000` 无 token | 401（拦截器拒） | 401 | ✅ |
| 同接口 + 有效 `Authorization: Bearer <token>` | 200（拦截器放行，返回 account_id=10000） | 200 + account_id=10000 | ✅ |

mvn test：**4/4 通过**（21.9s，含上下文启动）。覆盖升级：链路 ①（登录鉴权）由 🔴 没有 → 🟢 **有集成兜底**（登录 + 拦截器放行/拒绝已闭环）。

---

## 批次 4/5/6：模型依赖阻塞（诚实汇报，未实现）

这三批的核心【成功态】都依赖 AI 模型调用，而本环境 `model-config.yml` 为空（无 API Key），无法在无模型下达到成功态——属**缺失前置条件**（非重试可修），按规则停下汇报，不硬凑。

| 批次 | 链路 | 卡点（模型依赖） | 当前无模型下的实际表现 |
|---|---|---|---|
| **4** 实验 happy 全流程 | ⑤ | `executeExperiment`→`getPromptResult`→`ChatClient.call()` + `getEvaluatorResult`→evaluator 模型调用 | 异步执行必抛错→`status=FAILED`（到不了 COMPLETED，无 score） |
| **5** KB 异步索引 | ③ | 切片向量化需 `EmbeddingModel` | 写不进 ES 向量→`document.index_status` 卡住/失败（到不了 completed，retrieve 命中不了） |
| **6** 对话/工作流执行 | ④ | `ChatController`→graph-core 运行时→模型推理 | 执行即报错/空响应（流式无内容） |

**根因**：`model-config.yml` 空（"以空配置启动"），模型调用 seam（`ChatClient`/`ChatModel`/`EmbeddingModel`）在缺 key/缺模型 bean 时运行期失败。

**解锁选项（择一）**：
1. **配真实模型 Key**（最快）：把 `model-config-dashscope.yaml` 复制为 `model-config.yml` 并填 DashScope/OpenAI/DeepSeek 的 API Key（+ 保证网络可达）。我即可用 `@SpringBootTest` 跑通 4/5/6 的 happy 集成测试。
2. **Mock 模型 seam**（不依赖外部）：在测试里用 `@MockBean`/`@TestConfiguration` 提供 `ChatModel`/`EmbeddingModel` 桩（固定返回），并补 dataset_version/items、evaluator_version、prompt_version、knowledge_base+文档等种子数据，再处理实验异步时序。工作量**每批约 1–2 人日**（种子 + 异步 + 断言），需分多次推进。
3. **暂缓**：4/5/6 留到有模型环境或专门排期再做；当前已有批次 1/2/3 兜住（pipeline 解析、实验状态机、鉴权）三条非模型核心链路。

> 已完成批次（1/2/3）新增测试合计 **10 个方法**（pipeline 1 + 状态机 5 + 鉴权 4），全部通过；`mvn test` 总数 17 → **27**。
