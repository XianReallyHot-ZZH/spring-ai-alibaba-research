# 上游 Issue / PR 描述（中文版）— `Could not copy property 'outputSchema'` 回归

> 提交目标：spring-ai-alibaba（github.com/alibaba/spring-ai-alibaba）。
> 可作为 **Bug issue** 提交；文末「建议修复」已展开为可直接 `git apply` 的补丁，可顺手作为 PR body。
> 英文版见同目录 [17-upstream-issue-outputschema.md](./17-upstream-issue-outputschema.md)。

---

## 标题

`[Bug][admin] Prompt Playground / 评估器 / 实验 报错：Could not copy property 'outputSchema' from source to target（spring-ai 升级到 1.1.2 后的回归）`

## 概述

将 spring-ai 依赖升级到 **1.1.2** 后，在 Admin 控制台运行 Prompt（Playground）、评估器调试或实验时，**在发起任何模型请求之前**就抛出硬错误：

```
处理请求失败: Could not copy property 'outputSchema' from source to target
```

根因：`spring-ai 1.1.2` 新增了
`org.springframework.ai.model.tool.StructuredOutputChatOptions`（声明了
`outputSchema`）。Admin 模块里的三个 `*ObservationMetadataChatOptions` 辅助类，用
`org.springframework.beans.BeanUtils.copyProperties(...)` 把一个新建的厂商 options
对象**全量反射拷贝**进子类。这次拷贝在继承来的 `outputSchema` 属性上失败，并中止了
整个拷贝（Spring 把它包成 `FatalBeanException`）。

这是一次**回归**：由 `spring-ai 1.1.0 → 1.1.2` 升级引入——
`StructuredOutputChatOptions` 在 spring-ai 1.0.0 / 1.1.0 中**不存在**，1.1.2 才出现。

## 环境

| 项 | 值 |
|---|---|
| spring-ai-alibaba extensions | `1.1.2.2`（observation-extension、dashscope） |
| spring-ai | `1.1.2` |
| Spring Boot | `3.3.6` |
| JDK | `17` |
| 触发 provider | DeepSeek（已复现）；OpenAI 同样受影响；DashScope 大概率受影响（同代码模式） |

## 现象

- **出现位置**：Prompt Playground（`POST /api/prompt/run`）、评估器调试、实验运行——任何构建 provider `ChatClient` 的路径。
- **完整错误**（前缀是 `PromptRunServiceImpl.run()` 的 catch 文案，后缀是 Spring `FatalBeanException` 文案）：
  `处理请求失败: Could not copy property 'outputSchema' from source to target`
- **在发起网络调用之前就失败**：异常在**构建 chat options 时**抛出，因此即使模型 endpoint 不可达/Key 是假的也能复现——只要配置了一个启用的模型即可。

## 复现步骤

1. 启动 Admin 后端（任意 profile），至少配置一个模型（如 `model-config.yml` 里的 DeepSeek）。
2. 控制台 → **Prompt 工程 → Playground** → 选模型 → 任意模板 + 消息 → 运行。
3. 观察到上述报错；全程**没有**发起任何模型请求。

等价 API（登录后拿到 `$TOKEN`）：

```bash
curl -N -X POST http://localhost:8080/api/prompt/run \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"newSession":true,"promptKey":"<任意>","version":"1.0.0",
       "template":"reply to: {{q}}","variables":"{\"q\":\"hi\"}",
       "modelConfig":"{\"modelId\":<id>}","message":"hi"}'
# → Flux 返回一帧错误：处理请求失败: Could not copy property 'outputSchema' ...
```

## 根因

调用链：

```
PromptRunServiceImpl.run()
  → ChatClientFactoryDelegate.createChatClient(...)
    → DeepSeekChatClientFactory.buildChatOptions(...)
      → DeepSeekObservationMetadataChatOptions.fromDeepSeekOptions(chatOptions)
        → BeanUtils.copyProperties(fromOptions, options)   // 💥 在此抛出
```

受影响的三个文件（均在
`spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/.../admin/service/client/`）：

| 文件 | 行 | 模式 |
|---|---|---|
| `DeepSeekObservationMetadataChatOptions.java` | ~15 | `extends DeepSeekChatOptions implements ObservationMetadataAwareOptions` + `BeanUtils.copyProperties(from, this)` |
| `OpenAiObservationMetadataChatOptions.java` | ~18 | 同模式，基类为 `OpenAiChatOptions` |
| `DashScopeObservationMetadataChatOptions.java` | ~15 | 同模式，基类为 `DashScopeChatOptions` |

每个辅助类都这么写：

