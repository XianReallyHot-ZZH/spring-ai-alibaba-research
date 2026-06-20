# 应用启动日志（startup-log.md）

> 脚本/产物：后端 `spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar` ｜ 前端 `frontend/`
> 执行机：Windows 11 / Git Bash ｜ 中间件已由 `docs-research/scripts/` 起好（MySQL:3306 / Redis / ES / Nacos / RocketMQ / OTLP 均在跑）
> 日期：2026-06-20
> **结论：✅ 后端 :8080 + 前端 :8000 双双启动成功。** 后端连 MySQL/Redis/ES 全绿；前端用 Node 20 便携版跑通（全局 Node 24 不动）。

---

## TL;DR

| 项 | 状态 | 详情 |
|---|---|---|
| 后端构建 `mvn clean package` | ✅ | 修 1 个上游编译 bug（ToolExample）后，4 模块全过，fat jar 448MB |
| 后端启动 | ✅ | `java -jar -Dspring.profiles.active=local`，27s 起来，:8080，health=UP（MySQL/Redis/ES UP） |
| 前端依赖安装 | ✅ | Node 20 便携版 + `npm install --ignore-scripts` + `build:flow`（added 3146，spark-flow/dist 产出） |
| 前端启动 | ✅ | `npm run dev`（Node 20），:8000，Webpack 编译 11175 模块成功 |

---

## 一、后端构建（mvn clean package）— 修了 1 个上游编译 bug

### 预防性修复
- 写 `%USERPROFILE%\.m2\settings.xml`，加 **Aliyun Maven 镜像**（`https://maven.aliyun.com/repository/public`）——预防国内拉 Maven Central 超时（同 Docker Hub 的教训）。生效（依赖从 aliyun-public 拉）。

### 编译错误（自修复 1 次）
- **现象**：`admin-server-runtime` 编译失败，`Tool.java:[127] 找不到符号 类 ToolExample`（3 处）。
- **根因**：上游 commit `645128ff7 fix: remove misplaced duplicate ToolExample.java` 删了一个错位的教程文件，但 `Tool.ToolConfig` 里 `private List<ToolExample> examples;` 仍引用同包的 `ToolExample`——**这个真正 DTO 全仓不存在**（被删的是另一个同名教程类）。是上游遗漏的编译 bug。
- **修复**：全仓仅此一处引用、且无任何 get/set 调用（死字段）→ 删除 `Tool.java` 中 `ToolConfig.examples` 字段（含注释）。零功能影响，Jackson 默认忽略未知属性。
- **结果**：runtime 编译通过 → core(2:28)/openapi(32s)/start(2:53) 全 SUCCESS → **BUILD SUCCESS**。

### 产物
- `spring-ai-alibaba-admin-server-start/target/spring-ai-alibaba-admin-server-start.jar`（448 MB，含 GraalVM）

---

## 二、后端启动 — ✅ 成功

- 命令：`cd spring-ai-alibaba-admin-server-start && java -Dspring.profiles.active=local -jar target/spring-ai-alibaba-admin-server-start.jar`
- profile=`local`（指向 localhost 中间件，与在跑栈一致：MySQL:3306 / Redis:6379 / ES:9200 / Nacos:8848 / RocketMQ:18080 / OTLP:4318）。
- **26.7s 启动完成**：`Started SaaStudioAdmin`，Tomcat :8080。
- `GET /actuator/health` → **200 UP**，组件全绿：
  - db(MySQL) UP · redis(7.2.5) UP · elasticsearch UP(cluster yellow, 39 shards) · diskSpace UP · ping UP
- **管理/界面端点（后端 :8080）**：
  - Swagger UI（REST API 控制台，~211 接口可交互）：`http://localhost:8080/swagger-ui/index.html` → 200
  - Actuator 健康：`http://localhost:8080/actuator/health` → 200
  - builder 控制台探针：`/console/v1/system/health` → 200；generator：`/graph-studio/api/app` → 200
- 非致命告警：`model-config.yml` 为空 → `FileModelConfigRepository` 报"以空配置启动"。应用照常起；**AI 模型功能需后续在 `model-config.yml` 填真实 provider+API Key**。

---

## 三、前端 — ❌ 被 Node 版本阻塞

### 已完成
- `npm config set registry https://registry.npmmirror.com`（国内镜像）。
- 复制 `packages/main/.env.example` → `.env`（`WEB_SERVER=http://127.0.0.1:8080`，账号 saa/123456）。

### 自修复过程（3 次，止于此）
1. **`npm run re-install` 失败 (exit 127)**：`re-install` 先跑 `clear`（要 `rimraf`），但 node_modules 空 → `rimraf: command not found`。
   - 修复：跳过 clear（无东西可清），改 `npm install && npm run build:flow`（workspaces，root install 装全）。
2. **`npm install` 成功，但 `umi setup` postinstall 失败**：`No such module: http_parser` ← `http-deceiver/lib/deceiver.js` 调 `process.binding('http_parser')`（Node 12+ 移除），由 `@umijs/preset-umi` 内置 esmi 插件加载时触发。
   - 诊断：**lockfile 存在**（版本是团队锁定，非解析漂移）；**无 nvm**；Node 24。降 Node 到 20 LTS 大概率有兼容 shim、24 彻底移除——但本机无 nvm 切不了。
3. **尝试关 esmi 插件**：`.umirc.ts` 无 esmi 开关（内置 preset，不可简单关）；且失败 install 把 node_modules 弄成不一致态。
   - **结论**：前端是硬阻塞，非补丁可解（http-deceiver 的 process.binding 无现代等价；esmi 内置；node_modules 已不一致）。

