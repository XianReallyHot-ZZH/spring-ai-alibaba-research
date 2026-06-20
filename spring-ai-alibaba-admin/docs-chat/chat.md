# 项目基本心智

## 架构图
读一下这个项目的 README 和顶层目录，给我画一张架构图。
前端、后端、数据库、中间件分层画，核心模块写一句话职责。
周边基础设施（日志、监控、配置）用一个方框概括就行，
不用展开。保存到 docs-research/architecture.svg。

## 模块图

看一下项目的 pom.xml，画一张内部模块依赖图。
只画项目自己的模块，外部库不画。有循环依赖用红色标出来。
保存到 docs-research/module-deps.svg。

## 依赖图

综合看 pom.xml、application.yml 和 README，帮我梳理这个项目。
对外依赖了什么，分成三类：关键 Java 依赖、中间件、外部 API。
画出来，每类用不同颜色。保存到 docs-research/external-deps.svg。

## 接口清单

扫一下这个项目里所有的 Controller，给我整理一份 REST 接口清单。
每个接口列出方法（GET/POST 等）、路径、一句话说明、主要入参、返回结构。
按模块分组。保存到 docs-research/04-api-list.md。

## 数据模型

看项目的 entity 类、DTO、数据库建表 SQL，给我梳理核心数据模型。
每个模型列出字段、类型、一句话说明。标出主键、外键、枚举值。
关键模型之间的关系画一张简单的 ER 图。保存到 docs-research/05-data-model.md 和 docs-research/06-data-model-er.svg。

## 校对

对照 docs-research/04-api-list.md 和 docs-research/05-data-model.md，看接口里提到的每个实体在数据模型里是不是都有定义。
有不一致的地方列出来。然后验证不一致的地方并修复。

## push

把项目 push 到 GitHub 仓库 https://github.com/XianReallyHot-ZZH/spring-ai-alibaba-research.git

## claude 文档

读 docs-research/ 下的所有资产,如果你不能读svg文件，那么根据svg文件的内容生成对应的mermaid代码保存到对应的md文件中，最终给我生成一份 CLAUDE.md 初稿。
精简：项目定位、核心架构、关键模块、关键约定、怎么跑，
外加两节空着的：禁区、历史包袱。
架构图、接口清单、数据模型的详细内容不要复制进来，
用链接指向 docs-research/ 就好。保存到项目根目录的 CLAUDE.md。

## skill 挖掘

### 分析项目重复流程
扫一下当前项目（包括 git log、CLAUDE.md、docs-research/、README、CONTRIBUTING、.github/），找出团队反复在做的操作流程。
判断标准是三特征：可复制、可参数化、可自动化。三个都满足才算值得做 SKILL 的候选。
把找到的候选列出来，每个写明：流程名、为什么是反复的、能参数化的部分是什么、起点和终点是什么。最后给我用一个表格总结。

### Top 3 推荐 SKILL
从上面的清单里挑 3 个最高优先级的，给我做成候选 SKILL。
每个候选写：name（英文）、description、预期 steps、allowed-tools。
优先级判断标准：频率高、痛点深、自动化收益大。用表格总结，包含类型和理由。

### CRUD SKILL
生成代码中 CRUD 的 SKILL。
注意按照标准格式和放在标准目录。
结果放到 .claude/skills/ 目录中。

### 技术文档自动更新的 SKILL
基于上面的候选，给我生成完整的技术文档自动更新 SKILL.md。要求：
- 名字 docs-auto-sync
- description 写清楚什么场景触发、产出是什么
- steps 清晰可执行
- allowed-tools 限制到最小
- 重要：只汇报不一致的地方，不要自动改文件，让人决定怎么处理
保存到 .claude/skills/docs-auto-sync/SKILL.md。



## 总结

我刚 clone 了 Spring AI Alibaba Admin。现在帮我完整摸清这个项目，
产出一整套 AI 协作基础设施。整个过程你自主推进，遇到问题自己修、
自己 review、自己决定下一步，不要每一步都问我。

请按以下顺序执行：

第一步：画三张全景图，保存到 docs-research/
- architecture.svg（分层架构图，核心模块写一句话职责）
- module-deps.svg（内部模块依赖，循环依赖红色标出）
- external-deps.svg（Java 依赖 + 中间件 + 外部 API 三类）

