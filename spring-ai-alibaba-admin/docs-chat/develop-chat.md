# saa admin 二开

## 需求草稿
我有一个新需求：给 Prompt 管理加版本对比功能。首先查阅源码中是不是已经实现了，如果已经有了，那么直接结束。
GET /api/prompt/version/diff?promptKey=xxx&versionA=v3&versionB=v5
返回两个版本的 diff 结果。

读 docs-research/ 下的所有资产（特别是 04-api-list.md、05-data-model.md、CLAUDE.md）， 再扫一下代码里现有 Prompt 版本相关的实现（PromptVersionController、 PromptService、PromptVersionEntity），
按以下六个维度给我写需求文档草稿：
1. 业务目标（一句话）
2. 用户场景（典型使用场景 + 当前痛点）
3. 接口契约（方法、路径、入参、返回、错误码，对齐项目现有风格）
4. 边界场景清单（至少列 8 条 edge case，包括从现有代码反推的，每条标"待产品决策"或基于现有代码的预期行为）
5. 老项目约束（CLAUDE.md 禁区和历史包袱里和这个需求相关的，每条标 CLAUDE.md 来源）
6. 不在这次范围里的事（先列你能想到的候选，最终我来定）
输出 markdown，保存到 docs-research/requirements/prompt-version-diff.md。

## 定稿需求
我对 docs-research/requirements/prompt-version-diff.md 做了三个判断，
按下面的内容更新文档：
（1）业务目标修正：从"工程师 review 自己的修改"改成"团队多人协作下的
（2）Prompt 演进追溯"。diff 结果要返回 versionA/versionB 的元信息（创建时间、状态）不只是内容。

边界场景的产品决策（每条更新到表格里替换"待产品决策"）：
- E04（template 为 null）：null 视同空字符串
- E07（已软删除）：允许查 diff
- E10（LONGTEXT 超大）：本期不做大小限制
- E11（版本号大小写）：不在应用层 toLowerCase
- E12（高并发）：本期不加缓存

不在这次范围里的事最终决策：
- 砍掉：后端生成 unified diff、跨 promptKey 对比、N 版本对比、
  diff 缓存、versionDescription diff、权限控制
- 留到下期：diff 导出、一键比对上一版

整理为正式技术文档：
- 一句话总结放最前
- 接口契约用表格（方法 + 路径 + 入参 + 返回 + 错误码）
- 边界场景用表格（场景 + 预期行为 + 依据）
- 老项目约束单独一节，每条标 CLAUDE.md 来源
- 不在这次范围里的事单独一节

保存到原文件。








