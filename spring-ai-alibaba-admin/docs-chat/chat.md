# 聊天

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


