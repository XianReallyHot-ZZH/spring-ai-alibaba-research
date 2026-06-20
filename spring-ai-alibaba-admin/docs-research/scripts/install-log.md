# 安装日志（install-log.md）

> 脚本：`docs-research/scripts/install-deps.sh` ｜ override：`docs-research/scripts/docker-compose-mirror.yaml`
> 执行机：Windows 11 / Git Bash (MINGW64) ｜ 日期：2026-06-20
> **结论：✅ 全部中间件已启动并初始化成功（9 个常驻服务 Up，建库/建索引/建 topic 均完成）。** 过程中共遇 7 个问题，均已自修复。

---

## TL;DR — 最终状态

| 中间件 | 版本 | 宿主端口 | 状态 | 初始化验证 |
|---|---|---|---|---|
| MySQL | 8.0.35 | 3306 | ✅ Up (healthy) | `admin` 库 **27 张表**已加载（account/application/dataset/experiment/knowledge_base/model_config/prompt/tool…） |
| Redis | 7.2.5 | 6379 | ✅ Up (healthy) | `redis-cli ping` → PONG |
| Elasticsearch | 9.1.2 | 9200/9300 | ✅ Up (healthy) | 索引 `loongsuite_traces` + pipeline `parsing_loongsuite_traces` 已建（HTTP 200） |
| Kibana | 9.1.2 | 5601 | ✅ Up | `/api/status` → 200 |
| LoongCollector（OTLP） | 3.1.4 | 4318 | ✅ Up | :4318 监听中（GET / 返 404 为正常，OTLP 走 POST /v1/traces） |
| Nacos | latest（3.x） | 8848(gRPC)/7848(API)/7080(控制台) | ✅ Up | 日志 "Nacos started successfully"；应用走 `server-addr=localhost:8848`(gRPC) |
| RocketMQ namesrv/broker/proxy | 5.3.2 | 9876/10911/18080 | ✅ Up (healthy) | topic `topic_saa_studio_document_index` + 消费组已建 |

容器状态（`docker ps`）：elasticsearch / kibana / loongcollector / mysql / nacos / redis / rmq_broker / rmq_namesrv / rmq_proxy 全部 **Up**。一次性 init 容器（elasticsearch-init / rmq-init-topic）已成功完成退出。

---

## 自修复全过程（7 个问题 → 逐个击破）

| # | 问题 | 现象/报错 | 诊断 | 修复 |
|---|---|---|---|---|
| 1 | 脚本路径算错层级 | `cd docker/middleware: No such file` | `PROJECT_ROOT` 多上了一级（`../../..` 应为 `../..`，跑到 monorepo 根） | 改 `SCRIPT_DIR/../..` |
| 2 | compose 缺 `.env` | `env file ./.env not found` + `${UID}/${GID}` 未设 | rmq 服务声明 `env_file: ./.env`；项目 `run.sh` 会生成它，脚本绕过了 | 脚本在 compose 前生成 `.env`（UID/GID/TZ/MIDDLEWARE_HOME） |
| 3 | Docker Hub 拉取被拦 | `auth.docker.io/token ... EOF`（nacos/rocketmq/redis 拉不动） | 国内网络对 docker.io 拦截；测得 `docker.m.daocloud.io` 可用 | 写 override，docker.io 4 镜像改走 daocloud（`USE_CN_MIRROR=1`） |
| 4 | 宿主 3306 被占 | `ports are not available ... :3306 bind` | 原生 `mysqld` 服务（PID 5580）占 3306，非 admin 杀不掉 | override 用 `ports: !override ["3307:3306"]` 把 docker mysql 映射到 **3307** |
| 5 | RocketMQ 起不来 | `cannot open runserver.sh: Permission denied`，rmq 循环重启 | compose 的 `user:"${UID}:${GID}"`=1000:1000，读不了 root 属脚本 | override 把 rmq/mysql 的 `user` 改回 `"0:0"`（root，镜像默认） |
| 6 | init/conf 没挂载 | elasticsearch-init `can't open init-indices.sh`；rmq_proxy 拿不到配置 | 我把 `MIDDLEWARE_HOME` 指到 `D:/Developer/DeveloperInstall/middleware`，但 compose 用 `${MIDDLEWARE_HOME}/{init,conf}` 挂载**项目的 init 脚本/配置**（只在 `docker/middleware` 下） | 脚本把项目 `init/`+`conf/` 拷到 DeveloperInstall/middleware，数据 + init + conf 同目录 |
| 7 | shell 脚本 CRLF | init-indices.sh 报 `: not found` / `not in a function` | Git 在 Windows checkout 把 `.sh` 转 CRLF，Linux 容器 `sh` 把 `\r` 当命令 | 拷贝后 `sed -i 's/\r$//'` 去 CR（已固化进脚本）；重建 elasticsearch-init → 索引创建成功 |

