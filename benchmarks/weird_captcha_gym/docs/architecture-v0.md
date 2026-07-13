# Weird CAPTCHA Gym Architecture v0

Date: 2026-07-08

This document fixes the benchmark architecture after collection freeze v0 and the 25-mechanic shortlist. The benchmark is a visual-puzzle stress test for computer-use agents, not a CAPTCHA-security benchmark.

## Source Inputs Read

- Gym-Anything paper: `research/_papers/gym-anything/gym-anything-2604.06126.pdf` and extracted text in `research/_papers/gym-anything/gym-anything-2604.06126.txt`.
- Gym-Anything project page and API examples.
- Official Gemini API Computer Use documentation for Gemini 3.5 Flash, especially the execution loop, normalized coordinates, and shared browser/mobile/desktop action commands.

## Locked Design Decisions

- All 25 shortlisted mechanics are in scope. We are not reducing the set to a 5-10 mechanic prototype pack.
- There is one common infrastructure, modeled after Gym-Anything. Mechanics do not get their own runners, APIs, or grouped harnesses.
- Allowed actions are identical across tasks. A moving checkbox, a chess CAPTCHA, a terminal escape, a tracing task, and a video-memory task all expose the same computer-use action surface.
- Task cards define puzzle content, generator knobs, ground truth, and outcome verification. They must not define per-task action subsets.
- Scoring is outcome-first. Trajectories are logged for debugging, training data, and benchmark-integrity checks, but normal scoring should not grade the agent's process.
- Claims in prior work that older GUI agents fail a task family are not treated as evidence about current July 2026 computer-use agents. Difficulty must be measured directly.

## Gym-Anything Mapping

Gym-Anything frames a task as `T = (E_s0, p, V)`: an environment with initial state, a natural-language instruction, and a verifier. This benchmark uses the same split inside the Gym-Anything fork, under `benchmarks/weird_captcha_gym/`.

- `E`: one of the 25 mechanic environments, each represented as a normal Gym-Anything environment folder under `benchmarks/weird_captcha_gym/environments/<mechanic>_env/`.
- shared software: a common puzzle browser/runtime mounted into every mechanic environment. The runner, observation capture, action injection, trajectory logging, and verifier dispatch remain Gym-Anything's responsibility.
- `s0`: the live generated puzzle state for one mechanic.
- `p`: the instruction shown to the agent and/or embedded in the puzzle UI.
- `V`: an outcome verifier that uses hidden ground truth from generation.

The important adaptation is that "software" is not the real unit of variation. The software is one puzzle runtime. The variation lives in task setup and runtime generation: `mechanic_id`, assets, UI state, prompt, and verifier metadata.

## Runtime Shape

The benchmark should be used through Gym-Anything's existing loader and runner stack:

```python
from gym_anything import from_config

env = from_config(
    "benchmarks/weird_captcha_gym/environments/relation_prompt_grounding_env",
    task_id="relation_prompt_grounding_seed_0001",
)
obs = env.reset(seed=812381, use_cache=True, cache_level="post_start")

for _ in range(max_steps):
    action_group = agent.act(obs["screen"], instruction=env.task_spec.natural_language)
    obs, reward, done, info = env.step(action_group)
    if done:
        break

env.close()
```

`reset()` starts the selected runner, executes env hooks, executes the task `pre_task` hook, and returns the first screenshot. `step()` injects one or more common Gym-Anything actions and returns the next screenshot. Verification runs when the episode is completed or closed.

## Observation Surface

The benchmark-native public observation should be minimal and CUA-like:

- `screen`: RGB screenshot of the current puzzle viewport.
- `instruction`: the natural-language task instruction when the harness, rather than the UI, provides it.
- `elapsed_ms` or `step_index`: optional public timing metadata only if exposed consistently to every task.

Hidden metadata must be kept out of the agent context:

- `mechanic_id`
- seed
- generator parameters
- object masks
- answer labels
- target coordinates
- intermediate ground truth
- verifier rubric

## Common Action Space

Every task uses the same Gym-Anything mouse/keyboard action surface. Task specs must not introduce per-mechanic action subsets.

Core actions are runner-level nested dictionaries:

```json
{"mouse": {"left_click": [450, 120]}}
{"mouse": {"double_click": [450, 120]}}
{"mouse": {"triple_click": [450, 120]}}
{"mouse": {"right_click": [450, 120]}}
{"mouse": {"move": [450, 120]}}
{"mouse": {"left_click_drag": [[100, 500], [800, 500]]}}
{"mouse": {"scroll": 3}}
{"keyboard": {"text": "answer"}}
{"keyboard": {"keys": ["ctrl", "a"]}}
{"action": "wait", "seconds": 1}
{"action": "screenshot"}
```

Adapter notes:

- If an external model surface provides normalized coordinates, the agent adapter should convert them to the active Gym-Anything screenshot resolution before calling `env.step()`.
- If an external model surface provides an `intent` field, preserve it in agent logs if useful but ignore it for execution.
- If a model exposes `take_screenshot`, map it to Gym-Anything's control action `{"action": "screenshot"}` or rely on the screenshot returned after each step.
- Do not exclude or add actions for individual mechanics. Unsupported behavior should fail naturally because the UI does not respond, not because the harness secretly changes the action set.

## Task Directory Shape

Target layout:

```text
benchmarks/weird_captcha_gym/
  shared_runtime/
    app/
    server/
    mechanics/
  shared_scripts/
    install_puzzle_runtime.sh
    setup_puzzle_runtime.sh
    setup_task.py
    export_result.sh
  environments/
    reverse_identity_gate_env/
      env.json
      scripts/
        install_puzzle_runtime.sh
        setup_puzzle_runtime.sh
      tasks/
        reverse_identity_gate_seed_0001/
          task.json
          setup_task.sh
          export_result.sh
          verifier.py
          seeds/
          evidence/
    moving_checkbox_evasive_button_env/
      ...
```

