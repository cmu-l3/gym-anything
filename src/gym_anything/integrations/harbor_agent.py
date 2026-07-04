"""Harbor agent that runs a gym-anything reference agent loop.

Harbor's built-in computer-use agent (computer-1) provisions its own desktop
(Xvfb + XFCE + Chromium) inside the environment, which collides with benchmark
guests that already run a full desktop with the target application open. This
agent drives the guest through the gym-anything observation/action surface
instead, running a reference agent from ``agents/agents`` verbatim — the same
loop the local evaluation harness and the prime-rl adapter use.

It requires the trial environment to be ``GymAnythingEnvironment`` (it reaches
the booted ``GymAnythingEnv`` through ``environment.gym_env``)::

    harbor run --path <compiled-task> \\
        --agent-import-path gym_anything.integrations.harbor_agent:CuaWorldAgent \\
        --model gemini-3.5-flash \\
        --env gym_anything.integrations.harbor:GymAnythingEnvironment

``--model`` is passed to the reference agent verbatim (no provider-prefix
rewriting), so use the exact name the reference agent expects. The reference
agent class defaults to ``GeminiQwen3Agent`` and can be changed with
``--agent-kwarg reference_agent=Qwen3VLAgent``.
"""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from harbor.agents.base import BaseAgent
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext


class CuaWorldAgent(BaseAgent):
    """Runs a gym-anything reference agent against a GymAnythingEnvironment."""

    def __init__(
        self,
        logs_dir: Path,
        model_name: str | None = None,
        *args: Any,
        reference_agent: str = "GeminiQwen3Agent",
        max_steps: int = 15,
        temperature: float = 1.0,
        **kwargs: Any,
    ):
        super().__init__(logs_dir, model_name, *args, **kwargs)
        self._reference_agent_name = reference_agent
        self._max_steps = int(max_steps)
        self._temperature = float(temperature)

    @staticmethod
    def name() -> str:
        return "cua-world-agent"

    def version(self) -> str | None:
        return "0.1.0"

    async def setup(self, environment: BaseEnvironment) -> None:
        # The benchmark's own hooks provision the desktop and application.
        return None

    async def run(
        self,
        instruction: str,
        environment: BaseEnvironment,
        context: AgentContext,
    ) -> None:
        await asyncio.to_thread(self._run_sync, instruction, environment)

    # -- the local evaluation loop, verbatim ---------------------------------

    def _run_sync(self, instruction: str, environment: BaseEnvironment) -> None:
        gym_env = getattr(environment, "gym_env", None)
        if gym_env is None:
            raise RuntimeError(
                "CuaWorldAgent requires the gym-anything environment backend "
                "(--env gym_anything.integrations.harbor:GymAnythingEnvironment)"
            )

        agent = self._make_reference_agent(gym_env)

        obs = gym_env.capture_observation()
        screen = obs.get("screen") or {}
        resolution = tuple(screen.get("resolution") or (1920, 1080))
        agent.init(
            task_description=instruction,
            display_resolution=resolution,
            save_path=str(self.logs_dir),
        )

        action_outputs: list[dict[str, Any]] = []
        for _ in range(self._max_steps):
            action_groups = agent.step(obs, action_outputs)
            action_outputs = []
            done = False
            for group in action_groups or []:
                obs, _reward, done, info = gym_env.step(group.get("actions") or [])
                result = info.get(
                    "action_result", {"action": "other", "output": "Executed the action"}
                )
                action_outputs.append({**result, "tool_id": group.get("tool_id")})
            if getattr(agent, "done", False) or done:
                break

    def _make_reference_agent(self, gym_env: Any):
        import agents.agents as registry

        cls = getattr(registry, self._reference_agent_name, None)
        if cls is None:
            available = ", ".join(
                n for n in dir(registry) if n.endswith("Agent") and not n.startswith("_")
            )
            raise ValueError(
                f"Unknown reference agent {self._reference_agent_name!r}; "
                f"available: {available}"
            )
        task_root = gym_env.task_root
        task_name = Path(task_root).name if task_root else "task"
        agent_args = {
            "model": self.model_name or "",
            "exp_name": "harbor",
            "task_name": task_name,
            "temperature": self._temperature,
        }
        return cls(agent_args=agent_args, verbose=False, debug=False)


__all__ = ["CuaWorldAgent"]