> 关键转折：问题 6 是最深的根因——一个 `MIDDLEWARE_HOME` 指向错误，同时引发了 mysql 未加载建表 SQL、ES 找不到 init 脚本、rmq_proxy/loongcollector 拿不到配置三个症状。修正后做了一次 `down -v` + 清空数据目录的全新初始化，mysql 才正确加载 27 张表。
>
> **补充（恢复项目默认端口）**：问题 4 的 3307 是临时避让。后续在管理员窗口 `net stop MySQL` + `Set-Service MySQL -StartupType Manual` 停掉原生 mysqld，把 override 的 mysql 端口从 3307 改回 3306（删除 `ports: !override`），`docker compose up -d --force-recreate mysql` → docker mysql 回归 **3306**（数据复用，27 表不变）。`Get-Service MySQL` = Stopped、3306 归属 = `com.docker.backend`。

---

## 验证证据（实测）

```
MySQL 表数:        27  （SELECT COUNT(*) ... table_schema='admin'）
MySQL 关键表:      account,application,dataset,experiment,knowledge_base,model_config,prompt,tool ✔
Redis:             PONG
ES pipeline:       GET /_ingest/pipeline/parsing_loongsuite_traces → 200
ES index:          GET /loongsuite_traces/_mapping → 200
RocketMQ topic:    topicList 含 topic_saa_studio_document_index ✔
Kibana:            /api/status → 200
Nacos:             日志 "Nacos started successfully in stand alone mode"
MySQL 宿主端口:    3306/tcp -> 0.0.0.0:3306   （原生 mysqld 已停，恢复项目默认端口）
```

---

## 运行应用时的注意事项

1. **MySQL 在项目默认端口 3306**（原生 `MySQL` 服务已停 + 设为手动启动防自启，override 已改回 3306）。后端直接用 `application-local.yml` 默认连接即可，无需覆盖端口：
   ```bash
   mvn -pl :spring-ai-alibaba-admin-server-start spring-boot:run
   ```
2. 其余中间件端口与 `application-local.yml` 默认一致：Redis 6379 / ES 9200 / Nacos `server-addr=localhost:8848` / RocketMQ `endpoints=localhost:18080` / OTLP `localhost:4318`。
3. **数据/安装位置**：中间件数据落 `D:\Developer\DeveloperInstall\middleware`（D 盘，不用 C 盘）。Docker 镜像层在 Docker Desktop 的 WSL2 内（若要挪到 D 盘：Settings > Resources > disk image location）。
4. 中间件命令：启动用 `bash docs-research/scripts/install-deps.sh`；停止 `cd docker/middleware && docker compose -f docker-compose-prod.yaml -f ../../docs-research/scripts/docker-compose-mirror.yaml down`。

---

## 产物文件

- `docs-research/scripts/install-deps.sh` — 跨 OS 安装脚本（含 `.env` 生成、国内镜像 override、init/conf 拷贝、CRLF 修复、逐项验证）。
- `docs-research/scripts/docker-compose-mirror.yaml` — 本地环境 override（docker.io→daocloud、mysql 3307+root、rmq root）。
- `docker/middleware/.env` — 由脚本生成（UID/GID/TZ/MIDDLEWARE_HOME）。
