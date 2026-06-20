---
name: env-bootstrap
description: Bootstrap or verify a project's local dev environment end-to-end. Use when (1) newly taking over a project and needing to run it locally, (2) resetting/rebuilding a broken environment, or (3) periodically verifying environment health. Runs five phases — dependency inventory → install middleware → start/stop scripts → compile & start app → API smoke test — then emits a verification report. Handles real-world gotchas with self-repair (China registry mirrors for Docker/Maven/npm, host port conflicts, Windows CRLF/WSL2/container-user permission, Node/JDK version mismatches, postinstall chicken-and-egg, upstream compile bugs) and waits for true readiness, not just "started". Stop and report only after 3 consecutive failures of the same error.
allowed-tools: Read, Bash, Write
---

# Env Bootstrap

把一个项目的本地开发环境从零跑起来（或验证已有环境），并给出验证报告。通用、不限技术栈（Java/Node/Python/Go + Docker 中间件皆可）。

## 何时用 / 何时不用

- **用**：新接手项目要本地跑通；环境坏了要重置重建；定期体检环境健康。
- **不用**：单次小改动（直接跑即可）；生产/CI 部署。

## 原则

1. **盘点先于操作**——先摸清栈与要求，不臆测。
2. **每步等真就绪**——轮询真实健康信号（ping/health/日志 started），而非"进程已起"。
3. **自修复**：读报错 → 判因（版本/源/权限/依赖缺失/鸡生蛋）→ 修（换源/换版本/加 sudo/装前置/调顺序）→ 重试。**同一错误连续 3 次停下汇报**，不空转。
4. **工具约束**：本 skill 只用 `Read`/`Bash`/`Write`——搜索/检视用 Bash(`grep`/`find`/`ls`/`cat`/`curl`)，建文件用 Write，读文件用 Read。

## Phase 0 — 确认范围

先问/确认触发场景（新接手 / 重置 / 健康验证）。健康验证可只跑 Phase 1 + Phase 5（+ 中间件 status）；新接手/重置跑全流程。

## Phase 1 — 依赖盘点

用 Read 读 `README*` / `CONTRIBUTING*` / `CLAUDE.md` / `Makefile`；用 Bash 扫 `pom.xml` / `package.json` / `requirements.txt` / `go.mod` / `docker-compose*.yaml` / `.env.example` / `application*.yml`。盘点出：
- **工具链 + 版本要求**：JDK / Maven / Node / Python / Go / Docker + Compose。
- **中间件清单**：每个的镜像+版本、宿主端口、凭证、初始化要求（建库 SQL/建索引/建 topic/建命名空间）。
- **构建命令、启动命令、profile/env 切换**、应用监听端口、管理界面地址。
- 用 Bash 查本机已装版本（`java -version`、`mvn -v`、`node -v`、`docker --version` 等）对比 → 列出 gap。

产出：一份依赖盘点（直接报告，或 Write 到项目的 docs 目录）。

## Phase 2 — 装中间件

优先 **docker-compose**（版本固定、自带 init 容器）。从 compose 目录 `docker compose up -d`。逐项处理：

- **国内网络**：docker.io 易被拦（`auth.docker.io ... EOF`）。先测可用镜像源（如 `docker.m.daocloud.io`，拉 hello-world 验证），再写一个 **compose override** 把 docker.io 镜像改走镜像源；本项目自有 registry（如 elastic.co、阿里云）通常可达，不动。
- **端口冲突**：起前 `netstat -ano`/`ss -ltn` 扫项目要用的端口；被占则换宿主端口（override `ports: !override`）或停占用服务。
- **init/conf 挂载**：`${MIDDLEWARE_HOME}/init`、`${VAR}/conf` 这类路径必须指向**真实存在**的目录——若把数据根指到别处，记得把项目的 `init/`+`conf/` 拷过去同目录，否则建表 SQL/初始化脚本/配置挂不进容器。
- **Windows 特有**：Git checkout 的 `.sh` 是 CRLF，Linux 容器 `sh` 会报 `: not found` → `sed -i 's/\r$//'` 去 CR；compose 里 `user:"${UID}:${GID}"` 在 Windows bind mount 上常致 `Permission denied` → override 成 `"0:0"`（root）。
- **等就绪**：轮询真实信号——MySQL `mysqladmin ping`、Redis `redis-cli ping`、ES `/_cluster/health`、MQ `mqadmin clusterList`、Nacos/应用日志出现 `started successfully`、OTLP 端口监听。

## Phase 3 — 启停脚本

