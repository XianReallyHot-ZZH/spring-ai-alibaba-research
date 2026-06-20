# Upstream Issue / PR Description — `Could not copy property 'outputSchema'` regression

> Ready-to-submit text for spring-ai-alibaba (github.com/alibaba/spring-ai-alibaba).
> Submit as a **Bug issue** (no code change yet) — the *Suggested fix* section is detailed enough to become a PR body later.
> Language: English (the repo also accepts Chinese).

---

## Title

`[Bug][admin] Prompt Playground / Evaluator / Experiment fail: Could not copy property 'outputSchema' from source to target (regression after spring-ai 1.1.2 upgrade)`

## Summary

After the spring-ai dependency was bumped to **1.1.2**, running a Prompt in the
Admin console (Playground), an Evaluator debug, or an Experiment throws a
hard error before any model call is made:

```
处理请求失败: Could not copy property 'outputSchema' from source to target
```

Root cause: `spring-ai 1.1.2` introduced
`org.springframework.ai.model.tool.StructuredOutputChatOptions` (which declares
`outputSchema`). The Admin module's three `*ObservationMetadataChatOptions`
helpers copy a freshly-built provider options object into a subclass via
`org.springframework.beans.BeanUtils.copyProperties(...)`. That bulk reflective
copy now fails on the inherited `outputSchema` property and aborts the whole copy
(Spring wraps it as `FatalBeanException`).

This is a **regression** introduced by the `spring-ai 1.1.0 → 1.1.2` bump:
`StructuredOutputChatOptions` does not exist in spring-ai 1.0.0 / 1.1.0 and first
appears in 1.1.2.

## Environment

| Item | Value |
|---|---|
| spring-ai-alibaba extensions | `1.1.2.2` (observation-extension, dashscope) |
| spring-ai | `1.1.2` |
| Spring Boot | `3.3.6` |
| JDK | `17` |
| Triggering provider | DeepSeek (reproduced); OpenAI also affected; DashScope likely affected (same code pattern) |

## Symptom

- **Where it surfaces**: Prompt Playground (`POST /api/prompt/run`), Evaluator
  debug, Experiment run — anything that builds a provider `ChatClient`.
- **Exact error** (returned to the frontend / SSE consumer):
  `处理请求失败: Could not copy property 'outputSchema' from source to target`
  (the prefix is `PromptRunServiceImpl.run()`'s catch-block message; the suffix
  is the Spring `FatalBeanException` message).
- **Fails before any network call**: the exception is thrown while *building*
  the chat options, so it reproduces even with an unreachable / dummy model
  endpoint — you only need one enabled model configured.

## Reproduce

1. Build & start the Admin backend (any profile) with at least one model
   configured (e.g. a DeepSeek model in `model-config.yml`).
2. In the console, open **Prompt 工程 → Playground**, pick the model, enter any
   template + message, and run.
3. Observe the error above. No model request is ever sent.

Equivalent API (after login → `$TOKEN`):

```bash
curl -N -X POST http://localhost:8080/api/prompt/run \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"newSession":true,"promptKey":"<any>","version":"1.0.0",
       "template":"reply to: {{q}}","variables":"{\"q\":\"hi\"}",
       "modelConfig":"{\"modelId\":<id>}",
       "message":"hi"}'
# → Flux returns an error frame: 处理请求失败: Could not copy property 'outputSchema' ...
```

## Root cause

Call path:

```
PromptRunServiceImpl.run()
  → ChatClientFactoryDelegate.createChatClient(...)
    → DeepSeekChatClientFactory.buildChatOptions(...)
      → DeepSeekObservationMetadataChatOptions.fromDeepSeekOptions(chatOptions)
        → BeanUtils.copyProperties(fromOptions, options)   // 💥 throws here
```

The three affected files (all in
`spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/.../admin/service/client/`):

| File | Line | Pattern |
|---|---|---|
| `DeepSeekObservationMetadataChatOptions.java` | ~15 | `extends DeepSeekChatOptions implements ObservationMetadataAwareOptions` + `BeanUtils.copyProperties(from, this)` |
| `OpenAiObservationMetadataChatOptions.java`   | ~18 | same pattern with `OpenAiChatOptions` |
| `DashScopeObservationMetadataChatOptions.java`| ~15 | same pattern with `DashScopeChatOptions` |

Each helper does:

