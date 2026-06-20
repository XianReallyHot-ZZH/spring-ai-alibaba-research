# 新人上手指南（09-setup-guide）

> 目标：从零把 **Spring AI Alibaba Admin（Agent Studio）** 在本地完整跑起来——中间件 + 后端 + 前端。
> 这是"照着做"的精简版；完整调试历史见 [`scripts/install-log.md`](./scripts/install-log.md)（装中间件）与 [`scripts/startup-log.md`](./scripts/startup-log.md)（起应用）。
> 跑通后你将得到：后端 API `:8080`（含 Swagger UI）、前端控制台 `:8000`、全套中间件。

---

## 1. 前置条件

| 依赖 | 版本 | 说明 |
|---|---|---|
| JDK | **17+**（21 亦可） | 后端编译/运行（`java.version=17`） |
| Maven | **3.8+** | 后端构建 |
| Docker Desktop + WSL2 | Compose 2+ | 中间件走 docker-compose；需 WSL2 后端 |
| Node（前端） | **20 LTS** | ⚠️ 前端工具链与 Node 22+ 不兼容，**必须 20**；建议用 Volta 管理（默认 24、前端 pin 20） |
| 内存 | ≥ 8GB | 中间件全集较吃内存 |
| 模型 API Key | 可选 | DashScope/OpenAI/DeepSeek 其一；不填也能启动，仅 AI 调用功能不可用 |

**Windows 约定**：数据/安装放 **`D:\Developer\DeveloperInstall`**（不用 C 盘）；Docker Desktop 在 *Settings → Resources* 把 disk image 也设到 D 盘。
**国内网络**：Maven/npm/Docker Hub 都建议配国内镜像（下文步骤已含），否则拉取易超时。

---

## 2. 装中间件（一键脚本，推荐）

```bash
cd spring-ai-alibaba-admin
bash docs-research/scripts/install-deps.sh        # 启动 + 初始化 + 逐项验证，等就绪
```

脚本自动完成：生成 `.env`、docker.io 镜像改走 daocloud、把项目 `init/`+`conf/` 拷到数据目录、去除 shell 脚本 CRLF、MySQL 自动建库建表 / ES 建索引 / RocketMQ 建 topic、逐项健康验证。数据落 `D:\Developer\DeveloperInstall\middleware`。

> 手动等价：`cd docker/middleware && ./run.sh prod`（但上面的脚本已把国内网络/Windows 权限等坑都处理了，推荐用脚本）。

**日常操作**（中间件已装好后）：
```bash
bash docs-research/scripts/deps-start.sh     # 启动并等就绪
bash docs-research/scripts/deps-status.sh    # 查状态（容器+端口+健康抽检）
bash docs-research/scripts/deps-stop.sh      # 停止（保留数据）
```

---

## 3. 启动后端

**3.1 Maven 国内镜像**（首次，防依赖拉取超时）——写 `C:\Users\<你>\.m2\settings.xml`：
```xml
<settings><mirrors><mirror>
  <id>aliyun</id><mirrorOf>central</mirrorOf>
  <url>https://maven.aliyun.com/repository/public</url>
</mirror></mirrors></settings>
```

**3.2 构建**（admin 根目录）：
```bash
mvn clean package -DskipTests
# 产物：spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar
```

**3.3 配模型 Key（可选，AI 功能）**——复制模板为 `model-config.yml` 并填 Key：
```bash
cd spring-ai-alibaba-admin-server-start
cp model-config-dashscope.yaml model-config.yaml   # 或 -openai.yaml / -deepseek.yaml
# 编辑 model-config.yaml，填 apiKey（DashScope 走 DASHSCOPE_API_KEY 等）
```

**3.4 启动**（用 `local` profile 连本机中间件）：
```bash
java -Dspring.profiles.active=local -jar target/spring-ai-alibaba-admin-server-start.jar
# → Started SaaStudioAdmin，监听 :8080
```

---

## 4. 启动前端

**4.1 Volta 管 Node 版本**（一次性）：
```powershell
# 装 Volta（MSI，管理员）：https://volta.sh
volta install node@20.18.1      # 前端用
volta install node@24.12.0      # 你原本的全局默认（其它项目用）
cd spring-ai-alibaba-admin\frontend
volta pin node@20.18.1          # 仅此项目固定 20，写进 package.json
```
> 之后 `cd frontend` 自动用 20，`cd` 别处用 24，互不干扰。

**4.2 装依赖 + 构建 spark-flow**（首次）：
```bash
cd frontend
npm install --ignore-scripts    # ⚠️ 必须 --ignore-scripts（绕过 umi setup 鸡生蛋，见踩坑#9）
npm run build:flow              # 产出 spark-flow/dist
```

