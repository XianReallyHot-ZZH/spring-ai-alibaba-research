---
name: scaffold-crud-resource
description: Scaffold a new standard CRUD resource (entity/DO + mapper + service(+impl) + controller + request/response DTOs + DDL + basic test) in spring-ai-alibaba-admin, end-to-end and verified. Use whenever adding a new persisted domain resource that needs create / get / list-with-paging / update / delete operations. Generates code matching either convention family — builder (@TableName *Entity, /console/v1, Result<PagingList<T>>) or admin (*DO, /api, Result<PageResult<T>>). Do NOT use for streaming endpoints (SseEmitter/Flux), OAuth callbacks, file upload/download, workflow debug endpoints, or generator controllers that implement an XxxAPI interface — those follow different patterns.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Scaffold CRUD Resource

Scaffold one new CRUD resource across all layers and verify it compiles + passes format/checkstyle. **Always mirror a real sibling file** — never invent conventions, annotations, or column styles.

## When to use / NOT to use

- **Use**: a new persisted resource with standard CRUD (create / get-by-id / list-paged / update / delete), optionally + enable/disable or batch.
- **Do NOT use** for: streaming (`SseEmitter`/`Flux`), OAuth callbacks, file upload/download, workflow debug endpoints, or `generator` controllers (`implements XxxAPI`, default methods). Tell the user these are out of scope and need a different approach.

## Step 0 — Gather inputs

Ask the user (or infer from the request) for:

- **Resource name** — PascalCase (e.g. `RuleSet`) + display/Chinese name.
- **Fields** — each as `name : javaType : sqlType : flags`, where flags ∈ `{PK, UK, bizKey, enum:v1|v2, nullable}`.
- **Family** — `builder` or `admin` (see table below; if unclear, ask which area/module the resource belongs to).
- **Table name** — snake_case (e.g. `rule_set`).
- **Ops** — default `{create, get, list-paged, update, delete}`; note any to omit, and optional `{enable/disable, batch-delete}`.
- **Biz key field** — if the family uses one (builder families use a `xxx_id`, e.g. `rule_set_id`).

Do not proceed until the family is decided — it determines packages, wrappers, audit columns, and path prefix.

## Step 1 — Pick the convention family

| Aspect | builder | admin |
|---|---|---|
| Entity class | `@TableName *Entity` (MyBatis-Plus) | plain `*DO` |
| Entity → module / package | `admin-server-core` → `core/base/entity` | `admin-server-start` → `admin/entity` |
| Mapper | `core/base/mapper` — `interface XxxMapper extends BaseMapper<XxxEntity>` (no XML) | `admin/mapper` + `resources/mapper/XxxMapper.xml` (`mapper-locations=classpath:mapper/*.xml`, `type-aliases-package=…admin.entity`) |
| Service(+Impl) | `core/base/service`(+`/impl`) | `admin/service`(+`/impl`) |
| Controller | `admin-server-start` → `admin/builder/controller` | `admin-server-start` → `admin/controller` |
| Path prefix | `/console/v1/<resource>s` | `/api/<resource>` |
| Response wrap | `Result<T>`, paging `Result<PagingList<T>>` | `Result<T>`, paging `Result<PageResult<T>>` |
| List-query param | `@ApiModelAttribute BaseQuery` / `<Xxx>Query` | `<Xxx>ListRequest` / `<Xxx>QueryRequest` (query bean) |
| Audit columns | `gmt_create`, `gmt_modified`, `creator`, `modifier` | `create_time`, `update_time` |
| Logical delete | `status` (0 deleted / 1 normal) | `deleted` (0 / 1) |

## Step 2 — Read exemplars and mirror them

Before writing anything, read real siblings and copy conventions verbatim (annotations, key style, audit cols, Lombok, `Result<…>` usage, mapping style, **Apache-2.0 license header**):

- builder → `spring-ai-alibaba-admin-server-core/src/main/java/com/alibaba/cloud/ai/studio/core/base/entity/ToolEntity.java` + `spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/builder/controller/ToolController.java`
- admin → `spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/entity/DatasetDO.java` + `…/admin/controller/DatasetController.java`

Also read the matching mapper + service(+impl) of the exemplar so package/imports line up.

## Step 3 — Generate files (into the packages from Step 1)

1. **Entity / DO** — fields + audit cols + logical-delete col + correct key annotations (`@TableName`/`@TableId` for builder; plain for admin). License header on every `.java`.
2. **Mapper** — builder: `BaseMapper`-extending interface; admin: mapper interface + `XxxMapper.xml` with the CRUD statements.
3. **Service + ServiceImpl** — methods for exactly the requested ops, delegating to the mapper.
4. **DTOs** — `<Xxx>CreateRequest`, `<Xxx>UpdateRequest`, `<Xxx>QueryRequest` (with paging fields); a response VO if the raw entity shouldn't leak.
5. **Controller** — `@RestController` + class-level `@RequestMapping(<prefix>)`; only the requested ops; paging returns the family's paged result type; use the family's query-param annotation.
6. **DDL** — append `CREATE TABLE` to `docker/middleware/init/mysql/<agentscope|admin>-schema.sql` (builder→`agentscope-schema.sql`, admin→`admin-schema.sql`): column `COMMENT`s, `PRIMARY KEY`, biz-key `UNIQUE KEY` + index, audit cols, `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`, `AUTO_INCREMENT=10000` (match existing tables).
7. **Test** (recommended) — a basic `*Test` mirroring the exemplar's sibling test.

## Step 4 — Self-check (must pass; do not skip)

From the **admin module root** (`spring-ai-alibaba-admin/`):

```bash
mvn spotless:apply                                                    # format + remove unused imports
mvn checkstyle:check                                                  # local checkstyle
mvn -pl :spring-ai-alibaba-admin-server-start -am clean package -DskipTests   # compile + package (controllers/services live here)
```

If a builder entity was added, also: `mvn -pl :spring-ai-alibaba-admin-server-core -am clean package -DskipTests`.
Iterate until all three are green. **Do not declare done while anything fails to compile or format.**

## Step 5 — Report

Tell the user, grouped by module:
- files created (entity, mapper, service(+impl), DTOs, controller, test) + the DDL file/table appended;
- the new endpoint paths (full, with prefix) and which ops were generated/omitted;
- the table name + which schema file;
- a one-line reminder that streaming/OAuth/upload/workflow-debug siblings are out of scope for this skill.
