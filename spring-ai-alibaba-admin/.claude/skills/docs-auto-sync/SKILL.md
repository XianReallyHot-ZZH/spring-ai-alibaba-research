---
name: docs-auto-sync
description: Reconcile the project's technical docs in docs-research/ against the current code and report drift — strictly READ-ONLY, never modifies any file. Use after changes to backend controllers/endpoints, entities/DOs, database DDL (agentscope/admin schema), pom.xml dependencies or modules, or top-level project structure, to check whether 01-architecture / 02-module-deps / 03-external-deps / 04-api-list / 05-data-model / 06-data-model-er have gone stale. Produces a grouped inconsistency report (stale-in-doc / missing-from-doc / changed) with suggested actions; a human decides what to update. Does NOT edit, write, or auto-apply any change.
allowed-tools: Read, Glob, Grep
---

# Docs Auto-Sync (Drift Report Only)

Compare the enumerated facts in `docs-research/` against the current code and **report only the mismatches**. Never modify files — this skill has no write tools by design. The human decides how to handle each finding.

## Hard rules

- **Read-only.** Do not edit, create, or delete any file. Do not run commands that write. If a fix seems obvious, still only *suggest* it in the report.
- **Report inconsistencies only.** Do not enumerate things that already match — that is noise. Only call out stale-in-doc, missing-from-doc, and changed items.
- **SVGs are not readable** (rendered Mermaid, very large). Work from the `.md` companions (`01/02/03/06-*.md`) and the plain-markdown docs (`04-api-list.md`, `05-data-model.md`).
- Focus on **structural drift** (added / removed / renamed). Skip cosmetic wording diffs.

## Step 0 — Scope

Default: reconcile all six assets. If the user points at a changed area (e.g. "I added a controller"), focus there but still note cross-cutting impact (a new resource usually affects both 04 and 05/06).

## Step 1 — API list (`04-api-list.md`) vs controllers

- `Glob` all controllers: `**/*Controller.java` excluding `**/target/**`. Record each class + its package dir (maps to the doc's module grouping: `controller`→openapi, `admin/controller`→admin, `admin/builder/controller`→builder, `admin/builder/generator/controller`→generator).
- For each controller, `Grep` the class-level `@RequestMapping` (base path) and method mappings (`@GetMapping/@PostMapping/@PutMapping/@DeleteMapping/@PatchMapping/@RequestMapping`).
- Compare the controller set and endpoint set against `04-api-list.md` (Read it; extract controller headings + path rows).
- Report:
  - **missing-from-doc**: controller / endpoint in code but not in 04.
  - **stale-in-doc**: controller / endpoint in 04 but no longer in code (renamed/removed).
  - **changed**: base path or HTTP method differs.

## Step 2 — Data model (`05-data-model.md`, `06-data-model-er.md`) vs DDL + entities

- `Read` the two DDL files: `docker/middleware/init/mysql/agentscope-schema.sql` and `.../admin-schema.sql`. `Grep` `CREATE TABLE` to get the table set per DB.
- `Glob` entities: `**/*Entity.java` and `**/*DO.java` (exclude `**/target/**`). These map to tables per 05's "Java 实体映射" table.
- Compare against 05's documented table list (27 tables) + the Java-entity↔table mapping.
- Report:
  - **missing-from-doc**: new table in DDL, or new `*Entity`/`*DO`, not in 05/06.
  - **stale-in-doc**: table/entity in 05/06 but dropped from DDL/code.
  - **changed**: a column/key/enum that 05 documents no longer matches the DDL (spot-check the touched tables; don't diff all columns blindly).

## Step 3 — Module deps (`02-module-deps.md`) vs pom

- `Read` `pom.xml` (modules) + each `spring-ai-alibaba-admin-server-*/pom.xml`.
- Compare: the 4-module set, and the internal compile-dependency edges (start→{openapi,core,runtime}, openapi→core, core→runtime) documented in 02.
- Report only if the module set or an internal dependency edge was added/removed/changed (a cycle appearing is high severity).

## Step 4 — External deps (`03-external-deps.md`) vs pom + config

- `Grep` the poms for new notable dependencies; `Read`/`Grep` `spring-ai-alibaba-admin-server-start/src/main/resources/application.yml` (+ profiles) for new middleware endpoints or external API config.
- Compare against the three categories in 03 (key Java deps / middleware / external APIs).
- Report only **significant** new/removed items (a new framework, DB, message broker, or model provider). Ignore version bumps of already-listed libs.

## Step 5 — Architecture (`01-architecture.md`) vs top-level structure

- `Glob` top-level dirs of `spring-ai-alibaba-admin/`. Compare against the layers/modules named in 01.
- Report only if a new top-level module/layer exists that 01 doesn't mention (or one it names is gone).

## Step 6 — Emit the drift report

Output a single report, grouped by asset. Use this shape per item:

```
[04-api-list] missing-from-doc — controller FeedbackController (admin/builder/controller) with 5 endpoints not listed.
  evidence: spring-ai-alibaba-admin-server-start/.../admin/builder/controller/FeedbackController.java
  suggested action: add a "### FeedbackController" section under "## 3. builder 模块" with its endpoints.
```

- Tag each item: `missing-from-doc` / `stale-in-doc` / `changed`, and a severity (🔴 structural add/remove/rename · 🟡 detail drift).
- End with one explicit line: **"No files were modified. Review and decide which updates to apply."**
- If nothing drifted: say **"docs-research/ is in sync with the code (no inconsistencies found)."** and stop.
