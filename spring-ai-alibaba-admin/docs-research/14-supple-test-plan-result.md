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
