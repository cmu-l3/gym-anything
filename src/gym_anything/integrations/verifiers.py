"""Gym-anything environments as Prime Intellect `verifiers` environments.

Prime-rl serves the policy over an OpenAI-compatible endpoint and OWNS the
sampling loop: it calls `env.rollout(client=<policy>, ...)` and trains on the
tokens the policy generates. The environment never makes its own model call.

So this adapter drives a **real reference agent** (the same class you select
locally with `--agent`, e.g. `Qwen3VLAgent`) by reusing exactly its two
model-facing halves — building the prompt messages and parsing the completion
into env actions — while the framework does the sampling in between. There is
no separate "scaffold": prime-rl uses the agent definition itself. Only
OpenAI-message agents (those exposing the `driver_*` seam) can be driven this
way; provider-native agents (Anthropic/Google native tools) cannot be served
over an OpenAI policy endpoint.

Dataset rows come from `hub.build_task_rows`. Requires the `prime-rl` extra.
"""

from __future__ import annotations

import asyncio
import base64
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import verifiers as vf
from datasets import Dataset

DEFAULT_RESOLUTION = (1920, 1080)


def _make_agent(name: str, agent_args: Optional[Dict[str, Any]]):
    """Instantiate a reference agent by class name, exactly like run_single."""
    import agents.agents as registry

    cls = getattr(registry, name, None)
    if cls is None:
        raise ValueError(
            f"Unknown agent {name!r}; available: {', '.join(getattr(registry, '__all__', []))}"
        )
    agent = cls(agent_args=dict(agent_args or {}), verbose=False, debug=False)
    if not getattr(agent, "driven", False):
        drivable = sorted(
            n for n in getattr(registry, "__all__", [])
            if getattr(getattr(registry, n, None), "driven", False)
        )
        raise ValueError(
            f"Agent {name!r} cannot be driven by prime-rl: its model call is provider-native "
            "(Anthropic/Google/Azure) and does not run over an OpenAI policy endpoint. "
            f"Pick an OpenAI-compatible agent (has the DrivableAgentMixin seam): {', '.join(drivable)}."
        )
    return agent


