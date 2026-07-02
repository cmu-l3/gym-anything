"""Gym-anything environments as Prime Intellect `verifiers` environments.

Generic adapter: any gym-anything env folder becomes a verifiers
`MultiTurnEnv` rollout. Each rollout boots the env through the public API
(`from_config`), streams screenshots to the policy as base64 images, exposes
the single provider-agnostic `computer` tool, and scores the episode with the
env's real verifier. Benchmark bindings (e.g. CUA-World) supply the dataset
rows; publishable hub packages live under `extras/hubs/`.

Requires the `prime-rl` extra: `pip install "gym-anything[prime-rl]"`.
"""

from __future__ import annotations

import asyncio
import base64
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import verifiers as vf
from datasets import Dataset

from .computer_tool import (
    PARSE_ERROR,
    WRONG_TOOL,
    make_computer_tool,
    parse_tool_calls,
    prune_screenshots,
    screenshot_message,
    system_prompt,
    translate_action,
)

DEFAULT_RESOLUTION = (1920, 1080)


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
    (including env teardown) *before* rubric scoring, so the reward cannot be
    computed from a rubric function that touches the live env -- it is
    computed here (from a cleanup handler) and stashed in ``state`` for the
    reward functions to read.
    """
    if "episode_reward" in state:
        return
    env = state.get("ga_env")
    if env is None:
        # No env means setup never succeeded; surface it rather than silently
        # scoring 0 as if the task were merely failed.
        state["episode_reward"] = 0.0
        state["verifier"] = {"error": "environment was never booted"}
        state["finalize_error"] = "ga_env missing at finalize time"
        return
    try:
        _obs, reward, _done, step_info = env.step([], mark_done=True)
        verifier = step_info.get("verifier")
        if verifier is None:
            # Fallback for local envs; the episode dir is not readable when
            # the env runs on a remote worker.
            try:
                summary_path = Path(env.episode_dir) / "summary.json"
                if summary_path.exists():
                    verifier = json.loads(summary_path.read_text()).get("verifier")
            except (OSError, TypeError, ValueError):
                verifier = None
        state["episode_reward"] = float(reward or 0.0)
        state["verifier"] = verifier or {}
    except Exception as e:  # surface the real failure instead of a silent 0
        import traceback

        state["episode_reward"] = 0.0
        state["verifier"] = {"error": f"{e}"}
        state["finalize_error"] = traceback.format_exc()[-2000:]


class GymAnythingComputerEnv(vf.MultiTurnEnv):
    """verifiers MultiTurnEnv driving a gym-anything env via the computer tool."""

    def __init__(
        self,
        *,
        runner: Optional[str],
        remote_url: Optional[str],
        coordinate_mode: str,
        keep_recent_screenshots: int,
        use_cache: bool,
        cache_level: str,
        use_savevm: bool,
        verifier_overrides: Optional[Dict[str, str]] = None,
        **kwargs: Any,
    ):
        super().__init__(**kwargs)
        self.runner = runner
        self.remote_url = remote_url
        self.coordinate_mode = coordinate_mode
        self.keep_recent_screenshots = keep_recent_screenshots
        self.use_cache = use_cache
        self.cache_level = cache_level
        self.use_savevm = use_savevm
        self.verifier_overrides = verifier_overrides or {}

    # -- boot / teardown ---------------------------------------------------

    def _boot(self, info: Dict[str, Any]) -> Tuple[Any, str, Tuple[int, int]]:
        env_dir = info["env_dir"]
        task_id = info["task_id"]
        if self.remote_url:
            # The worker (routed by the master) picks its own runner.
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
        # Manual driving: never let the task's own step/time budget finalize
        # the episode underneath us; max_turns is the budget here.
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
        env, b64, resolution = await asyncio.to_thread(self._boot, dict(info))
        state["ga_env"] = env
        state["resolution"] = resolution
        state["parse_errors"] = 0
        state["actions_executed"] = 0

        prompt = list(state["prompt"])
        prompt.insert(
            0, {"role": "system", "content": system_prompt(resolution, self.coordinate_mode)}
        )
        prompt.append(screenshot_message(b64))
        state["prompt"] = prompt

    async def env_response(
        self, messages: vf.Messages, state: vf.State, **kwargs: Any
    ) -> vf.Messages:
        env = state["ga_env"]
        resolution = state["resolution"]
        last = messages[-1]
        calls = parse_tool_calls(last)

        if not calls:
            state["parse_errors"] += 1
            b64 = await asyncio.to_thread(self._observe, env)
            return [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "No tool call found. Use the `computer` tool "
                            "for every step (action=terminate when done).",
                        },
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
                    ],
                }
            ]

        responses: List[Dict[str, Any]] = []
        terminal = False
        last_obs: Optional[Dict[str, Any]] = None
        for tc_id, args in calls:
            action = args.get("action")
            if action == WRONG_TOOL:
                state["parse_errors"] += 1
                responses.append(
                    {"role": "tool", "content": "Unsupported tool. Use `computer`.", "tool_call_id": tc_id}
                )
                continue
            if action == PARSE_ERROR:
                state["parse_errors"] += 1
                responses.append(
                    {"role": "tool", "content": "Could not parse tool arguments as JSON.", "tool_call_id": tc_id}
                )
                continue
            plan = translate_action(args, resolution, self.coordinate_mode)
            if plan["error"]:
                state["parse_errors"] += 1
                responses.append({"role": "tool", "content": plan["error"], "tool_call_id": tc_id})
                continue
            if plan["terminal"]:
                terminal = True
                responses.append({"role": "tool", "content": "Episode terminated.", "tool_call_id": tc_id})
                continue
            if plan["wait"] is not None:
                await asyncio.sleep(min(plan["wait"], 30.0))
            if plan["actions"]:
                last_obs, _reward, _done, _info = await asyncio.to_thread(
                    env.step, plan["actions"]
                )
                state["actions_executed"] += len(plan["actions"])
            responses.append({"role": "tool", "content": "Executed.", "tool_call_id": tc_id})

        if terminal:
            await asyncio.to_thread(_finalize_episode, state)
            state["final_env_response"] = responses
            return responses

        if last_obs is not None:
            b64 = _obs_screenshot_b64(env, last_obs)
        else:
            b64 = await asyncio.to_thread(self._observe, env)
        responses.append(screenshot_message(b64))
        return responses

    async def get_prompt_messages(self, state: vf.State) -> vf.Messages:
        messages = await super().get_prompt_messages(state)
        return prune_screenshots(messages, self.keep_recent_screenshots)

    @vf.cleanup(priority=50)
    async def finalize_reward(self, state: vf.State) -> None:
        """Score the episode with the real verifier while the VM is alive.

        Cleanup handlers run in descending priority and *before* rubric
        scoring, so this (priority 50) runs before close_env (priority 0)
        while ga_env is still open. Idempotent: no-op if the terminate path
        already finalized.
        """
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
    """The env's own reward.

    The episode is finalized (real verifier run) by the finalize_reward
    cleanup handler while the VM is alive; this reads the stashed result.
    """
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


def build_computer_env(
    rows: List[Dict[str, Any]],
    *,
    runner: Optional[str] = None,
    remote_url: Optional[str] = None,
    coordinate_mode: str = "norm1000",
    max_turns: int = 15,
    # -1 = full untruncated screenshot history, matching the proven reference
    # agents (agents/agents/gemini_computer_use.py: "deliberately do NOT
    # compact per turn"). Set a positive value to bound context growth at the
    # cost of the model losing visual history.
    keep_recent_screenshots: int = -1,
    use_cache: bool = True,
    cache_level: str = "post_start",
    use_savevm: bool = False,
    verifier_overrides: Optional[Dict[str, str]] = None,
    env_id: str = "gym-anything",
    env_args: Optional[Dict[str, Any]] = None,
    **kwargs: Any,
) -> vf.Environment:
    """Build a verifiers Environment from dataset rows.

    Args:
        rows: dataset rows with `prompt`, `info` ({env_dir, task_id, seed})
            and `task` keys; benchmark bindings produce these (e.g.
            `benchmarks.cua_world.hub.build_task_rows`).
        runner: gym-anything runner override for in-process envs ("modal"
            boots VMs on Modal cloud; None lets the host auto-select).
        remote_url: run envs on a gym-anything remote cluster instead of
            in-process; the worker picks the runner, `runner` is ignored.
        coordinate_mode: "norm1000" (0-1000 normalized) or "pixel".
        max_turns: model-turn budget per rollout.
        keep_recent_screenshots: screenshots kept in context (older ones
            are replaced with placeholders to bound context growth).
        use_cache / cache_level / use_savevm: gym-anything checkpoint knobs.
        verifier_overrides: per-env verifier/VLM overrides in env-var-key
            form (e.g. {"GYM_ANYTHING_VERIFIER_MODE": "vlm_checklist",
            "VLM_BACKEND": "local"}), delivered via set_verifier_overrides.
    """
    if not rows:
        raise ValueError("no dataset rows supplied")
    dataset = Dataset.from_list(rows)
    rubric = vf.Rubric(
        funcs=[task_reward, verifier_passed, verifier_score, actions_executed, parse_errors],
        weights=[1.0, 0.0, 0.0, 0.0, 0.0],
    )
    return GymAnythingComputerEnv(
        dataset=dataset,
        eval_dataset=dataset,
        rubric=rubric,
        tool_defs=[make_computer_tool(coordinate_mode)],
        max_turns=max_turns,
        runner=runner,
        remote_url=remote_url,
        coordinate_mode=coordinate_mode,
        keep_recent_screenshots=keep_recent_screenshots,
        use_cache=use_cache,
        cache_level=cache_level,
        use_savevm=use_savevm,
        verifier_overrides=verifier_overrides,
        env_id=env_id,
        env_args=env_args or {},
        **kwargs,
    )
