/*
 * Copyright 2025-2026 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.alibaba.cloud.ai.studio.core.observability;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Characterization test —— 锁定 ES ingest pipeline {@code parsing_loongsuite_traces}
 * 对 OTLP trace 文档的【实际】解析行为（凭一次实测记录，再固化成断言；不写"应该是什么"）。
 *
 * <p>被测对象不是 Java 代码，而是 {@code docker/middleware/init/elasticsearch/init-indices.sh}
 * 里定义并装入 ES 的 pipeline + {@code loongsuite_traces} 索引映射。改造 pipeline/mapping 时
 * 这些行为会静默变化，故先用 Characterization 锁住现状。
 *
 * <p>依赖：本地 ES 运行 + pipeline 已装入（{@code deps-start.sh}）。无 ES 时用
 * {@link Assumptions#assumeTrue} 跳过，不致 {@code mvn test} 失败。
 */
class LoongsuiteTracesPipelineCharacterizationTest {

	private static final String ES_URL = System.getProperty("es.url", "http://localhost:9200");
	private static final String PIPELINE = "parsing_loongsuite_traces";
	private static final ObjectMapper M = new ObjectMapper();

	/** 用 ES 的 _simulate 跑样例 trace 文档，断言 pipeline 实际产出（2026-06-20 实测）。 */
	@Test
	void characterize_pipeline_parses_sample_trace_doc() throws Exception {
		Assumptions.assumeTrue(pipelineReady(),
				"跳过：本地 ES 未运行或 pipeline 未装入（先跑 deps-start.sh）");

		String body = buildSimulateBody();
		HttpResponse<String> resp = HttpClient.newHttpClient().send(
				HttpRequest.newBuilder(URI.create(ES_URL + "/_ingest/pipeline/" + PIPELINE + "/_simulate"))
						.header("Content-Type", "application/json")
						.POST(HttpRequest.BodyPublishers.ofString(body)).build(),
				HttpResponse.BodyHandlers.ofString());
		assertEquals(200, resp.statusCode(), "simulate 应返回 200");

		JsonNode src = M.readTree(resp.body()).path("docs").get(0).path("doc").path("_source");

		// 1) contents 被 rename 为 metadata；span 字段保留，attribute/resource/links/logs 已被 remove
		JsonNode meta = src.path("metadata");
		assertEquals("trace-1", meta.path("traceID").asText());
		assertEquals("chat", meta.path("name").asText());
		assertEquals("agent-svc", meta.path("service").asText());
		assertEquals(100, meta.path("duration").asInt());
		assertEquals("otel", meta.path("otlp").path("name").asText());
		assertTrue(meta.path("attribute").isMissingNode(), "metadata.attribute 应被移除");
		assertTrue(meta.path("resource").isMissingNode(), "metadata.resource 应被移除");
		assertTrue(meta.path("links").isMissingNode(), "metadata.links 应被移除");
		assertTrue(meta.path("logs").isMissingNode(), "metadata.logs 应被移除");
		assertTrue(src.path("contents").isMissingNode(), "contents 应被 rename 走（→metadata）");

		// 2) contents.attribute(JSON 串) → attributes 扁平对象；token 值【保持 String】（json processor 不转 long）
		JsonNode attrs = src.path("attributes");
		assertEquals("10", attrs.path("gen_ai.usage.input_tokens").asText());
		assertEquals("20", attrs.path("gen_ai.usage.output_tokens").asText());
		assertEquals("v", attrs.path("custom.key").asText());

		// 3) contents.resource → resources 扁平
		assertEquals("agent-svc", src.path("resources").path("service.name").asText());

		// 4) contents.links → spanLinks（nested）；contents.logs → spanEvents（nested）
		assertEquals("t2", src.path("spanLinks").get(0).path("traceID").asText());
		assertEquals("log1", src.path("spanEvents").get(0).path("name").asText());

		// 5) usage：script 把 String token 转成 long 并求和
		JsonNode usage = src.path("usage");
		assertEquals(10L, usage.path("input_tokens").asLong());
		assertEquals(20L, usage.path("output_tokens").asLong());
		assertEquals(30L, usage.path("total_tokens").asLong());

		// 6) pipeline 不触碰的顶层字段原样保留
		assertEquals(1000, src.path("time").asInt());
		assertEquals("test", src.path("tags").path("env").asText());
	}

	/** 用 Jackson 拼样例文档，contents.attribute/resource/links/logs 为 JSON 字符串（pipeline 期望的入参形态）。 */
	private static String buildSimulateBody() throws Exception {
		ObjectNode attribute = M.createObjectNode()
				.put("gen_ai.usage.input_tokens", "10")
				.put("gen_ai.usage.output_tokens", "20")
				.put("custom.key", "v");
		ObjectNode resource = M.createObjectNode().put("service.name", "agent-svc").put("host.name", "h1");
		ArrayNode links = M.createArrayNode();
		links.add(M.createObjectNode().put("traceID", "t2").put("spanID", "s2"));
		ArrayNode logs = M.createArrayNode();
		logs.add(M.createObjectNode().put("name", "log1").put("time", 1050));

		ObjectNode contents = M.createObjectNode();
		contents.put("traceID", "trace-1").put("spanID", "span-1").put("parentSpanID", "p-1");
		contents.put("name", "chat").put("service", "agent-svc").put("kind", "client");
		contents.put("start", 1000).put("end", 1100).put("duration", 100);
		contents.put("statusCode", "0").put("statusMessage", "ok").put("traceState", "").put("host", "h1");
		contents.set("otlp", M.createObjectNode().put("name", "otel").put("version", "1.0"));
		// 这些字段在 ES 里是【字符串】（内含 JSON），json processor 会解析它们
		contents.put("attribute", M.writeValueAsString(attribute));
		contents.put("resource", M.writeValueAsString(resource));
		contents.put("links", M.writeValueAsString(links));
		contents.put("logs", M.writeValueAsString(logs));

		ObjectNode source = M.createObjectNode();
		source.set("contents", contents);
		source.put("time", 1000);
		source.set("tags", M.createObjectNode().put("env", "test"));

		ObjectNode root = M.createObjectNode();
		ArrayNode docs = M.createArrayNode();
		docs.add(M.createObjectNode().set("_source", source));
		root.set("docs", docs);
		return M.writeValueAsString(root);
	}

	private static boolean pipelineReady() {
		try {
			HttpClient.newHttpClient().send(
					HttpRequest.newBuilder(URI.create(ES_URL + "/_ingest/pipeline/" + PIPELINE)).GET().build(),
					HttpResponse.BodyHandlers.discarding());
			return true;
		}
		catch (Exception e) {
			return false;
		}
	}
}
