"""CUA-World as a Prime Intellect verifiers environment.

Runs gym-anything in-process: each rollout boots a real VM (Linux, Windows,
or Android guest) through the selected runner -- ModalRunner by default, so
the VMs run on Modal cloud sandboxes with KVM and nothing is required
locally beyond a Modal token. Screenshots stream to the policy as base64
images; the policy acts through a single `computer` tool; the episode is
scored by the task's real verifier (the benchmark's `verifier.py` contract),
not an LLM judge.

Requires the gym-anything repo installed (`pip install -e .` from the repo
root) so the `gym_anything` and `benchmarks` packages plus the environment
folders are available.

Usage:
    vf-eval cua-world -m <vision-model> -n 1 -r 1 \
        -a '{"env_names": ["gimp_env"], "task_ids": ["horizontal_mirror"]}'
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import tempfile
from pathlib import Path
from typing import Any

import verifiers as vf
from datasets import Dataset

_REPO_ROOT: Path | None = None


def _repo_root() -> Path:
    """Repo root inferred from the installed benchmarks package."""
    global _REPO_ROOT
    if _REPO_ROOT is None:
        import benchmarks

        _REPO_ROOT = Path(benchmarks.__file__).resolve().parent.parent
    return _REPO_ROOT


# ---------------------------------------------------------------------------
# Tool definition (single provider-agnostic `computer` tool)
# ---------------------------------------------------------------------------

_ACTIONS = [
    "left_click",
    "double_click",
    "right_click",
    "middle_click",
    "mouse_move",
    "left_click_drag",
    "scroll",
    "key",
    "type",
    "wait",
    "screenshot",
    "terminate",
]


def _make_computer_tool(coordinate_mode: str) -> dict[str, Any]:
    if coordinate_mode == "norm1000":
        coord_desc = (
            "[x, y] in a 0-1000 normalized coordinate space; [0,0] is the "
            "top-left corner and [1000,1000] the bottom-right corner of the screen."
        )
    else:
        coord_desc = "[x, y] in raw screen pixels; origin is the top-left corner."
    return {
        "name": "computer",
        "description": (
            "Control the computer with mouse and keyboard and observe the "
            "screen. After every action you receive a new screenshot.\n"
            "Actions: left_click / double_click / right_click / middle_click "
            "(need `coordinate`), mouse_move (needs `coordinate`), "
            "left_click_drag (needs `coordinate` start and `coordinate2` end), "
            "scroll (needs `pixels`; negative scrolls down, optionally "
            "`coordinate` to scroll at), key (needs `keys`, e.g. "
            "[\"ctrl\",\"s\"] or [\"Return\"]), type (needs `text`), wait "
            "(needs `time` seconds), screenshot (no args), terminate (ends "
            "the episode; set `status`)."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": _ACTIONS},
                "coordinate": {
                    "type": "array",
                    "items": {"type": "number"},
                    "description": coord_desc,
                },
                "coordinate2": {
                    "type": "array",
                    "items": {"type": "number"},
                    "description": "Drag end point; same convention as `coordinate`.",
                },
                "text": {"type": "string", "description": "Text for action=type."},
                "keys": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Keys pressed together for action=key.",
                },
                "pixels": {
                    "type": "number",
                    "description": "Scroll amount for action=scroll.",
                },
                "time": {
                    "type": "number",
                    "description": "Seconds to wait for action=wait.",
                },
                "status": {
                    "type": "string",
                    "enum": ["success", "failure"],
                    "description": "Task outcome for action=terminate.",
                },
            },
            "required": ["action"],
        },
    }


def _system_prompt(resolution: tuple[int, int], coordinate_mode: str) -> str:
    w, h = resolution
    if coordinate_mode == "norm1000":
        coords = (
            "Coordinates use a 0-1000 normalized space on both axes "
            f"(the real screen is {w}x{h} pixels; you never need pixel values)."
        )
    else:
        coords = f"Coordinates are raw pixels on a {w}x{h} screen."
    return (
        "You are operating a real computer through the `computer` tool to "
        "complete the task described by the user. The screen content is "
        "provided to you as screenshots; a fresh screenshot follows every "
        f"action. {coords} Consult the latest screenshot before every click "
        "and click at the center of targets. Applications can be slow: if "
        "the screen has not caught up with your action, use wait and then "
        "screenshot. When the task is complete (or impossible), call the "
        "tool with action=terminate."
    )


# ---------------------------------------------------------------------------
# Action translation: tool call -> gym-anything action dicts
# ---------------------------------------------------------------------------


def _to_pixels(coord: Any, resolution: tuple[int, int], mode: str) -> tuple[int, int]:
    x, y = float(coord[0]), float(coord[1])
    if mode == "norm1000":
        x = x * resolution[0] / 1000.0
        y = y * resolution[1] / 1000.0
    return int(round(x)), int(round(y))


def _translate(args: dict[str, Any], resolution: tuple[int, int], mode: str) -> dict[str, Any]:
    """Translate one computer-tool call into gym actions + control metadata.

    Returns {"actions": [...], "terminal": bool, "wait": float|None, "error": str|None}
    """
    out: dict[str, Any] = {"actions": [], "terminal": False, "wait": None, "error": None}
    action = args.get("action")
    try:
        if action in ("left_click", "double_click", "right_click", "middle_click", "mouse_move"):
            x, y = _to_pixels(args["coordinate"], resolution, mode)
            key = "move" if action == "mouse_move" else action
            out["actions"] = [{"mouse": {key: [x, y]}}]
        elif action == "left_click_drag":
            x1, y1 = _to_pixels(args["coordinate"], resolution, mode)
            x2, y2 = _to_pixels(args.get("coordinate2", args["coordinate"]), resolution, mode)
            out["actions"] = [{"mouse": {"left_click_drag": [[x1, y1], [x2, y2]]}}]
        elif action == "scroll":
            amount = args.get("pixels", -400)
            acts = []
            if args.get("coordinate"):
                x, y = _to_pixels(args["coordinate"], resolution, mode)
                acts.append({"mouse": {"move": [x, y]}})
            acts.append({"mouse": {"scroll": amount}})
            out["actions"] = acts
        elif action == "key":
            keys = args.get("keys") or []
            if isinstance(keys, str):
                keys = keys.replace("+", " ").split()
            out["actions"] = [{"keyboard": {"keys": list(keys)}}]
        elif action == "type":
            out["actions"] = [{"keyboard": {"text": str(args.get("text", ""))}}]
        elif action == "wait":
            out["wait"] = float(args.get("time", 1.0))
        elif action == "screenshot":
            pass  # no-op; a screenshot always follows
        elif action == "terminate":
            out["terminal"] = True
        else:
            out["error"] = f"Unknown action: {action!r}"
    except (KeyError, IndexError, TypeError, ValueError) as e:
        out["error"] = f"Malformed arguments for {action!r}: {e}"
    return out


def _parse_tool_calls(message: Any) -> list[tuple[str, dict[str, Any]]]:
    """Extract (tool_call_id, arguments) pairs for `computer` calls."""
    calls = []
    tool_calls = getattr(message, "tool_calls", None)
    if tool_calls is None and isinstance(message, dict):
        tool_calls = message.get("tool_calls")
    for i, tc in enumerate(tool_calls or []):
        fn = getattr(tc, "function", None) or (tc.get("function") if isinstance(tc, dict) else None)
        name = getattr(fn, "name", None) or (fn.get("name") if isinstance(fn, dict) else None)
        name = name or getattr(tc, "name", None) or (tc.get("name") if isinstance(tc, dict) else None)
        raw = getattr(fn, "arguments", None) or (fn.get("arguments") if isinstance(fn, dict) else None)
        raw = raw if raw is not None else (getattr(tc, "arguments", None) or (tc.get("arguments") if isinstance(tc, dict) else None))
        tc_id = getattr(tc, "id", None) or (tc.get("id") if isinstance(tc, dict) else None) or f"call_{i}"
        if name != "computer":
            calls.append((tc_id, {"action": "__wrong_tool__", "__name__": name}))
            continue
        if isinstance(raw, str):
            try:
                args = json.loads(raw)
            except json.JSONDecodeError:
                args = {"action": "__parse_error__"}
        elif isinstance(raw, dict):
            args = raw
        else:
            args = {"action": "__parse_error__"}
        calls.append((tc_id, args))
    return calls


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
            summary_path = Path(env.episode_dir) / "summary.json"
            if summary_path.exists():
                verifier = json.loads(summary_path.read_text()).get("verifier")
        state["episode_reward"] = float(reward or 0.0)
        state["verifier"] = verifier or {}
    except Exception as e:  # surface the real failure instead of a silent 0
        import traceback

        state["episode_reward"] = 0.0
        state["verifier"] = {"error": f"{e}"}
        state["finalize_error"] = traceback.format_exc()[-2000:]


def _screenshot_message(b64: str) -> dict[str, Any]:
    return {
        "role": "user",
        "content": [
            {"type": "text", "text": "Current screen:"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ],
    }


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------


class CuaWorldEnv(vf.MultiTurnEnv):
    def __init__(
        self,
        *,
        runner: str,
        coordinate_mode: str,
        keep_recent_screenshots: int,
        use_cache: bool,
        cache_level: str,
        use_savevm: bool,
        **kwargs: Any,
    ):
        super().__init__(**kwargs)
        self.runner = runner
        self.coordinate_mode = coordinate_mode
        self.keep_recent_screenshots = keep_recent_screenshots
        self.use_cache = use_cache
        self.cache_level = cache_level
        self.use_savevm = use_savevm

    # -- boot / teardown ---------------------------------------------------

    def _boot(self, info: dict[str, Any]) -> tuple[Any, str, tuple[int, int]]:
        os.environ["GYM_ANYTHING_RUNNER"] = self.runner
        os.chdir(_repo_root())  # relative mount paths in env.json resolve here
        from gym_anything import from_config

        env = from_config(info["env_dir"], task_id=info["task_id"])
        env.reset(
            seed=int(info.get("seed", 0)),
            use_cache=self.use_cache,
            cache_level=self.cache_level,
            use_savevm=self.use_savevm,
        )
        # Manual driving: never let the task's own step/time budget finalize
        # the episode underneath us; max_turns is the budget here.
        env.set_episode_limits(max_steps=100000, timeout_sec=10**9)
        screen = next(
            (o for o in env.env_spec.observation if o.type == "rgb_screen"), None
        )
        resolution = tuple(screen.resolution) if screen and screen.resolution else (1920, 1080)
        b64 = self._grab_screenshot(env)
        return env, b64, resolution

    def _grab_screenshot(self, env: Any) -> str:
        path = Path(tempfile.mkdtemp(prefix="cua_shot_")) / "screen.png"
        ok = env._runner.capture_screenshot(path)
        if not ok or not path.exists():
            raise RuntimeError("screenshot capture failed")
        return base64.b64encode(path.read_bytes()).decode()

    def _finalize(self, state: vf.State) -> None:
        _finalize_episode(state)

    # -- verifiers hooks -----------------------------------------------------

    async def setup_state(self, state: vf.State) -> None:
        info = state.get("info", {})
        env, b64, resolution = await asyncio.to_thread(self._boot, dict(info))
        state["ga_env"] = env
        state["resolution"] = resolution
        state["parse_errors"] = 0
        state["actions_executed"] = 0

        prompt = list(state["prompt"])
        prompt.insert(0, {"role": "system", "content": _system_prompt(resolution, self.coordinate_mode)})
        prompt.append(_screenshot_message(b64))
        state["prompt"] = prompt

    async def env_response(
        self, messages: vf.Messages, state: vf.State, **kwargs: Any
    ) -> vf.Messages:
        env = state["ga_env"]
        resolution = state["resolution"]
        last = messages[-1]
        calls = _parse_tool_calls(last)

        if not calls:
            state["parse_errors"] += 1
            b64 = await asyncio.to_thread(self._grab_screenshot, env)
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

        responses: list[dict[str, Any]] = []
        terminal = False
        for tc_id, args in calls:
            action = args.get("action")
            if action == "__wrong_tool__":
                state["parse_errors"] += 1
                responses.append(
                    {"role": "tool", "content": "Unsupported tool. Use `computer`.", "tool_call_id": tc_id}
                )
                continue
            if action == "__parse_error__":
                state["parse_errors"] += 1
                responses.append(
                    {"role": "tool", "content": "Could not parse tool arguments as JSON.", "tool_call_id": tc_id}
                )
                continue
            plan = _translate(args, resolution, self.coordinate_mode)
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
                await asyncio.to_thread(env.step, plan["actions"])
                state["actions_executed"] += len(plan["actions"])
            responses.append({"role": "tool", "content": "Executed.", "tool_call_id": tc_id})

        if terminal:
            await asyncio.to_thread(self._finalize, state)
            state["final_env_response"] = responses
            return responses

        b64 = await asyncio.to_thread(self._grab_screenshot, env)
        responses.append(_screenshot_message(b64))
        return responses

    async def get_prompt_messages(self, state: vf.State) -> vf.Messages:
        messages = await super().get_prompt_messages(state)
        return _prune_screenshots(messages, self.keep_recent_screenshots)

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


def _prune_screenshots(messages: vf.Messages, keep_recent: int) -> vf.Messages:
    """Replace all but the last `keep_recent` screenshots with placeholders."""
    if keep_recent is None or keep_recent < 0:
        return messages
    image_positions = []
    for i, msg in enumerate(messages):
        content = msg.get("content") if isinstance(msg, dict) else getattr(msg, "content", None)
        if isinstance(content, list) and any(
            isinstance(p, dict) and p.get("type") == "image_url" for p in content
        ):
            image_positions.append(i)
    drop = set(image_positions[:-keep_recent]) if keep_recent else set(image_positions)
    if not drop:
        return messages
    pruned = []
    for i, msg in enumerate(messages):
        if i not in drop:
            pruned.append(msg)
            continue
        content = msg.get("content")
        new_content = [
            p if not (isinstance(p, dict) and p.get("type") == "image_url")
            else {"type": "text", "text": "[older screenshot removed]"}
            for p in content
        ]
        pruned.append({**msg, "content": new_content})
    return pruned


# ---------------------------------------------------------------------------
# Rewards
# ---------------------------------------------------------------------------


async def task_reward(state: vf.State) -> float:
    """The benchmark's own reward.

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
# Dataset + entry point
# ---------------------------------------------------------------------------


