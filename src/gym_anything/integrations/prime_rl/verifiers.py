"""Gym-anything environments as Prime Intellect `verifiers` environments.

Prime-rl serves the policy over an OpenAI-compatible endpoint and OWNS the
sampling loop: it calls `env.rollout(client=<policy>, ...)` and trains on the
tokens the policy generates. The environment never makes its own model call.

So this adapter runs a **real reference agent's `step()` verbatim** — the
same class you select locally with `--agent` (e.g. `Qwen3VLAgent`) — with
exactly one substitution: the agent's model call (`self.llm_call`, see
`BaseAgent.llm_call`) is a bridge that suspends `step()`, hands the messages
the agent just built to the framework as the turn's prompt, and resumes
`step()` with the completion the framework sampled. Message construction,
history management, screenshot handling, and parsing are therefore the
agent's own code — the local harness and the driven harness cannot diverge
because they are the same lines (`tests/test_agent_driver_parity.py` pins
this).

Because the agent rebuilds its prompt each turn (e.g. windowed history),
each trajectory step carries its own prompt. For training, use prime-rl's
`trajectory_strategy = "branching"` with windowed agents; agents whose
prompts grow append-only work with `"interleaved"` as well.

Only agents marked drivable (`driven = True`, OpenAI-message `llm_call`
seam) can be run this way; provider-native agents (Anthropic/Google native
tools) cannot be served over an OpenAI policy endpoint and are rejected.

Dataset rows come from `hub.build_task_rows`. Requires the `prime-rl` extra.
"""

from __future__ import annotations

import asyncio
import base64
import json
import queue
import tempfile
import threading
import traceback
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import verifiers as vf
from datasets import Dataset

DEFAULT_RESOLUTION = (1920, 1080)

_BRIDGE_ABORT = object()


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
            f"Pick an OpenAI-compatible agent (routes its model call through llm_call): "
            f"{', '.join(drivable)}."
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


def _completion_text(completion: Any) -> str:
    """Assistant text from a sampled completion (message list, dict, or str)."""
    if isinstance(completion, str):
        return completion
    if isinstance(completion, list):
        return "".join(_completion_text(m) for m in completion)
    content = getattr(completion, "content", None)
    if content is None and isinstance(completion, dict):
        content = completion.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text"
        )
    return str(content or "")


def _role(message: Any) -> Optional[str]:
    """Role of an OpenAI-style message (dict) or a vf.Message object."""
    if isinstance(message, dict):
        return message.get("role")
    return getattr(message, "role", None)


class RolloutAborted(Exception):
    """Raised inside the agent thread when the rollout is torn down."""


class _StepBridge:
    """Suspends the agent's model call so the framework can sample.

    agent thread                         async rollout loop
    ------------                         ------------------
    llm_call(messages) --requests-->     get_prompt_messages -> turn prompt
      blocks                             framework samples the policy
      returns text   <--completions--    send_completion(text)

    The agent thread ends by putting a ("finished", error_or_None) request.
    """

    def __init__(self, call_timeout: float = 3600.0):
        self._requests: "queue.Queue" = queue.Queue()
        self._completions: "queue.Queue" = queue.Queue()
        self._call_timeout = call_timeout
        self.actions_executed = 0
        self.parse_errors = 0
        # Sampling params the agent passed to its model call, so the framework
        # samples with exactly what the agent specified (see _sampling_args_from_call).
        self.sampling_args: Dict[str, Any] = {}

    # -- agent-thread side --------------------------------------------------

    def llm_call(self, messages, *args: Any, **kwargs: Any) -> str:
        if not self.sampling_args:
            self.sampling_args = _sampling_args_from_call(args, kwargs)
        self._requests.put(("messages", messages))
        item = self._completions.get(timeout=self._call_timeout)
        if item is _BRIDGE_ABORT:
            raise RolloutAborted()
        return item

    def finish(self, error: Optional[str] = None) -> None:
        self._requests.put(("finished", error))

    # -- rollout-loop side ---------------------------------------------------

    def next_request(self, timeout: float = 1800.0) -> Tuple[str, Any]:
        return self._requests.get(timeout=timeout)

    def send_completion(self, text: str) -> None:
        self._completions.put(text)

    def abort(self) -> None:
        self._completions.put(_BRIDGE_ABORT)