第二步：梳理接口和数据模型
- docs-research/api-list.md（REST 接口清单,按模块分组,对外/内部区分）
- docs-research/data-model.md 和 docs-research/data-model-er.svg（以 DB 层为准）

第三步：对照以上两份，列出不一致的地方并修正，直到自洽

第四步：基于 docs-research/ 下的所有产出，生成项目根目录的 CLAUDE.md
- 前五节（项目定位、核心架构、关键模块、关键约定、怎么跑）你自己基于 docs-research/ 生成
- 禁区和历史包袱两节留空，写"待补充"占位
- 整体控制在 300 行以内，不要把 docs-research/ 的内容复制进来

第五步：基于这个项目挖出最高优先级的一个 SKILL，生成完整的 SKILL.md
- 优先选"技术文档自动更新"（docs-auto-sync），解决代码改了但文档没跟上的问题
- 保存到 .claude/skills/docs-auto-sync/SKILL.md
- 只读不写（allowed-tools: Read, Grep）
- 步骤清晰，不自动修正，只报告

自主原则：
- 每一步跑完自己 review 输出质量，不合格自己重跑
- 图里有漏、有错、有不清晰的地方，主动补充或重画
- 遇到项目特有的细节（比如多模块、前后端分离），自己处理
- 所有步骤跑完后，生成一份 summary，列出每个产出文件、
  每份资产的主要内容概括、你认为还需要人工确认的地方

不要打断来问我。有判断不清的地方先做一个合理选择，
在最后的 summary 里标记出来。跑完再汇报。




# 项目启动运行与环境准备

## 依赖盘点
综合看 docs-research/02-external-deps.md、application*.yml、pom.xml、README，给我列一份这个项目运行需要的完整外部依赖清单。
每个依赖列出：名字、版本要求（精确到主版本）、默认端口、连接信息、初始化要求（建库、配 Nacos 命名空间等）。
保存到 docs-research/07-env-checklist.md。

## 依赖安装
读 docs-research/07-env-checklist.md，给我生成一份本地安装脚本，保存到 docs-research/scripts/install-deps.sh。
- 不同的操作系统用不同的安装工具来装中间件，brew（macOS），apt（Linux），windows你自己看情况选择
- 包含每个中间件的初始化（建库 SQL、Nacos 配置等）
- 初始化完成后，要验证是否真的初始化成功并启动成功
- 不会的依赖（比如某个 jar 包要下）写清楚下载链接和放哪
- 脚本要兼容不同操作系统，比如 macOS、Linux、Windows
- Windows系统安装时不要用C盘，使用D:\Developer\DeveloperInstall目录

生成完直接执行这个脚本。执行过程遵循自主修复原则:
- 任何一步失败，先看报错信息
- 自己判断原因（版本不对、源问题、权限问题、依赖缺失）
- 自己修（换源、换版本、加 sudo、装前置依赖）
- 修完重试，跑通为止
- 不要每个错误都问我

如果同一个错误连续修 3 次还不行，停下来汇报具体卡在哪。
其他情况一律自己解决。

最终输出一份 docs-research/scripts/install-log.md，记录每个中间件最终用了什么命令装上、过程中遇到什么问题、怎么修的。

## 中间件启停脚本
基于刚才装好的中间件，生成三个脚本到 docs-research/scripts/ 下：
- deps-start.sh：一键启动所有依赖中间件
- deps-stop.sh：一键停止所有依赖中间件
- deps-status.sh：查看每个中间件的运行状态

启动后等服务就绪再返回，不要"启动了但还没 ready"。
status 脚本要打印每个中间件的运行状态和端口监听情况。

## 应用编译启动
中间件已经起来了（用 docs-research/scripts/deps-status.sh 确认）。
现在帮我跑 mvn clean package + 启动应用，前端有的话也启动。
启动过程同样遵循自主修复原则（连续 3 次同一错误才停下来汇报）。

启动成功后告诉我应用监听的端口、管理界面地址。
失败和修复的过程记到 docs-research/scripts/startup-log.md。

## 接口冒烟
读 docs-research/api-list.md，挑 5 个最核心的接口（覆盖登录、Prompt、Dataset、Evaluator、Trace 几大模块），用 curl 跑一遍。
返回 200 算通过，返回错误的列出来。
最后输出一份 docs-research/08-smoke-test-result.md。