def _build_dataset(
    env_names: list[str],
    split: str,
    surface: str,
    task_ids: list[str] | None,
    max_examples: int | None,
) -> Dataset:
    from benchmarks.cua_world.registry import (
        get_tasks_for_environment,
        resolve_environment_dir,
    )

    rows = []
    for env_name in env_names:
        env_dir = str(resolve_environment_dir(env_name))
        tasks = get_tasks_for_environment(env_name, split=split, surface=surface)
        for task_id in sorted(tasks):
            if task_ids and task_id not in task_ids:
                continue
            task_json_path = Path(env_dir) / "tasks" / task_id / "task.json"
            if not task_json_path.exists():
                continue
            task = json.loads(task_json_path.read_text())
            nl = task.get("natural_language")
            desc = (
                (nl.get("prompt") if isinstance(nl, dict) else nl)
                or task.get("description")
                or ""
            )
            if not desc:
                continue
            rows.append(
                {
                    "prompt": [{"role": "user", "content": desc}],
                    "info": {
                        "env_dir": env_dir,
                        "env_name": env_name,
                        "task_id": task_id,
                        "seed": 0,
                    },
                    "task": f"{env_name}/{task_id}",
                }
            )
    if not rows:
        raise ValueError(
            f"No tasks found for env_names={env_names} split={split!r} "
            f"surface={surface!r} task_ids={task_ids}"
        )
    if max_examples is not None:
        rows = rows[:max_examples]
    return Dataset.from_list(rows)