def _sampling_args_from_call(args: tuple, kwargs: dict) -> Dict[str, Any]:
    """Translate the arguments an agent passed to ``llm_call`` into verifiers
    sampling_args, using ``call_llm``'s signature as the single source of truth.

    The seam contract is that ``self.llm_call`` is a ``call_llm``-compatible
    callable, so the positional args after ``messages`` mean
    ``(model, temperature, top_p, top_k, max_tokens, repetition_penalty)``.
    We map them the exact way ``call_llm`` maps them onto the OpenAI call
    (temperature/top_p/max_tokens at top level, top_k/repetition_penalty in
    ``extra_body``), so a driven rollout samples with the same params the agent
    would have used locally — for any agent, with no per-agent code.
    """
    import inspect

    from agents.shared.llm_clients import call_llm

    params = list(inspect.signature(call_llm).parameters.values())[1:]  # drop messages
    bound: Dict[str, Any] = {}
    for i, p in enumerate(params):
        if i < len(args):
            bound[p.name] = args[i]
        elif p.name in kwargs:
            bound[p.name] = kwargs[p.name]
        elif p.default is not inspect.Parameter.empty:
            bound[p.name] = p.default

    sampling: Dict[str, Any] = {}
    for key in ("temperature", "top_p", "max_tokens"):
        if bound.get(key) is not None:
            sampling[key] = bound[key]
    extra: Dict[str, Any] = {}
    for key in ("top_k", "repetition_penalty"):
        if bound.get(key) is not None:
            extra[key] = bound[key]
    if extra:
        sampling["extra_body"] = extra
    return sampling


