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
package com.alibaba.cloud.ai.studio.admin.builder;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 鉴权链路【集成测试】（批次 3，#1+#2，核心链路 ①）。
 * {@code @SpringBootTest} 起完整应用上下文（连真实 MySQL/Redis/Nacos 等，profile=local），
 * 用 MockMvc 走 Spring MVC 层（含 {@code TokenAuthInterceptor}），打真实 DB 的种子账号 saa/123456。
 *
 * <p>断言基于实测（2026-06-20 curl 探得）：正确登录→200+token；错密→401；
 * 受保护接口无 token→401；有效 Bearer token→200。
 *
 * <p>依赖：本地中间件在跑（{@code deps-start.sh}），MySQL 有种子账号 saa。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("local")
class AuthIntegrationTest {

	private static final ObjectMapper M = new ObjectMapper();

	@Autowired
	private MockMvc mockMvc;

	/** 正确凭据 → 200 且返回 access_token。 */
	@Test
	void login_validCredentials_returnsAccessToken() throws Exception {
		mockMvc.perform(post("/console/v1/auth/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"username\":\"saa\",\"password\":\"123456\"}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.access_token").isNotEmpty());
	}

	/** 错误密码 → 401（实测：全局异常处理返回 401）。 */
	@Test
	void login_wrongPassword_isUnauthorized() throws Exception {
		mockMvc.perform(post("/console/v1/auth/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"username\":\"saa\",\"password\":\"WRONGPASS\"}"))
				.andExpect(status().isUnauthorized());
	}

	/** 受保护接口（/console/v1/**）无 Authorization → 拦截器返 401。 */
	@Test
	void protectedEndpoint_withoutToken_isUnauthorized() throws Exception {
		mockMvc.perform(get("/console/v1/accounts/10000"))
				.andExpect(status().isUnauthorized());
	}

	/** 受保护接口 + 有效 Bearer token → 拦截器放行 → 200（返回种子账号 10000）。 */
	@Test
	void protectedEndpoint_withValidToken_isOk() throws Exception {
		String token = login("saa", "123456");
		mockMvc.perform(get("/console/v1/accounts/10000")
				.header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.account_id").value("10000"));
	}

	private String login(String username, String password) throws Exception {
		String body = mockMvc.perform(post("/console/v1/auth/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content(String.format("{\"username\":\"%s\",\"password\":\"%s\"}", username, password)))
				.andReturn().getResponse().getContentAsString();
		JsonNode node = M.readTree(body);
		return node.path("data").path("access_token").asText();
	}
}