def load_environment(
    env_names: list[str] | str = "gimp_env",
    split: str = "all",
    surface: str = "raw",
    task_ids: list[str] | None = None,
    max_examples: int | None = None,
    runner: str = "modal",
    coordinate_mode: str = "norm1000",
    max_turns: int = 15,
    keep_recent_screenshots: int = 3,
    use_cache: bool = True,
    cache_level: str = "post_start",
    use_savevm: bool = False,
    verifier_mode: str | None = None,
    vlm_backend: str | None = None,
    vlm_model: str | None = None,
    vlm_base_url: str | None = None,
    vlm_api_key_var: str | None = None,
    **kwargs: Any,
) -> vf.Environment:
    """CUA-World computer-use environment.

    Args:
        env_names: benchmark environment name(s), e.g. "gimp_env" or
            ["gimp_env", "libreoffice_calc_env"].
        split: task split ("all", "train", "test", or a named split).
        surface: "raw" or "verified".
        task_ids: optional whitelist of task ids.
        max_examples: cap on dataset rows.
        runner: gym-anything runner ("modal" boots VMs on Modal cloud;
            "qemu_native"/"docker"/... run locally if the host supports them).
        coordinate_mode: "norm1000" (0-1000 normalized) or "pixel".
        max_turns: model-turn budget per rollout.
        keep_recent_screenshots: screenshots kept in context (older ones
            are replaced with placeholders to bound context growth).
        use_cache / cache_level / use_savevm: gym-anything checkpoint knobs.
        verifier_mode: override the task's success mode for every task, e.g.
            "vlm_checklist" to grade with a VLM against each task's
            vlm_checklist.json instead of its programmatic verifier.py.
            None keeps each task's declared mode (usually "program").
        vlm_backend / vlm_model / vlm_base_url: VLM grader config when
            verifier_mode="vlm_checklist". Use vlm_backend="local" with an
            OpenAI-compatible vlm_base_url to route to any provider (e.g.
            Prime Inference) with model like "google/gemini-3.5-flash".
        vlm_api_key_var: name of an env var holding the VLM API key (its
            value is read from the client env and forwarded to the grader).
    """
    if isinstance(env_names, str):
        env_names = [env_names]

    # Verifier/VLM config is delivered to the verifier (which runs inside the
    # runner's process) via gym-anything's env vars; the modal runner forwards
    # these into the sandbox shim.
    if verifier_mode:
        os.environ["GYM_ANYTHING_VERIFIER_MODE"] = verifier_mode
    if vlm_backend:
        os.environ["VLM_BACKEND"] = vlm_backend
    if vlm_model:
        os.environ["VLM_MODEL"] = vlm_model
    if vlm_base_url:
        os.environ["VLM_BASE_URL"] = vlm_base_url
    if vlm_api_key_var:
        key_val = os.environ.get(vlm_api_key_var, "")
        if key_val:
            os.environ["VLM_API_KEY"] = key_val

    dataset = _build_dataset(env_names, split, surface, task_ids, max_examples)
    rubric = vf.Rubric(
        funcs=[task_reward, verifier_passed, verifier_score, actions_executed, parse_errors],
        weights=[1.0, 0.0, 0.0, 0.0, 0.0],
    )
    return CuaWorldEnv(
        dataset=dataset,
        eval_dataset=dataset,
        rubric=rubric,
        tool_defs=[_make_computer_tool(coordinate_mode)],
        max_turns=max_turns,
        runner=runner,
        coordinate_mode=coordinate_mode,
        keep_recent_screenshots=keep_recent_screenshots,
        use_cache=use_cache,
        cache_level=cache_level,
        use_savevm=use_savevm,
        env_id="cua-world",
        env_args={
            "env_names": env_names,
            "split": split,
            "surface": surface,
            "task_ids": task_ids,
            "runner": runner,
            "coordinate_mode": coordinate_mode,
            "max_turns": max_turns,
            "verifier_mode": verifier_mode,
        },
        **kwargs,
    )