def _localize_screen(env: Any, obs: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Ensure obs['screen']['path'] is a local file, as agents expect."""
    screen = (obs or {}).get("screen") or {}
    path = screen.get("path")
    if path and screen.get("remote"):
        screen["path"] = env.fetch_path(path)
        screen.pop("remote", None)
    elif not path and screen.get("png_b64"):
        tmp = Path(tempfile.mkdtemp()) / "screen.png"
        tmp.write_bytes(base64.b64decode(screen["png_b64"]))
        screen["path"] = str(tmp)
    return obs


def _episode_loop(env: Any, agent: Any, bridge: _StepBridge, first_obs: Any) -> None:
    """The local evaluation loop, verbatim (mirrors run_single's inner loop).

    Runs on a worker thread. The only difference from a local run is that
    agent.step()'s model call suspends on the bridge instead of hitting a
    client. Keep this in lockstep with agents/evaluation/run_single.py; the
    parity test compares the two.
    """
    error: Optional[str] = None
    try:
        obs = _localize_screen(env, first_obs)
        action_outputs: List[Dict[str, Any]] = []
        while not agent.done:
            actions = agent.step(obs, action_outputs)
            action_outputs = []
            done = False
            for action in actions or []:
                obs, _reward, done, info = env.step(action.get("actions") or [])
                obs = _localize_screen(env, obs)
                action_result = (info or {}).get(
                    "action_result",
                    {"action": "other", "output": "Executed the action"},
                )
                action_outputs.append({**action_result, "tool_id": action.get("tool_id")})
                bridge.actions_executed += len(action.get("actions") or [])
                metadata = action.get("metadata") or {}
                if metadata.get("parse_error"):
                    bridge.parse_errors += 1
            if done:
                break
    except RolloutAborted:
        return
    except Exception:
        error = traceback.format_exc()[-2000:]
    finally:
        bridge.finish(error)


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
        state["episode_reward"] = 0.0
        state["verifier"] = {"error": f"{e}"}
        state["finalize_error"] = traceback.format_exc()[-2000:]


def _surface_verifier_info(state: "vf.State") -> None:
    """Persist the verifier's full verdict into ``state["info"]``.

    ``state["info"]`` is always serialised into the saved rollout output
    (``state_to_output``), unlike arbitrary state keys, so this makes the score
    breakdown and reasoning visible in the eval samples/dashboard instead of
    being computed and dropped. Logging-only; does not touch the reward.
    """
    verifier = state.get("verifier") or {}
    scores = verifier.get("scores") or {}
    info = state.get("info")
    if not isinstance(info, dict):
        info = {}
    info["verifier"] = {
        "score": verifier.get("score"),
        "passed": verifier.get("passed"),
        "completion_score": scores.get("score_a"),
        "integrity_passed": scores.get("score_b"),
        "integrity_pass_rate": scores.get("integrity_pass_rate"),
        "completion_details": scores.get("completion_details"),
        "integrity_details": scores.get("integrity_details"),
        "feedback": verifier.get("feedback"),
        "error": verifier.get("error"),
    }
    state["info"] = info


class GymAnythingAgentEnv(vf.MultiTurnEnv):
    """verifiers MultiTurnEnv that runs a real reference agent's step()."""

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

    def _boot(self, info: Dict[str, Any]) -> Tuple[Any, Any]:
        env_dir = info["env_dir"]
        task_id = info["task_id"]
        if self.remote_url:
            from ...remote.client import RemoteGymEnv

            env = RemoteGymEnv.from_config(
                self.remote_url,
                env_dir,
                task_id=task_id,
                verifier_env=(self.verifier_overrides or None),
            )
        else:
            from ...config.loading import from_config

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
        return env, obs

    # -- verifiers hooks -----------------------------------------------------

    async def setup_state(self, state: vf.State) -> None:
        info = state.get("info", {})
        task_description = _task_text(state.get("prompt"))
        env, obs = await asyncio.to_thread(self._boot, dict(info))
        state["ga_env"] = env
        state["actions_executed"] = 0
        state["parse_errors"] = 0

        screen = (obs or {}).get("screen") or {}
        resolution = tuple(screen.get("resolution") or DEFAULT_RESOLUTION)

        bridge = _StepBridge()
        agent = _make_agent(self.agent_name, self.agent_args)
        agent.llm_call = bridge.llm_call  # the one substitution vs a local run
        agent.init(
            task_description=task_description,
            display_resolution=resolution,
            save_path=str(getattr(env, "episode_dir", ".") or "."),
        )
        state["agent"] = agent
        state["bridge"] = bridge

        thread = threading.Thread(
            target=_episode_loop, args=(env, agent, bridge, obs), daemon=True
        )
        state["agent_thread"] = thread
        thread.start()

        # The opening prompt is whatever the agent's own step() builds for
        # its first model call — the framework samples from exactly that.
        event, payload = await asyncio.to_thread(bridge.next_request)
        if event == "finished":
            state["finalize_error_loop"] = payload or "agent finished before first model call"
            await asyncio.to_thread(_finalize_episode, state)
            state["final_env_response"] = [{"role": "user", "content": "Episode terminated."}]
            return
        state["prompt"] = payload

        # Sample with the params the agent passed to its own model call, so a
        # driven rollout matches a local run. state is per-rollout (no race);
        # anything the framework/caller set explicitly (e.g. a prime-rl training
        # sampling config) wins per-key, so training keeps control.
        agent_sampling = bridge.sampling_args
        if agent_sampling:
            caller = dict(state.get("sampling_args") or {})
            merged = {**agent_sampling, **caller}
            merged_extra = {
                **agent_sampling.get("extra_body", {}),
                **(caller.get("extra_body") or {}),
            }
            if merged_extra:
                merged["extra_body"] = merged_extra
            state["sampling_args"] = merged

    async def get_prompt_messages(self, state: vf.State) -> "vf.Messages":
        if not state["trajectory"]:
            return state["prompt"]

        bridge: _StepBridge = state["bridge"]

        # Enforce the model-turn budget ourselves: resume the agent only if
        # budget remains, otherwise terminate and score.
        if self.max_turns > 0 and len(state["trajectory"]) >= self.max_turns:
            state["is_truncated"] = True
            return await self._terminate(state)

        # Resume the suspended step() with the completion the framework
        # sampled; the agent parses and acts, then either requests the next
        # model call (its next turn's messages) or finishes.
        completion = state["trajectory"][-1]["completion"]
        bridge.send_completion(_completion_text(completion))
        event, payload = await asyncio.to_thread(bridge.next_request)
        state["actions_executed"] = bridge.actions_executed
        state["parse_errors"] = bridge.parse_errors
        if event == "messages":
            return payload
        if payload:
            state["finalize_error_loop"] = payload
        return await self._terminate(state)

    async def env_response(
        self, messages: "vf.Messages", state: vf.State, **kwargs: Any
    ) -> "vf.Messages":
        raise NotImplementedError(
            "unused: get_prompt_messages is overridden; each turn's messages "
            "come from the agent's own step()"
        )

    async def render_completion(self, state: "vf.State") -> None:
        """Record the FULL multi-turn trajectory, not just the last windowed turn.

        verifiers' default ``render_completion`` serialises only
        ``state["trajectory"][-1]`` because it assumes append-only prompts. Our
        agent rebuilds a windowed prompt each turn, so the default drops every
        prior screenshot and action, leaving a single-turn log. Every turn is
        already in ``state["trajectory"]``; stitch each turn's new observation
        (the trailing user message of its windowed prompt) and action into one
        conversation so the recorded completion is the whole episode.

        Logging-only: this runs from a ``@cleanup`` handler after the rollout, so
        it never feeds the agent, and it does not affect the reward (which comes
        from the env verifier via ``state["episode_reward"]``).
        """
        traj = state.get("trajectory") or []
        if not traj:
            state["completion"] = []
            return
        # Turn 0's action answers the observation already carried by state["prompt"].
        conversation: List[Any] = list(traj[0]["completion"])
        for step in traj[1:]:
            user_msgs = [m for m in step["prompt"] if _role(m) == "user"]
            conversation += user_msgs[-1:] + list(step["completion"])
        final_resp = state.get("final_env_response")
        if final_resp:
            conversation += final_resp if isinstance(final_resp, list) else [final_resp]
        state["completion"] = conversation

    async def _terminate(self, state: vf.State) -> "vf.Messages":
        """Score while the VM is alive, then signal rollout completion."""
        await asyncio.to_thread(_finalize_episode, state)
        state["final_env_response"] = [{"role": "user", "content": "Episode terminated."}]
        # Never sampled from: the rollout loop skips sampling once
        # final_env_response is set. Return the last prompt as a placeholder.
        return state["trajectory"][-1]["prompt"] if state["trajectory"] else state["prompt"]

    @vf.cleanup(priority=50)
    async def finalize_reward(self, state: vf.State) -> None:
        """Score with the real verifier while the VM is alive (before close)."""
        await asyncio.to_thread(_finalize_episode, state)
        _surface_verifier_info(state)

    @vf.cleanup(priority=0)
    async def close_env(self, state: vf.State) -> None:
        bridge: Optional[_StepBridge] = state.pop("bridge", None)
        if bridge is not None:
            bridge.abort()
        thread: Optional[threading.Thread] = state.pop("agent_thread", None)
        if thread is not None and thread.is_alive():
            await asyncio.to_thread(thread.join, 30.0)
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


async def verifier_completion(state: vf.State) -> float:
    """Checklist completion score (0-100), before the integrity gate is applied."""
    return float(((state.get("verifier") or {}).get("scores") or {}).get("score_a") or 0.0)


async def verifier_integrity(state: vf.State) -> float:
    """1.0 if every integrity check passed, else 0.0. A 0 here hard-zeros the score
    even when verifier_completion is high (integrity_threshold is all-or-nothing)."""
    return 1.0 if ((state.get("verifier") or {}).get("scores") or {}).get("score_b") else 0.0


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
    """Build a verifiers Environment that runs a real reference agent.

    Args:
        rows: dataset rows (`prompt`/`info`/`task`), from `hub.build_task_rows`.
        agent: reference agent class name, exactly as `--agent` locally
            (e.g. "Qwen3VLAgent"). Must be drivable (llm_call seam).
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
        funcs=[
            task_reward,
            verifier_passed,
            verifier_score,
            verifier_completion,
            verifier_integrity,
            actions_executed,
            parse_errors,
        ],
        weights=[1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
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