## 沉淀出设置指引
基于 docs-research/scripts/install-log.md 和 docs-research/scripts/startup-log.md，整理一份给新人看的 setup-guide.md，
包含：前置条件、装中间件步骤、启动命令、常见踩坑、验证清单。
保存到 docs-research/09-setup-guide.md。

## 沉淀出环境启动SKILL
基于这次环境搭建的全流程，给我生成一个通用的 env-bootstrap 的 SKILL，保存到 .claude/skills/env-bootstrap/SKILL.md。
触发场景：新接手项目、重置环境、定期验证环境健康。
步骤：依赖盘点 → 装中间件 → 启停脚本 → 编译启动 → 接口冒烟。
allowed-tools 限制到 Read, Bash, Write。



# 理清现有测试
摸核心链路 → 摸现有测试 → 跑一遍看实际状态 → 算出缺口清单

## 摸清核心链路
基于 docs-research/04-api-list.md、docs-research/05-data-model.md、CLAUDE.md，给我列出
这个项目最值得测的核心链路。要求：
- 总数不超过 8 条，宁少勿多
- 必须是"改造时容易出问题"的链路，不是所有链路
- 每条写：链路名、起点（哪个接口）、关键节点（哪些 service / DB 操作）、终点（什么状态算成功）
输出用表格总结。保存到 docs-research/10-critical-paths.md。

## 现有测试梳理
扫一下项目里所有的测试目录（src/test、tests/、e2e/ 等），统计现有测试情况。要求：
- 单元测试 / 集成测试 / E2E 各多少个文件
- 哪些 Controller 有对应的测试，哪些没有
- 哪些核心 Service 有测试，哪些没有
- 不要给覆盖率百分比，那是 JaCoCo 干的事
- 不要列出每个测试方法，只关注"哪些核心链路被覆盖"
对照 docs-research/10-critical-paths.md，标出每条核心链路当前的测试覆盖情况（有 / 部分 / 没有）。输出用表格总结。保存到 docs-research/11-test-status.md。

## 实际测试
跑一遍 mvn test（或项目的标准测试命令），统计真实结果：
- 通过 / 失败 / 跳过 各多少
- 失败的分类：代码 bug / 测试本身坏了 / 环境问题
- 跑总耗时多少
- 不要试图修复失败的测试，只汇报状态
最后给一个"测试健康度"的判断：绿（90% 通过）/ 黄（60-90%）/红（< 60%）。输出用表格总结。追加到 docs-research/11-test-status.md 的"实际运行结果"小节。

## 测试缺口清单
对照 docs-research/10-critical-paths.md（应该测什么）和 docs-research/11-test-status.md（现在测了什么），算出测试缺口。
严格遵守以下原则：
- 总数不超过 20 项，宁少勿多
- 只列在核心链路上的缺口，不在主链路上的不要列
- 每项标 P0（改造前必须有）/ P1（有了更好）
- 不要追求覆盖率指标，追求"关键路径有兜底"
- 每项写：场景描述、为什么必须、建议测试类型（集成 / 单元 / Characterization Test）
输出用表格总结。保存到 docs-research/12-test-gaps.md。


# 构建测试护栏

## 补测试计划
基于 docs-research/12-test-gaps.md，把 P0 缺口拆成多批，每批 1-3 个（最好 1 个），给我一份补测试计划。
每批写：批次号、测试类型（CharacterizationTest / 集成测试 / 单元测试）、覆盖的核心链路、预期工作量。
按"改造路径上的 Characterization > 核心链路集成 > 复杂逻辑单元"的顺序排批次。简单 CRUD 不进计划。
输出用表格总结。保存到 docs-research/13-test-plan.md。

## 一批一批补测试
按 docs-research/13-test-plan.md 的第 1 批，给项目补出对应的测试。
对 Characterization Test 类型：先跑一次现有代码记录实际行为，再把行为转成断言。不要凭"应该是什么"写断言，凭"实际是什么"写。
对集成测试类型：需要真实启动应用 + 数据库。用 SpringBootTest 的方式起完整 context 跑。
补完跑一遍 mvn test 确保都通过。
输出用表格总结每个测试覆盖的场景、预期结果、实际跑出来的状态。保存到 docs-research/14-test-plan-result.md。

按 docs-research/13-test-plan.md 的第 2 批补测试，
参考第 1 批已经跑通的测试风格，保持一致。
其他要求同前。输出补充到 docs-research/14-test-plan-result.md。