```java
public static DeepSeekObservationMetadataChatOptions fromDeepSeekOptions(DeepSeekChatOptions fromOptions) {
    DeepSeekObservationMetadataChatOptions options = new DeepSeekObservationMetadataChatOptions();
    BeanUtils.copyProperties(fromOptions, options);   // 反射式拷贝「所有」属性
    return options;
}
```

为什么偏偏是 `outputSchema`：

- `outputSchema` 声明在 `org.springframework.ai.model.tool.StructuredOutputChatOptions`（`extends ChatOptions`；签名干净的 `String getOutputSchema()` / `void setOutputSchema(String)`）。
- `DeepSeekChatOptions implements ToolCallingChatOptions`（后者 extends `StructuredOutputChatOptions`），但**并未**覆写 `outputSchema`。
- `BeanUtils.copyProperties` 遍历 target 的属性描述符并逐个调 setter；在子类上调用继承来的 `outputSchema` 访问器时抛异常，Spring 包成 `FatalBeanException("Could not copy property 'outputSchema' from source to target")`，整个拷贝中止。

为什么是回归——`StructuredOutputChatOptions` 在各 spring-ai 版本中的存在情况：

| spring-ai | `StructuredOutputChatOptions.class` |
|---|---|
| 1.0.0 | 不存在 |
| 1.1.0 | 不存在 |
| **1.1.2** | **存在** |
| 1.1.3 / 2.0.0 | 存在 |

全量拷贝是为 ≤1.1.0 的属性面写的；1.1.2 加了 `outputSchema` 后，拷贝没跟着更新。

## 影响范围

- 让受影响 provider（DeepSeek 已确认；OpenAI——`OpenAiChatOptions` 直接声明了 `outputSchema`——同样受影响；DashScope 同模式）的 Prompt Playground、评估器调试、实验运行全部不可用。
- 影响面大：这恰好在 Admin 平台的评估主轴（Prompt → 数据集 → 评估器 → 实验）上，是核心价值路径，不修无法用。

## 建议修复（可直接落地的补丁）

`ObservationMetadataAwareOptions` 这个抽象**本就在 `spring-ai-alibaba-observation-extension`（同仓库）里**。正确做法是在那里集中提供「把厂商 options 包一层 metadata」的能力，而不是让 Admin 用脆弱的反射拷贝各写一遍。

本补丁先在 Admin 模块内落地最小根治版（无需跨模块发版）：

1. 新增 `ObservationOptionsCopyUtils.copySafely(source, target)`：基于 Spring `BeanWrapper` 逐属性拷贝，**拷不动就跳过**（debug 级日志可加），且跳过 null 值——因此像 `outputSchema` 这类继承来、从未赋值的属性根本不会被尝试；未来 spring-ai 再加任何不可反射拷贝的属性也稳。
2. 三个 `*ObservationMetadataChatOptions` 改用它，删除三处 `BeanUtils.copyProperties`。
3. 新增回归测试 `ObservationMetadataChatOptionsTest`：对 DeepSeek / OpenAI 断言 `fromXxxOptions` 不抛异常、且 model 与参数存活、`observationMetadata` 可注入——下次再升 spring-ai、又冒出不可拷属性时，CI 当场红。

> 更进一步（可选 follow-up）：把 `copySafely` 上移到 `spring-ai-alibaba-observation-extension`，作为 `ObservationOptions.wrap(ChatOptions, Map)` 暴露，让外部用户也复用，彻底消除三处重复。

补丁如下（相对仓库根，可直接 `git apply`）：

