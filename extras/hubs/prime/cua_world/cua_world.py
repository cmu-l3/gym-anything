"""CUA-World on the Prime Intellect Environments Hub.

Pure declaration. Prime-rl owns the sampling loop; this environment drives a
real reference agent from `agents/agents/` (selected by name, exactly like
`--agent` locally) and reuses that agent's own system prompt and parser. All
logic lives in the gym-anything library:
  * dataset enumeration — `gym_anything.registry`
  * rollout that drives the agent — `gym_anything.integrations.verifiers`
  * the `load_environment` surface — `gym_anything.integrations.hub`
  * the agent itself — `agents/agents/qwen3vl.py`

Defaults mirror how you would run this locally:
  * `agent="Qwen3VLAgent"` + `agent_args` — the OpenAI-compatible vision agent,
    the same class `--agent Qwen3VLAgent` selects. It drives any vision model
    served over an OpenAI-compatible endpoint (the policy under prime-rl, or
    e.g. gemini via Google's OpenAI endpoint).
  * `verifier_mode="vlm_checklist"` — grade against each task's
    vlm_checklist.json with a VLM, not the per-task programmatic verifier.

Usage:
    vf-eval cua-world -m gemini-3.5-flash \
        -b https://generativelanguage.googleapis.com/v1beta/openai/ \
        -k GEMINI_API_KEY -n 1 -r 1 \
        -a '{"env_names": ["gimp_env"], "task_ids": ["horizontal_mirror"]}'
"""

from gym_anything.integrations.hub import make_hub_loader

load_environment = make_hub_loader(
    "cua_world",
    env_id="cua-world",
    env_names="gimp_env",
    runner="modal",
    # Drive a real reference agent by name, exactly like --agent locally.
    agent="Qwen3VLAgent",
    agent_args={"model": "gemini-3.5-flash", "temperature": 1.0},
    # Grade with the VLM checklist: the programmatic verifiers read a live,
    # agent-mutable ground-truth file, so an agent that saves over the original
    # destroys the baseline. The VLM judges the trajectory instead.
    verifier_mode="vlm_checklist",
    vlm_backend="local",
    vlm_base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
    vlm_model="gemini-3.5-flash",
    vlm_api_key_var="GEMINI_API_KEY",
)