```java
public static DeepSeekObservationMetadataChatOptions fromDeepSeekOptions(DeepSeekChatOptions fromOptions) {
    DeepSeekObservationMetadataChatOptions options = new DeepSeekObservationMetadataChatOptions();
    BeanUtils.copyProperties(fromOptions, options);   // bulk reflective copy of EVERY property
    return options;
}
```

Why it breaks on `outputSchema` specifically:

- `outputSchema` is declared on
  `org.springframework.ai.model.tool.StructuredOutputChatOptions`
  (`extends ChatOptions`; clean `String getOutputSchema()` / `void setOutputSchema(String)`).
- `DeepSeekChatOptions implements ToolCallingChatOptions` (which extends
  `StructuredOutputChatOptions`) but does **not** override `outputSchema`.
- `BeanUtils.copyProperties` iterates the *target*'s property descriptors and
  invokes each setter; invoking the inherited `outputSchema` accessor on the
  subclass throws, and Spring wraps it as
  `FatalBeanException("Could not copy property 'outputSchema' from source to target")`,
  aborting the whole copy.

Why it's a regression — `StructuredOutputChatOptions` presence across spring-ai versions:

| spring-ai | `StructuredOutputChatOptions.class` |
|---|---|
| 1.0.0 | absent |
| 1.1.0 | absent |
| **1.1.2** | **present** |
| 1.1.3 | present |
| 2.0.0 | present |

The bulk-copy was written against the ≤1.1.0 property surface; the 1.1.2 bump
added `outputSchema` and the copy was not updated.

## Impact

- Breaks Prompt Playground, Evaluator debug, and Experiment execution for
  affected providers (DeepSeek confirmed; OpenAI — `OpenAiChatOptions` declares
  `outputSchema` directly — also affected; DashScope shares the pattern).
- High blast radius: it's on the main "evaluation" axis of the Admin platform
  (Prompt → Dataset → Evaluator → Experiment), so the core value path is
  unusable until fixed.

## Suggested fix

The `ObservationMetadataAwareOptions` abstraction already lives in
`spring-ai-alibaba-observation-extension`, i.e. in this same repo. The right fix
is to centralise the "wrap a provider options object with observation metadata"
operation there, instead of letting Admin re-implement a fragile reflective copy
three times.

1. **In `spring-ai-alibaba-observation-extension`**: provide a single, robust
   wrap utility, e.g.

   ```java
   // copies a provider ChatOptions into a metadata-aware wrapper,
   // skipping any property whose reflective copy fails (debug-logged),
   // so it never breaks on future spring-ai property additions.
   ObservationOptions.wrap(ChatOptions base, Map<String,String> metadata);
   ```

   …or an `AbstractObservationMetadataChatOptions` base class implementing that
   safe copy once. Key point: the copy must be resilient (skip-on-failure),
   **not** hardcode a property name — the contract is "carry the scalar model
   params + my metadata; vendor structured-output/tooling options are
   out of scope and may not be reflectively copyable."

2. **In Admin**: have the three `*ObservationMetadataChatOptions` helpers (or the
   three `*ChatClientFactory.buildChatOptions` methods) use the shared utility;
   delete the duplicated `BeanUtils.copyProperties` calls.

3. **Regression test**: for each provider, assert
   `build options → wrap` does not throw and that `model` +
   `observationMetadata` survive. This makes the **next** spring-ai bump that
   adds a non-copyable property fail in CI instead of in production.

   *Minimal alternative (if touching observation-extension is out of scope):*
   in the three Admin factories, replace the bulk copy with an explicit-field
   copy of only the parameters the project actually supports
   (`options.setModel(from.getModel())`, …), removing `BeanUtils.copyProperties`
   entirely. Decoupled and correct, but leaves the three sites duplicated.

## Workaround (for users blocked now)

Exclude `outputSchema` from the copy via the 3-arg overload, in all three
`*ObservationMetadataChatOptions.fromXxxOptions(...)`:

```java
BeanUtils.copyProperties(fromOptions, options, "outputSchema");
```

This unblocks immediately but is a **band-aid** (hardcodes an internal property
name and will break again on the next non-copyable property); it should not be
the long-term fix.

## References

- `org.springframework.ai.model.tool.StructuredOutputChatOptions` (spring-ai 1.1.2)
- `org.springframework.beans.BeanUtils#copyProperties(Object, Object)` → throws
  `FatalBeanException("Could not copy property '<p>' from source to target")`
- `com.alibaba.cloud.ai.observation.model.ObservationMetadataAwareOptions`
  (spring-ai-alibaba-observation-extension)