**4.3 配 .env 并启动**：
```bash
cd packages/main
cp .env.example .env            # WEB_SERVER=http://127.0.0.1:8080，账号 saa/123456
npm run dev                     # → http://localhost:8000（首次编译 ~17-37s）
```

---

## 5. 常见踩坑（按出现频率）

| # | 现象 | 根因 | 解决 |
|---|---|---|---|
| 1 | Docker 拉镜像 `auth.docker.io ... EOF` | 国内对 Docker Hub 拦截 | `install-deps.sh` 已把 docker.io 改走 `docker.m.daocloud.io`（`USE_CN_MIRROR=1`） |
| 2 | 前端 `No such module: http_parser` / esmi 崩 | Node 22+ 移除了旧 binding，Umi 工具链不兼容 | 前端用 **Node 20**（Volta pin），勿用 24 |
| 3 | 前端 `umi setup` postinstall 失败 `Can't resolve spark-flow/dist` | install 阶段 umi setup 要 dist，但 spark-flow 还没构建（鸡生蛋） | `npm install --ignore-scripts` 先装全，再 `npm run build:flow` |
| 4 | 后端编译 `找不到符号 ToolExample` | 上游 commit 误删，`Tool.ToolConfig.examples` 仍引用（死字段） | 删 `Tool.java` 中 `ToolConfig.examples` 字段（仅此一处引用） |
| 5 | `mysql` 容器起不来 `:3306 bind` | 宿主 3306 被原生 mysqld 占 | 停原生 MySQL 服务（`net stop MySQL`，管理员），或把 docker mysql 端口改 3307 |
| 6 | `elasticsearch-init` `can't open init-indices.sh` / `rmq_proxy` 拿不到配置 | `MIDDLEWARE_HOME` 指错，init 脚本/配置没挂进容器 | `MIDDLEWARE_HOME` 必须指向含 `init/`+`conf/` 的目录（install-deps.sh 已自动拷贝） |
| 7 | RocketMQ `cannot open runserver.sh: Permission denied` | compose 的 `user:"${UID}:${GID}"`=1000 读不了 root 属脚本 | rmq/mysql 容器 `user` 改 `"0:0"`（install-deps.sh 的 override 已含） |
| 8 | `init-indices.sh: : not found` | Git 在 Windows 把 `.sh` 转 CRLF，Linux 容器 sh 解析报错 | 去除 CR：`sed -i 's/\r$//' *.sh`（install-deps.sh 已自动处理） |
| 9 | Maven 拉依赖慢/超时 | 直连 Maven Central 慢 | `~/.m2/settings.xml` 配 Aliyun 镜像（见 3.1） |
| 10 | 后端启动告警 `model-config.yml ... 以空配置启动` | 模型配置为空 | 填 `model-config.yml`（provider+apiKey）；不影响启动，仅 AI 功能不可用 |
| 11 | Nacos 控制台 `:7080/nacos/` 返 500 | 控制台在根 `/`，非 `/nacos/`；应用走 :8848 gRPC | 访问 `http://localhost:7080/`；应用 `nacos.server-addr=localhost:8848` 无需改 |

> 多数坑 `install-deps.sh` 已自动规避；本表供手动操作或排查时对照。完整排障过程见两份日志。

---

## 6. 验证清单

逐项确认，全绿即环境就绪：

**中间件**
- [ ] `bash docs-research/scripts/deps-status.sh` → **9/9 容器 Up**、端口全 `yes`、健康抽检全 ✅
- [ ] MySQL `admin` 库表数 = 27（agentscope + admin 两份 schema）

**后端**
- [ ] `curl http://localhost:8080/actuator/health` → `{"status":"UP",...}`，`db`/`redis`/`elasticsearch` 均 UP
- [ ] `curl http://localhost:8080/swagger-ui/index.html` → 200（API 控制台）

**前端**
- [ ] 浏览器开 `http://localhost:8000` → 出登录页，`saa / 123456` 能登录

**接口冒烟**（详见 [`08-smoke-test-result.md`](./08-smoke-test-result.md)）
- [ ] 登录 `POST /console/v1/auth/login` → 200，拿到 `access_token`
- [ ] `GET /api/prompts`、`/api/dataset/datasets`、`/api/evaluator/evaluators` → 200
- [ ] `GET /api/observability/traces?startTime=&endTime=` → 200（必带时间参数）

---

## 附：每日启动（环境已装好后）
```bash
# 1) 中间件
bash docs-research/scripts/deps-start.sh
# 2) 后端
cd spring-ai-alibaba-admin-server-start && java -Dspring.profiles.active=local -jar target/spring-ai-alibaba-admin-server-start.jar
# 3) 前端（新终端，Volta 自动 Node 20）
cd frontend/packages/main && npm run dev
```
访问：前端 `http://localhost:8000` ｜ 后端 API `http://localhost:8080` ｜ Swagger `http://localhost:8080/swagger-ui/index.html`。