def _task_text(prompt_rows: Any) -> str:
    """Extract the task instruction text from the dataset prompt rows."""
    if isinstance(prompt_rows, str):
        return prompt_rows
    parts: List[str] = []
    for msg in prompt_rows or []:
        content = msg.get("content") if isinstance(msg, dict) else getattr(msg, "content", None)
        if isinstance(content, str):
            parts.append(content)
        elif isinstance(content, list):
            parts.extend(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
    return "\n".join(p for p in parts if p).strip()


def _obs_screenshot_b64(env: Any, obs: Optional[Dict[str, Any]]) -> str:
    """Base64 PNG from an observation, for local and remote envs alike."""
    screen = (obs or {}).get("screen") or {}
    b64 = screen.get("png_b64")
    if b64:
        return b64
    path = screen.get("path")
    if not path:
        raise RuntimeError("observation carries no screen image")
    if screen.get("remote"):
        path = env.fetch_path(path)
    return base64.b64encode(Path(path).read_bytes()).decode()


def _finalize_episode(state: "vf.State") -> None:
    """Run the post-task hook + real verifier exactly once, while the VM is
    still alive.

    MUST run before the env is closed. verifiers runs cleanup handlers
    (including env teardown) *before* rubric scoring, so the reward is computed
    here (from a cleanup handler) and stashed in ``state``.
    """
    if "episode_reward" in state:
        return
    env = state.get("ga_env")
    if env is None:
        state["episode_reward"] = 0.0
        state["verifier"] = {"error": "environment was never booted"}
        state["finalize_error"] = "ga_env missing at finalize time"
        return
    try:
        _obs, reward, _done, step_info = env.step([], mark_done=True)
        verifier = step_info.get("verifier")
        if verifier is None:
            try:
                summary_path = Path(env.episode_dir) / "summary.json"
                if summary_path.exists():
                    verifier = json.loads(summary_path.read_text()).get("verifier")
            except (OSError, TypeError, ValueError):
                verifier = None
        state["episode_reward"] = float(reward or 0.0)
        state["verifier"] = verifier or {}
    except Exception as e:
        import traceback

        state["episode_reward"] = 0.0
        state["verifier"] = {"error": f"{e}"}
        state["finalize_error"] = traceback.format_exc()[-2000:]


class GymAnythingAgentEnv(vf.MultiTurnEnv):
    """verifiers MultiTurnEnv that drives a real reference agent."""

    def __init__(
        self,
        *,
        agent: str,
        agent_args: Optional[Dict[str, Any]],
        runner: Optional[str],
        remote_url: Optional[str],
        use_cache: bool,
        cache_level: str,
        use_savevm: bool,
        verifier_overrides: Optional[Dict[str, str]] = None,
        **kwargs: Any,
    ):
        super().__init__(**kwargs)
        self.agent_name = agent
        self.agent_args = agent_args or {}
        self.runner = runner
        self.remote_url = remote_url
        self.use_cache = use_cache
        self.cache_level = cache_level
        self.use_savevm = use_savevm
        self.verifier_overrides = verifier_overrides or {}

    # -- boot / teardown ---------------------------------------------------

    def _boot(self, info: Dict[str, Any]) -> Tuple[Any, str, Tuple[int, int]]:
        env_dir = info["env_dir"]
        task_id = info["task_id"]
        if self.remote_url:
            from ..remote.client import RemoteGymEnv

            env = RemoteGymEnv.from_config(
                self.remote_url,
                env_dir,
                task_id=task_id,
                verifier_env=(self.verifier_overrides or None),
            )
        else:
            from ..config.loading import from_config

            overrides = {"runner": self.runner} if self.runner else None
            env = from_config(env_dir, task_id=task_id, overrides=overrides)
            if self.verifier_overrides:
                env.set_verifier_overrides(self.verifier_overrides)
        obs = env.reset(
            seed=int(info.get("seed", 0)),
            use_cache=self.use_cache,
            cache_level=self.cache_level,
            use_savevm=self.use_savevm,
        )
        env.set_episode_limits(max_steps=100000, timeout_sec=10**9)
        screen = (obs or {}).get("screen") or {}
        resolution = tuple(screen.get("resolution") or DEFAULT_RESOLUTION)
        b64 = _obs_screenshot_b64(env, obs)
        return env, b64, resolution

    def _observe(self, env: Any) -> str:
        return _obs_screenshot_b64(env, env.capture_observation())

    # -- verifiers hooks -----------------------------------------------------

    async def setup_state(self, state: vf.State) -> None:
        info = state.get("info", {})
        task_description = _task_text(state.get("prompt"))
        env, b64, resolution = await asyncio.to_thread(self._boot, dict(info))
        state["ga_env"] = env
        state["resolution"] = resolution
        state["actions_executed"] = 0
        state["parse_errors"] = 0

        agent = _make_agent(self.agent_name, self.agent_args)
        agent.init(
            task_description=task_description,
            display_resolution=resolution,
            save_path=str(getattr(env, "episode_dir", ".") or "."),
        )
        state["agent"] = agent
        # The agent builds its own opening messages (system prompt + first
        # screenshot), using its real logic — the framework samples from these.
        state["prompt"] = agent.driver_initial_messages(b64)

    async def env_response(
        self, messages: vf.Messages, state: vf.State, **kwargs: Any
    ) -> vf.Messages:
        env = state["ga_env"]
        agent = state["agent"]
        # messages[-1] is the completion the framework just sampled from the
        # policy. Parse it with the agent's own parser.
        result = await asyncio.to_thread(agent.driver_parse, messages[-1])
        actions = result.get("actions") or []
        if result.get("parse_error"):
            state["parse_errors"] += 1

        last_obs: Optional[Dict[str, Any]] = None
        wait = result.get("wait")
        if wait is not None:
            await asyncio.sleep(min(float(wait), 30.0))
        if actions and not result.get("done"):
            last_obs, _r, _d, _i = await asyncio.to_thread(env.step, actions)
            state["actions_executed"] += len(actions)

        if result.get("done"):
            await asyncio.to_thread(_finalize_episode, state)
            resp = [{"role": "user", "content": "Episode terminated."}]
            state["final_env_response"] = resp
            return resp

        if last_obs is not None:
            b64 = _obs_screenshot_b64(env, last_obs)
        else:
            b64 = await asyncio.to_thread(self._observe, env)
        return agent.driver_observation_messages(b64)

    @vf.cleanup(priority=50)
    async def finalize_reward(self, state: vf.State) -> None:
        """Score with the real verifier while the VM is alive (before close)."""
        await asyncio.to_thread(_finalize_episode, state)

    @vf.cleanup(priority=0)
    async def close_env(self, state: vf.State) -> None:
        env = state.pop("ga_env", None)
        if env is not None:
            await asyncio.to_thread(env.close)


# ---------------------------------------------------------------------------
# Rewards
# ---------------------------------------------------------------------------


async def task_reward(state: vf.State) -> float:
    return float(state.get("episode_reward", 0.0))


async def verifier_passed(state: vf.State) -> float:
    return 1.0 if (state.get("verifier") or {}).get("passed") else 0.0


async def verifier_score(state: vf.State) -> float:
    return float((state.get("verifier") or {}).get("score") or 0.0)


async def actions_executed(state: vf.State) -> float:
    return float(state.get("actions_executed", 0))


async def parse_errors(state: vf.State) -> float:
    return float(state.get("parse_errors", 0))


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------


def build_agent_env(
    rows: List[Dict[str, Any]],
    *,
    agent: str,
    agent_args: Optional[Dict[str, Any]] = None,
    runner: Optional[str] = None,
    remote_url: Optional[str] = None,
    max_turns: int = 15,
    use_cache: bool = True,
    cache_level: str = "post_start",
    use_savevm: bool = False,
    verifier_overrides: Optional[Dict[str, str]] = None,
    env_id: str = "gym-anything",
    env_args: Optional[Dict[str, Any]] = None,
    **kwargs: Any,
) -> vf.Environment:
    """Build a verifiers Environment that drives a real reference agent.

    Args:
        rows: dataset rows (`prompt`/`info`/`task`), from `hub.build_task_rows`.
        agent: reference agent class name, exactly as `--agent` locally
            (e.g. "Qwen3VLAgent"). Must be OpenAI-compatible (drivable).
        agent_args: the agent's own args dict, exactly as `--agent_args`
            (model, temperature, decoding_params, ...).
        runner: gym-anything runner ("modal" boots VMs on Modal; None
            auto-selects).
        remote_url: run envs on a remote cluster instead of in-process.
        max_turns: model-turn budget per rollout.
        use_cache / cache_level / use_savevm: checkpoint knobs.
        verifier_overrides: per-env verifier/VLM overrides (env-var-key form).
    """
    if not rows:
        raise ValueError("no dataset rows supplied")
    if not agent:
        raise ValueError("an agent must be named (like --agent locally); no default")
    # Fail fast with a clear error if the agent is unknown / not drivable.
    _make_agent(agent, agent_args)

    dataset = Dataset.from_list(rows)
    rubric = vf.Rubric(
        funcs=[task_reward, verifier_passed, verifier_score, actions_executed, parse_errors],
        weights=[1.0, 0.0, 0.0, 0.0, 0.0],
    )
    return GymAnythingAgentEnv(
        dataset=dataset,
        eval_dataset=dataset,
        rubric=rubric,
        max_turns=max_turns,
        agent=agent,
        agent_args=agent_args,
        runner=runner,
        remote_url=remote_url,
        use_cache=use_cache,
        cache_level=cache_level,
        use_savevm=use_savevm,
        verifier_overrides=verifier_overrides,
        env_id=env_id,
        env_args=env_args or {},
        **kwargs,
    )
