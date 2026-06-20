# 接口冒烟测试结果（08-smoke-test-result）

> 目标：从 [`04-api-list.md`](./04-api-list.md) 挑 5 个核心接口（覆盖 登录 / Prompt / Dataset / Evaluator / Trace），用 curl 实跑。
> 后端：`http://localhost:8080`（本地已起，`local` profile，中间件在跑）｜ 日期：2026-06-20
> **结论：5/5 通过（HTTP 200）。** 其中 Trace 需带必填时间参数，初次缺参返回 400，补参后 200。

## 鉴权流程
1. `POST /console/v1/auth/login`（账号 `saa` / 密码 `123456`，DB 种子用户）→ 返回 `data.access_token`（JWT）。
2. 后续请求带 `Authorization: Bearer <access_token>`。
> 拦截器 `TokenAuthInterceptor` 覆盖 `/console/v1/**`；`/api/*`（admin 评估/可观测）本次用同一 token 可访问。

## 结果汇总

| # | 模块 | 方法 | 路径 | 关键参数 | HTTP | 结果 |
|---|---|---|---|---|:--:|:--:|
| 1 | 登录 | POST | `/console/v1/auth/login` | `{username:saa,password:123456}` | 200 | ✅ |
| 2 | Prompt | GET | `/api/prompts` | — | 200 | ✅ |
| 3 | Dataset | GET | `/api/dataset/datasets` | — | 200 | ✅ |
| 4 | Evaluator | GET | `/api/evaluator/evaluators` | — | 200 | ✅ |
| 5 | Trace | GET | `/api/observability/traces` | `startTime`,`endTime`(必填) | 200 | ✅ |

## 逐项明细

### 1) 登录 — POST /console/v1/auth/login
```bash
curl -X POST http://localhost:8080/console/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"saa","password":"123456"}'
```
- **200** → `{"data":{"access_token":"eyJ...","refresh_token":"eyJ...","expires_in":...},"code":200,"message":"success"}`
- 取 `data.access_token` 作后续 Bearer token。

### 2) Prompt 列表 — GET /api/prompts
```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/prompts
```
- **200** → `{"data":{"totalCount":0,"totalPage":0,"pageNumber":1,"pageSize":10,"pageItems":[]},"code":200,...}`
- 全新库，无 Prompt 数据（空列表属正常）。

### 3) Dataset 列表 — GET /api/dataset/datasets
```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/dataset/datasets
```
- **200** → `{"data":{"totalCount":0,...,"pageItems":[]},"code":200,...}`
- 空列表，正常。

### 4) Evaluator 列表 — GET /api/evaluator/evaluators
```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/evaluator/evaluators
```
- **200** → `{"data":{"totalCount":1,"totalPage":1,"pageNumber":0,"pageSize":10,"pageItems":[]},"code":200,...}`
- ⚠️ 观察：`totalCount=1` 但 `pageItems=[]`、`pageNumber=0`（其它接口 pageNumber=1）。疑似分页 off-by-one 或计数含未发布/软删数据；HTTP 仍 200，功能可用，建议后续核对。

### 5) Trace 列表 — GET /api/observability/traces
```bash
# startTime/endTime 为必填（String，传 epoch 毫秒）
START=$(($(date +%s%N)/1000000 - 30*86400000)); END=$(($(date +%s%N)/1000000 + 86400000))
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/observability/traces?startTime=$START&endTime=$END"
```
- **缺参时 400**：`{"code":400,"message":"Parameters invalid, startTime: 开始时间不能为空, endTime: 结束时间不能为空."}`
- **补参后 200**：`{"data":{"totalCount":0,...,"pageSize":50,"pageItems":[]},"code":200,...}`
- 暂无 Agent 应用上报 trace（`loongsuite_traces` 索引为空），返回空列表，正常。

## 复跑脚本
```bash
BASE=http://localhost:8080
TOKEN=$(curl -s -X POST $BASE/console/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"saa","password":"123456"}' \
  | grep -oE '"access_token":"[^"]+"' | sed 's/"access_token":"//;s/"$//')
HDR="Authorization: Bearer $TOKEN"
START=$(($(date +%s%N)/1000000 - 30*86400000)); END=$(($(date +%s%N)/1000000 + 86400000))
for p in "/api/prompts" "/api/dataset/datasets" "/api/evaluator/evaluators" "/api/observability/traces?startTime=$START&endTime=$END"; do
  echo "$p -> $(curl -s -o /dev/null -w '%{http_code}' -H "$HDR" "$BASE$p")"
done
```

## 结论
5 个核心接口（登录 / Prompt / Dataset / Evaluator / Trace）**全部 200 通过**；服务端无 5xx。唯一前置条件：Trace 必须带 `startTime`/`endTime`。数据为空属全新库正常状态。一处可跟进的小异常：Evaluator 列表 `totalCount` 与 `pageItems` 不一致，建议核对分页逻辑。
