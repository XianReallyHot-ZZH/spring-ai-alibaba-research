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
package com.alibaba.cloud.ai.studio.admin.service.impl;

import com.alibaba.cloud.ai.studio.admin.dto.request.ExperimentCreateRequest;
import com.alibaba.cloud.ai.studio.admin.entity.ExperimentDO;
import com.alibaba.cloud.ai.studio.admin.mapper.DatasetItemMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.DatasetVersionMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.EvaluatorMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.EvaluatorVersionMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.ExperimentMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.ExperimentResultMapper;
import com.alibaba.cloud.ai.studio.admin.service.ChatSessionService;
import com.alibaba.cloud.ai.studio.admin.service.PromptVersionService;
import com.alibaba.cloud.ai.studio.admin.dto.Experiment;
import com.alibaba.cloud.ai.studio.admin.utils.ModelConfigParser;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Characterization test —— 锁定 {@link ExperimentServiceImpl} 的实验状态机【实际】转换规则
 * （凭读码记录的真实行为，不写"应该"）。仅刻画不依赖模型/异步执行的同步状态逻辑：
 * create→RUNNING、stop 的终态守卫、delete 的 RUNNING 守卫。
 * RUNNING→COMPLETED/FAILED 经异步模型调用，见 13-test-plan 批次 4（需模型）。
 *
 * <p>批次 2（#7）。用 evaluationObjectConfig.type="other" 使 create 的异步执行空转、不触模型。
 */
@ExtendWith(MockitoExtension.class)
class ExperimentStateMachineCharacterizationTest {

	@Mock private ExperimentMapper experimentMapper;
	@Mock private ExperimentResultMapper experimentResultMapper;
	@Mock private DatasetVersionMapper datasetVersionMapper;
	@Mock private EvaluatorMapper evaluatorMapper;
	@Mock private EvaluatorVersionMapper evaluatorVersionMapper;
	@Mock private DatasetItemMapper datasetItemMapper;
	@Mock private ModelConfigParser modelConfigParser;
	@Mock private PromptVersionService promptVersionService;
	@Mock private ChatSessionService chatSessionService;
	@Mock private EvaluatorServiceImpl evaluatorServiceImpl;

	@InjectMocks
	private ExperimentServiceImpl service;

	/** 实际：create 立刻把 status 置为 RUNNING（注意：不是 DRAFT），并 insert。 */
	@Test
	void create_setsStatusRunning_andInserts() {
		ExperimentCreateRequest req = new ExperimentCreateRequest();
		req.setName("exp-char");
		// 非 "prompt" 类型 → 异步 executeExperiment 提前 return，不触模型
		req.setEvaluationObjectConfig("{\"type\":\"other\"}");
		when(experimentMapper.insert(any(ExperimentDO.class))).thenReturn(1);

		Experiment e = service.create(req);

		assertEquals("RUNNING", e.getStatus(), "实际行为：create 后 status=RUNNING（非 DRAFT）");
		verify(experimentMapper).insert(argThat(d -> "RUNNING".equals(d.getStatus())));
	}

	/** 实际：stop 一个 RUNNING 实验 → 置为 STOPPED。 */
	@Test
	void stop_running_transitionsToStopped() {
		ExperimentDO running = ExperimentDO.builder().id(1L).status("RUNNING").build();
		when(experimentMapper.selectById(1L)).thenReturn(running);
		when(experimentMapper.updateById(any(ExperimentDO.class))).thenReturn(1);

		Experiment e = service.stop(1L);

		assertEquals("STOPPED", e.getStatus());
		verify(experimentMapper).updateById(argThat(d -> "STOPPED".equals(d.getStatus())));
	}

	/** 实际：stop 处于终态（COMPLETED/FAILED/STOPPED）的实验 → no-op，不改状态、不 update。 */
	@Test
	void stop_terminalState_isNoOp() {
		ExperimentDO completed = ExperimentDO.builder().id(1L).status("COMPLETED").build();
		when(experimentMapper.selectById(1L)).thenReturn(completed);

		Experiment e = service.stop(1L);

		assertEquals("COMPLETED", e.getStatus(), "终态不变");
		verify(experimentMapper, never()).updateById(any(ExperimentDO.class));
	}

	/** 实际：delete 一个 RUNNING 实验 → 抛 IllegalStateException（不允许删运行中的）。 */
	@Test
	void delete_running_throws() {
		ExperimentDO running = ExperimentDO.builder().id(1L).status("RUNNING").build();
		when(experimentMapper.selectById(1L)).thenReturn(running);

		assertThrows(IllegalStateException.class, () -> service.deleteById(1L));
		verify(experimentMapper, never()).deleteById(any());
	}

	/** 实际：delete 非 RUNNING（如 STOPPED）→ 正常删除。 */
	@Test
	void delete_nonRunning_deletes() {
		ExperimentDO stopped = ExperimentDO.builder().id(1L).status("STOPPED").build();
		when(experimentMapper.selectById(1L)).thenReturn(stopped);
		when(experimentMapper.deleteById(1L)).thenReturn(1);

		service.deleteById(1L);

		verify(experimentMapper).deleteById(1L);
	}
}
