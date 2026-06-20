# CI 现状（15-ci-status）

> 扫描范围：monorepo 根 `.github/workflows/`、`spring-ai-alibaba-admin/.github/`、及其它 CI 文件（GitLab/Jenkins/Circle/Azure）。
> 托管平台：**GitHub**（upstream `alibaba/spring-ai-alibaba`；你的 fork `XianReallyHot-ZZH/spring-ai-alibaba-research`）。
> **核心结论：monorepo 有 10 个 GitHub Actions workflow，但 admin 模块【零 CI 覆盖】——既不在 monorepo 的 Maven reactor 里、admin/ 也没有自己的 workflow，且主构建 workflow 还被 `if: repo=='alibaba/...'` 锁死只在 upstream 跑（fork 全跳过）。**

---

## 一、CI 文件清单

| 类型 | 存在？ | 位置 |
|---|---|---|
| GitHub Actions | ✅ 10 个 | monorepo `.github/workflows/*.yml` |
| GitLab CI / Jenkinsfile / Circle / Azure / Bitbucket | ❌ 无 | — |
| admin 模块自有 CI（`spring-ai-alibaba-admin/.github/`） | ❌ 无 | — |

## 二、各 workflow 汇总（触发 / 做什么 / 跑测试? / 覆盖 admin?）

| Workflow | 触发(on) | 主要动作 | 跑测试? | 覆盖 admin? |
|---|---|---|:--:|:--:|
| **build-and-test** 🛠️ | push/PR → main（忽略 `**.md`） | make format-check / checkstyle-check / **test** / build | ✅ make test | ❌ |
| linter 👀 | push | make lint（codespell/yaml-lint 等） | ❌ | ⚠️ 仅文件级扫描 |
| license-check 🗒️ | push | make licenses-check（许可头） | ❌ | ⚠️ 仅文件级 |
| secret-check 🗝️ | push | make secrets-check | ❌ | ⚠️ 仅扫描 |
| lint-pr-title 🤔 | pull_request_target | PR 标题 conventional-commit 校验 | ❌ | —（PR 级） |
| greeting-guideline-pr | pull_request | 首次贡献者问候 | ❌ | — |
| pull-request-robot 🚀 | pull_request_target | PR 机器人（review/label） | ❌ | — |
| issue-and-pr 🫡 | issue_comment | issue/PR 斜杠命令 | ❌ | — |
| invalid-issue-check | schedule（定时） | 关闭无效 issue | ❌ | — |
| remove-stale-pr | schedule（定时） | 标记/关闭陈旧 PR | ❌ | — |

## 三、为什么 admin 模块【零 CI 覆盖】（三层原因）

1. **admin 不在 monorepo 的 Maven reactor**：monorepo 根 `pom.xml` 的 `<modules>` 只有 bom / graph-core / agent-framework / studio / sandbox / starters——**不含 `spring-ai-alibaba-admin`**。所以 `build-and-test` 里的 `make test`/`make build` 只构建上述模块，**根本不编译/测试 admin**。
2. **admin/ 没有自己的 `.github/workflows`**：admin 作为子目录，没有独立 CI。
3. **主构建 workflow 被 upstream 锁定**：`build-and-test.yml` 的 job 带 `if: (github.repository == 'alibaba/spring-ai-alibaba')`——**只在 alibaba upstream 仓库执行，任何 fork（含你的 research fork）上该 job 直接跳过**。

> 结果：改 admin 代码 → 不触发任何构建/测试 CI（无论 upstream 还是 fork）。当前唯一的"自动化护栏"是 [`docs-research/scripts/`](./scripts/) 下的本地脚本（install/start/deps-status/smoke）+ 手跑 `mvn test`。

## 四、建议：给 admin 加专用 GitHub Actions

托管在 GitHub → 用 **GitHub Actions** 最自然。admin 是自包含 Maven 项目（独立 pom、无 monorepo parent），加一个专属 workflow 即可，不依赖 monorepo reactor。

**最小可用版（先覆盖编译 + 单元测试，无需中间件）**：
```yaml
# .github/workflows/admin-build-test.yml（放在 admin/ 或 monorepo .github/，按 admin/** 路径触发）
name: admin build & test
on:
  push:
    paths: [ 'spring-ai-alibaba-admin/**' ]   # 若 workflow 放 admin/ 内则用 '**'
  pull_request:
    paths: [ 'spring-ai-alibaba-admin/**' ]
jobs:
  build-test:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17', cache: maven }
      - run: mvn -B -pl spring-ai-alibaba-admin test        # 跑 admin 4 模块 + 测试
```
- **能跑的**：纯单元测试（experiment 状态机 Characterization = Mockito、crypto/RAG 工具等）+ 编译护栏——CI 无中间件时，依赖 ES/MySQL 的测试靠 `Assumptions.assumeTrue` 自动跳过（不 fail）。
- **不要 `if: repo==alibaba` 限制**——让 fork 也能跑。

**进阶（覆盖集成测试）**：加 service containers（MySQL 8 + ES 9 + Redis）+ 跑 init SQL，让 `AuthIntegrationTest` 等也能在 CI 跑通；模型相关测试仍需 key（用 GitHub Secrets 注入，绝不写进仓库）。

## 五、一句话总结

| 项 | 现状 |
|---|---|
| 托管平台 | GitHub |
| 有 CI？ | monorepo 有（10 个 Actions），**但 admin 模块零覆盖** |
| admin 构建测试 | ❌ 不在任何 CI 里（不在 reactor + 无自有 workflow + upstream 锁定） |
| 建议 | 给 admin 加专用 GitHub Actions：先 `mvn test`（单测+编译），再按需加 service containers 跑集成测试 |