```diff
diff --git a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DashScopeObservationMetadataChatOptions.java b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DashScopeObservationMetadataChatOptions.java
index 57b2fc7..608c269 100644
--- a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DashScopeObservationMetadataChatOptions.java
+++ b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DashScopeObservationMetadataChatOptions.java
@@ -2,7 +2,6 @@ package com.alibaba.cloud.ai.studio.admin.service.client;
 
 import com.alibaba.cloud.ai.dashscope.chat.DashScopeChatOptions;
 import com.alibaba.cloud.ai.observation.model.ObservationMetadataAwareOptions;
-import org.springframework.beans.BeanUtils;
 
 import java.util.Map;
 
@@ -12,7 +11,7 @@ public class DashScopeObservationMetadataChatOptions extends DashScopeChatOption
     
     public static DashScopeObservationMetadataChatOptions fromDashScopeOptions(DashScopeChatOptions fromOptions) {
         DashScopeObservationMetadataChatOptions options = new DashScopeObservationMetadataChatOptions();
-        BeanUtils.copyProperties(fromOptions, options);
+        ObservationOptionsCopyUtils.copySafely(fromOptions, options);
         return options;
     }
     
diff --git a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DeepSeekObservationMetadataChatOptions.java b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DeepSeekObservationMetadataChatOptions.java
index c10b204..9f8a2bf 100644
--- a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DeepSeekObservationMetadataChatOptions.java
+++ b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/DeepSeekObservationMetadataChatOptions.java
@@ -2,7 +2,6 @@ package com.alibaba.cloud.ai.studio.admin.service.client;
 
 import com.alibaba.cloud.ai.observation.model.ObservationMetadataAwareOptions;
 import org.springframework.ai.deepseek.DeepSeekChatOptions;
-import org.springframework.beans.BeanUtils;
 
 import java.util.Map;
 
@@ -12,7 +11,7 @@ public class DeepSeekObservationMetadataChatOptions extends DeepSeekChatOptions
     
     public static DeepSeekObservationMetadataChatOptions fromDeepSeekOptions(DeepSeekChatOptions fromOptions) {
         DeepSeekObservationMetadataChatOptions options = new DeepSeekObservationMetadataChatOptions();
-        BeanUtils.copyProperties(fromOptions, options);
+        ObservationOptionsCopyUtils.copySafely(fromOptions, options);
         return options;
     }
     
diff --git a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/ObservationOptionsCopyUtils.java b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/ObservationOptionsCopyUtils.java
new file mode 100644
index 0000000..94cb20f
--- /dev/null
+++ b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/ObservationOptionsCopyUtils.java
@@ -0,0 +1,74 @@
+/*
+ * Copyright 2025-2026 the original author or authors.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     https://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+package com.alibaba.cloud.ai.studio.admin.service.client;
+
+import java.beans.PropertyDescriptor;
+
+import org.springframework.beans.BeanWrapper;
+import org.springframework.beans.BeanWrapperImpl;
+
+/**
+ * Reflectively copies bean properties from source to target, skipping any
+ * property whose copy fails, instead of aborting the whole copy.
+ *
+ * <p>Used to clone a provider ChatOptions into a metadata-aware subclass (see
+ * the *ObservationMetadataChatOptions classes). Unlike
+ * {@link org.springframework.beans.BeanUtils#copyProperties}, it tolerates
+ * properties inherited from a spring-ai interface that are not safely invokable
+ * on the subclass - e.g. outputSchema, added to StructuredOutputChatOptions in
+ * spring-ai 1.1.2, which previously made the bulk copy throw
+ * FatalBeanException("Could not copy property 'outputSchema' from source to
+ * target").
+ *
+ * <p>Only the scalar model parameters plus the caller-supplied observation
+ * metadata need to survive; vendor structured-output / tooling options are out
+ * of scope and silently skipped.
+ */
+public final class ObservationOptionsCopyUtils {
+
+    private ObservationOptionsCopyUtils() {
+    }
+
+    /**
+     * Copy readable, non-null properties from source to target, skipping any
+     * property that cannot be reflectively copied.
+     */
+    public static void copySafely(Object source, Object target) {
+        if (source == null || target == null) {
+            return;
+        }
+        BeanWrapper src = new BeanWrapperImpl(source);
+        BeanWrapper dst = new BeanWrapperImpl(target);
+        for (PropertyDescriptor pd : dst.getPropertyDescriptors()) {
+            String name = pd.getName();
+            if (pd.getWriteMethod() == null || "class".equals(name)) {
+                continue;
+            }
+            try {
+                Object value = src.getPropertyValue(name);
+                if (value == null) {
+                    continue; // unset inherited properties (e.g. outputSchema) are irrelevant
+                }
+                dst.setPropertyValue(name, value);
+            }
+            catch (Exception ignored) {
+                // skip a property that cannot be reflectively copied
+            }
+        }
+    }
+
+}
diff --git a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/OpenAiObservationMetadataChatOptions.java b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/OpenAiObservationMetadataChatOptions.java
index 7fe1531..3535f7e 100644
--- a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/OpenAiObservationMetadataChatOptions.java
+++ b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/main/java/com/alibaba/cloud/ai/studio/admin/service/client/OpenAiObservationMetadataChatOptions.java
@@ -2,7 +2,6 @@ package com.alibaba.cloud.ai.studio.admin.service.client;
 
 import com.alibaba.cloud.ai.observation.model.ObservationMetadataAwareOptions;
 import org.springframework.ai.openai.OpenAiChatOptions;
-import org.springframework.beans.BeanUtils;
 
 import java.util.Map;
 
@@ -15,7 +14,7 @@ public class OpenAiObservationMetadataChatOptions extends OpenAiChatOptions impl
     
     public static OpenAiObservationMetadataChatOptions fromOpenAiOptions(OpenAiChatOptions fromOptions) {
         OpenAiObservationMetadataChatOptions options = new OpenAiObservationMetadataChatOptions();
-        BeanUtils.copyProperties(fromOptions, options);
+        ObservationOptionsCopyUtils.copySafely(fromOptions, options);
         return options;
     }
     
diff --git a/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/test/java/com/alibaba/cloud/ai/studio/admin/service/client/ObservationMetadataChatOptionsTest.java b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/test/java/com/alibaba/cloud/ai/studio/admin/service/client/ObservationMetadataChatOptionsTest.java
new file mode 100644
index 0000000..1f1c74d
--- /dev/null
+++ b/spring-ai-alibaba-admin/spring-ai-alibaba-admin-server-start/src/test/java/com/alibaba/cloud/ai/studio/admin/service/client/ObservationMetadataChatOptionsTest.java
@@ -0,0 +1,80 @@
+/*
+ * Copyright 2025-2026 the original author or authors.
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     https://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+
+package com.alibaba.cloud.ai.studio.admin.service.client;
+
+import java.util.Map;
+
+import org.junit.jupiter.api.Test;
+import org.springframework.ai.deepseek.DeepSeekChatOptions;
+import org.springframework.ai.openai.OpenAiChatOptions;
+
+import static org.assertj.core.api.Assertions.assertThat;
+import static org.assertj.core.api.Assertions.assertThatCode;
+
+/**
+ * Regression tests for the spring-ai 1.1.2 outputSchema copy failure: wrapping a
+ * provider ChatOptions into the metadata-aware subclass must not throw
+ * FatalBeanException and must preserve scalar model params.
+ */
+class ObservationMetadataChatOptionsTest {
+
+    @Test
+    void deepSeekOptionsCanBeWrappedWithoutThrowing() {
+        DeepSeekChatOptions base = DeepSeekChatOptions.builder()
+            .model("deepseek-chat")
+            .temperature(0.3)
+            .maxTokens(1024)
+            .build();
+
+        DeepSeekObservationMetadataChatOptions wrapped =
+                DeepSeekObservationMetadataChatOptions.fromDeepSeekOptions(base);
+
+        assertThatCode(() -> wrapped.copy()).doesNotThrowAnyException();
+        assertThat(wrapped.getModel()).isEqualTo("deepseek-chat");
+        assertThat(wrapped.getTemperature()).isEqualTo(0.3);
+        assertThat(wrapped.getMaxTokens()).isEqualTo(1024);
+    }
+
+    @Test
+    void deepSeekWrapPreservesObservationMetadata() {
+        DeepSeekChatOptions base = DeepSeekChatOptions.builder().model("deepseek-chat").build();
+
+        DeepSeekObservationMetadataChatOptions wrapped =
+                DeepSeekObservationMetadataChatOptions.fromDeepSeekOptions(base);
+        wrapped.setObservationMetadata(Map.of("studioSource", "test"));
+
+        assertThat(wrapped.getObservationMetadata()).containsEntry("studioSource", "test");
+    }
+
+    @Test
+    void openAiOptionsCanBeWrappedWithoutThrowing() {
+        OpenAiChatOptions base = OpenAiChatOptions.builder()
+            .model("gpt-4o")
+            .temperature(0.5)
+            .build();
+
+        OpenAiObservationMetadataChatOptions wrapped =
+                OpenAiObservationMetadataChatOptions.fromOpenAiOptions(base);
+
+        assertThatCode(() -> wrapped.copy()).doesNotThrowAnyException();
+        assertThat(wrapped.getModel()).isEqualTo("gpt-4o");
+    }
+
+    // Note: add an equivalent case for DashScopeObservationMetadataChatOptions
+    // once its builder API is confirmed; the same fromXxxOptions path is exercised.
+
+}
```

## 临时 workaround（供现在被卡住的用户）

在三个 `fromXxxOptions(...)` 里用 3 参重载排除 `outputSchema`：

```java
BeanUtils.copyProperties(fromOptions, options, "outputSchema");
```

能立刻解封，但这是**创可贴**（写死了 spring-ai 内部属性名，下个不可拷属性还会再炸），不应作为长期修复。

## 参考

- `org.springframework.ai.model.tool.StructuredOutputChatOptions`（spring-ai 1.1.2）
- `org.springframework.beans.BeanUtils#copyProperties(Object, Object)` → 抛 `FatalBeanException("Could not copy property '<p>' from source to target")`
- `com.alibaba.cloud.ai.observation.model.ObservationMetadataAwareOptions`（spring-ai-alibaba-observation-extension）
