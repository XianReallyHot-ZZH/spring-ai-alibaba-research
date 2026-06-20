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




# 项目运行护栏

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

## 启停脚本
基于 上一步 装好的中间件，生成三个脚本到 docs-research/scripts/ 下：
- deps-start.sh：一键启动所有依赖中间件
- deps-stop.sh：一键停止所有依赖中间件
- deps-status.sh：查看每个中间件的运行状态

考虑混合场景：有的用 brew services 管，有的是手动 jar，有的是 systemd。脚本要能处理这几种。
启动后等服务就绪再返回，不要"启动了但还没 ready"。
status 脚本要打印每个中间件的运行状态和端口监听情况。