确认项目是否已有一键脚本；没有则用 Write 生成 3 个（复用 Phase 2 的 compose 调用与就绪探针）：

- **start**：`compose up -d` + **等全部就绪**后返回。注意 warm restart 时一次性 init 容器常非幂等（重建已存在索引/topic 会假失败），要兜底——对依赖它的服务用 `up -d --no-deps <svc>` 强起。
- **stop**：`compose down`（**保留数据卷**，勿 `-v`，除非要重置数据）。
- **status**：逐项打印 容器状态 + 宿主端口监听 + 便宜的健康抽检。

## Phase 4 — 编译启动

- **包管理镜像（国内，防拉取超时）**：Maven→写 `~/.m2/settings.xml` 加 Aliyun；npm→`npm config set registry https://registry.npmmirror.com`；pip→清华/阿里源。
- **构建**：`mvn clean package -DskipTests` / `npm install` / `npm run build` 等（按盘点）。
- **踩坑自修**：
  - **编译失败（缺类/符号）**：多是上游 bug 或本地状态污染。用 Bash 查 `git log` / 全仓引用；若是死引用（仅一处、无 get/set 调用），最小修复=删该引用。
  - **运行时版本不兼容**（如旧 binding 被移除、工具链不兼容新版运行时）：用版本管理器（Node→Volta/nvm，JDK→sdkman/jabba，Python→pyenv）切到要求的 LTS；**项目级 pin**（如 `volta pin`）避免影响全局其它项目。
  - **postinstall 鸡生蛋**（setup 脚本在 install 阶段就要某个 build 产物）：`npm install --ignore-scripts` 先把依赖装全，再显式 build 产出，dev 时再自行 setup。
- **启动**：用连本机中间件的 profile/env（如 `-Dspring.profiles.active=local`）。后台起，轮询应用端口 + `actuator/health` 或等价健康端点。
- **可选配置**（模型 API key、第三方 token 等）：缺则记录"功能降级"，不阻塞启动。

## Phase 5 — 接口冒烟

- **鉴权**：找登录/令牌接口（`POST /.../login`），调通拿到 token（Bash `curl` + `grep -oE`/`sed` 提取）。
- **挑核心只读接口**：每个主要业务模块选 1 个列表/详情 GET（约 5 个），覆盖面优先。
- **带 token 调**：HTTP **200 = 通过**；**400（缺必填参）→ 补参重测**（看报错字段名/类型）；**401/403 → 核 token 头格式/过期**；**5xx → 列为问题**。
- 产出冒烟报告：每接口 方法+路径+参数+HTTP+结果片段。

## Phase 6 — 汇总报告

Write 一份结论到 `docs*/scripts/*-bootstrap-log.md`（或项目约定位置）：哪些就绪、哪些降级（及补齐方式）、哪些阻塞（及卡点）；附**验证清单**（checkbox）与**复跑命令**。向用户给出口径：环境状态 + 访问地址 + 下一步。

---

## 通用踩坑速查（按实战频次）

| 现象 | 根因 | 解决 |
|---|---|---|
| 拉镜像 `... EOF` / 超时 | docker.io 被拦 | 测可用源 → override 改走国内镜像 |
| 容器 `:PORT bind ... in use` | 宿主端口被占 | 起前扫端口；换宿主端口或停占用服务 |
| `.sh: ... not found` / `not in a function` | Git 把 .sh 转 CRLF | `sed -i 's/\r$//'` 去 CR |
| `Permission denied`（容器内读脚本/写数据） | `user:` 非 root + bind mount | override `user:"0:0"` |
| init 找不到脚本/配置没挂进 | `MIDDLEWARE_HOME` 类变量指错 | 指向含 init/conf 的真实目录，或拷过去 |
| 前端 `No such module: http_parser` 类 | 运行时版本太新，工具链不兼容 | 版本管理器切到要求 LTS，项目级 pin |
| `umi setup`/postinstall 失败要 build 产物 | install 阶段 setup 要 dist（鸡生蛋） | `--ignore-scripts` 装全 → 显式 build → dev 再 setup |
| 编译 `找不到符号 X` | 上游误删/本地污染，X 是死引用 | 查引用面，最小删引用 |
| 包依赖拉取慢/超时 | 直连中央仓慢 | 配国内镜像（Maven Aliyun / npm npmmirror） |
| 容器"已起"但接口不通 | 没等真就绪 | 轮询 ping/health/日志 started，非 up 即返回 |

> 自修复铁律：每个错误先看报错原文判因，针对性修后重试；同一错误连续 3 次不过，停下向用户汇报具体卡点，不盲目循环。