### 解锁前端（需你来做）
```powershell
# 1) 装 nvm-windows（https://github.com/coreybutler/nvm-windows/releases），然后：
nvm install 20.18.0      # Node 20 LTS
nvm use 20.18.0
# 2) 重装并启动
cd D:\Developer\Github\my-projects\spring-ai-alibaba\spring-ai-alibaba-admin\frontend
rm -r -force node_modules, packages\main\node_modules, packages\spark-flow\node_modules   # 清掉不一致态
npm install
npm run build:flow
cd packages/main
npm run dev              # 前端 :8000，代理到后端 :8080
```

---

## 四、端口与界面汇总

| 服务 | 地址 | 状态 |
|---|---|---|
| 后端 API | `http://localhost:8080` | ✅ UP |
| Swagger UI（API 管理界面） | `http://localhost:8080/swagger-ui/index.html` | ✅ 200 |
| Actuator 健康 | `http://localhost:8080/actuator/health` | ✅ UP |
| 前端控制台 | `http://localhost:8000` | ✅ UP（Node 20，登录账号 saa/123456） |

> 后端已连上全部中间件（MySQL/Redis/ES 健康全绿）。AI 模型相关功能需在 `model-config.yml` 填 provider + API Key 后才可用（当前空配置）。

---

## 五、改动的源文件（自修复遗留，未提交）
- `spring-ai-alibaba-admin-server-runtime/.../plugin/Tool.java`：删除死字段 `ToolConfig.examples`（修上游 ToolExample 编译 bug）。建议作为 issue/PR 反馈上游。
- `~/.m2/settings.xml`、`npm registry`、`packages/main/.env`、`model-config.yml`：本地配置，非源码。

---

## 六、前端最终跑通（Node 20 便携版）— 关键自修复链

第三节里的 Node 24 阻塞，最终用 **Node 20 便携版**绕过（Volta 的 Windows MSI 需管理员、本会话装不了；便携版等效：全局 Node 24 不动，前端用 20，互不影响）。修复链：

1. **http_parser（Node 24 阻塞）** → 换 Node 20（仍保留了 http_parser 兼容 shim，esmi 插件不再崩）。
2. **`umi setup` postinstall 鸡生蛋**：install 阶段 umi setup 经 esbuild 解析 `@spark-ai/flow`→`spark-flow/dist`，但 dist 还没构建 → install 中止 → `father` 没装上 → build:flow 失败。
   → 修：`npm install --ignore-scripts`（跳过 umi setup，让 father 等全部装上）→ `npm run build:flow`（father 可用，产出 `spark-flow/dist`）。dev 时 umi 自行 setup。

### 复现命令（每次新开终端启前端）
```bash
# 1) 用 Node 20 便携版（已下载到 D:\Developer\DeveloperInstall\node-v20.18.1-win-x64）
export PATH="/d/Developer/DeveloperInstall/node-v20.18.1-win-x64:$PATH"
node -v   # 应为 v20.18.1

# 2) 首次：装依赖 + 构建 spark-flow（--ignore-scripts 绕过 umi setup 鸡生蛋）
cd frontend
npm.cmd install --ignore-scripts
npm.cmd run build:flow

# 3) 启动前端
cd packages/main
npm.cmd run dev        # → http://localhost:8000
```
> umi dev 首次编译约 37s（11175 模块）。前端经代理连后端 `WEB_SERVER=http://127.0.0.1:8080`（见 `packages/main/.env`）。

### 关于 Volta（可选，以后做）
若想要"项目级自动切 Node 版本"的便利，可由管理员装 Volta MSI（https://volta.sh），然后在 `frontend/` 执行 `volta pin node@20.18.1`——之后 `cd frontend` 自动用 20，无需手动 `export PATH`。当前便携版方案已等效满足"24/20 共存、互不影响"。

---

## 七、已切换到 Volta（最终方案）

便携 Node 20 已退役，**改用 Volta 管理**（用户已装 MSI）。已完成：
- `volta install node@20.18.1` + `volta install node@24.12.0` → Volta 缓存里同时有 20 和 24。
- `cd frontend && volta pin node@20.18.1` → 写入 `frontend/package.json` 的 `"volta":{"node":"20.18.1"}`。
- **Volta 默认 = 24.12.0（全局及其它项目用 24）；前端 pin = 20.18.1（仅 frontend 目录用 20）。** 项目 pin 优先于默认。
- 验证：Volta shim 拦截 `node`/`npm`，`cd frontend && node -v` → **v20.18.1**（自动，无需手动 PATH）。
- dev 已在 Volta 管理下重启：`node=v20.18.1`，Webpack 编译成功，`:8000=200`。

### 启前端（新终端，最简）
```bash
cd frontend/packages/main
npm run dev        # Volta 自动切到 pin 的 Node 20 → http://localhost:8000
```
> 依赖与 `spark-flow/dist` 已就绪（第六节的 `npm install --ignore-scripts` + `build:flow` 已跑过）。冷启首次编译 ~17-37s。

### PATH 注意（若 Volta 没拦住 node）
Volta 安装目录（`C:\Program Files\Volta`）需在系统 PATH 里、且**排在 Node 24（`D:\Developer\JavaSoftWare\nodejs`）之前**，Volta shim 才能拦截。新终端一般已满足；若 `cd frontend && node -v` 仍显示 24，把 `C:\Program Files\Volta` 在 PATH 里上移到 nodejs 之前。

### 改动的源文件（追加）
- `frontend/package.json`：新增 `volta.node = 20.18.1`（项目级 Node 版本锁定）。
- 便携版 `D:\Developer\DeveloperInstall\node-v20.18.1-win-x64` 保留作离线备份，已不再使用。