This follows the Gym-Anything separation:

- install/configure scripts are shared by all mechanic environments, with thin per-env wrappers if needed.
- task setup varies by mechanic and task metadata; live CAPTCHA-style mechanics may randomize the concrete challenge on each page load.
- verifiers are decoupled from the runner.
- artifacts are emitted in a consistent episode directory.

## Task Spec Contract

Each mechanic should expand into a task spec with these fields:

- `mechanic_id`: stable ID from `mechanic-shortlist-v0.md`.
- `source_anchors`: collection source folders motivating the mechanic.
- `instruction_templates`: natural-language prompts visible to the agent.
- `generator_contract`: randomness policy, difficulty knobs, asset requirements, and answer-generation rules.
- `public_state`: what the UI renders.
- `private_ground_truth`: hidden answer data produced by generation.
- `verifier_contract`: final-state/outcome checks and scoring tolerance.
- `timeouts`: max steps and, if needed, wall-clock limits.
- `failure_modes_targeted`: expected stress points for analysis, not scoring.
- `evidence_required`: screenshots, ground-truth JSON, generated assets, and a known-solved trace or manual solve note.

No field named `allowed_actions` should exist in task specs.

## Generator And Verifier Contract

Preferred procedural interface:

```ts
type GeneratedTask = {
  mechanicId: string;
  challengeId: string;
  instruction: string;
  publicState: unknown;
  privateGroundTruth: unknown;
  assets: Record<string, string>;
  verifierConfig: unknown;
};

function generateTask(difficulty: string): GeneratedTask;
function verifyOutcome(finalState: unknown, groundTruth: unknown, config: unknown): VerificationResult;
```

The verifier should normally be programmatic because generated puzzles can emit exact ground truth. VLM verification can be a fallback for mechanics whose intended answer is visual but hard to encode, but the first design pass should try hard to avoid VLM-only grading.

## Episode Artifacts

Every run should rely on Gym-Anything's episode directory as the source of truth:

- `traj.jsonl`: timestamped reset/action events.
- `frame_00000.png`, `frame_00001.png`, etc.
- `final.png` and `post_verification.png`.
- `summary.json`: score, pass/fail, step count, timing, verifier feedback.
- `recording.mp4`: optional when recording is enabled.

The puzzle runtime should additionally write guest-side task state:

- `/tmp/weird_captcha_gym/public_state.json`
- `/tmp/weird_captcha_gym/ground_truth.json`
- `/tmp/weird_captcha_gym/result.json`
- `/tmp/task_result.json`, exported by `post_task` for Gym-Anything verifier compatibility.

These artifacts are not process grading by default. They exist so failures can be debugged, verifiers can be audited, and future training data can be extracted.

## Integrity Policy

Outcome grading is the normal score. Integrity checks only invalidate runs when the benchmark harness itself was bypassed or contaminated, for example:

- the agent reads `ground_truth.json`;
- the agent calls a private API unavailable through the computer-use surface;
- the runner fails to reset to the intended task/runtime state;
- screenshots or logs are missing, making the run unverifiable;
- the environment crashes in a way unrelated to agent behavior.

This is different from grading whether the agent used a "good" process. We do not penalize weird but valid solution strategies if they operate through the shared action surface and reach the correct outcome.

## Creation And Audit Loop

Adapt the Gym-Anything creation-audit loop to puzzle mechanics:

1. Builder writes the generator, verifier, task spec, and evidence for a mechanic.
2. Builder produces several sampled examples plus at least one known-solved run or manual solve note.
3. Auditor checks task clarity, start-state evidence, randomness policy, answer non-leakage, verifier correctness, and artifact completeness.
4. Auditor treats comments and prose claims as untrusted; screenshots, generated ground truth, and repeated live runs are stronger evidence.
5. Mechanic is accepted only when generation, rendering, and verification are robust across fresh random challenge instances.

Audit criteria should include "not artificially hard." The puzzle can be hostile, funny, and annoying, but it should not rely on arbitrary pixel-perfect tolerances, impossible timing, unreadable prompts, or long chains of trivial repeated actions unless that is the actual mechanic being studied.

## Implementation Order

All 25 mechanics remain the target, but runner plumbing is not the same thing as benchmark quality. The reverse-identity and moving-checkbox pilots proved the AVF/browser/export/verifier path and are now explicitly rejected as benchmark tasks.

Recommended sequence:

1. Keep `shared_runtime/` and `shared_scripts/` as common infrastructure.
2. Build real generation pipelines with provenance and live runtime randomization. `surreal_apple_on_tree_grid_env` covers a dynamic semantic image-grid candidate; `cursor_lens_reveal_env` covers a mouse-driven reveal candidate; `modifier_stack_image_grid_env` covers a harder corrupted-recognition grid candidate; `semantic_drag_drop_absurdity_env`, `reload_interruption_env`, `rotate_wrong_thing_upright_env`, `bureaucratic_signature_trap_env`, `wonky_text_hostile_rendering_env`, and `temporal_memory_first_change_env` cover the first source-grounded non-grid candidates.
3. Make the visible UI CAPTCHA-like: prompt, selectable surface, `PASS`, and `FAIL` only.
4. Run it through Gym-Anything reset/step/close so screenshots, trajectory logging, `post_task`, and verifier dispatch are exercised for real.
5. Promote only after the per-task quality audit passes and AVF evidence includes first screen, failed retry, and passing verifier run.
6. Fill in the remaining mechanics after the first one survives that stricter bar.
