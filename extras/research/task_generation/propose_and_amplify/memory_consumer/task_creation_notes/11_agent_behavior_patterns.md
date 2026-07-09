> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Agent Behavior Patterns and Task Design Implications

## Overview

Designing tasks for AI agents is fundamentally different from designing tasks for human users. Human users tolerate ambiguity, know how to search efficiently, and commit to decisions under uncertainty. AI agents frequently exhibit distinct failure modes that are entirely unrelated to their knowledge of the application — they are emergent properties of how agents reason under uncertainty. This document catalogs observed failure patterns and translates them into concrete task design decisions.

These patterns were derived from empirical trajectory analysis across multiple environments and are intended to be general, not environment-specific.

---

## Failure Pattern 1: The Search Loop

**What it looks like**: The agent correctly identifies what needs to be done, correctly navigates to the right tool or module, then enters an endless loop: scrolling through data, cycling through records, or panning around a canvas — looking for the "perfect" starting position, the "right" slice, or the "correct" record — without ever committing to an action. All available steps are consumed by this search, and the core task is never executed.

**Why it happens**: Agents have calibrated uncertainty about spatial, anatomical, or domain-specific judgments. When a task requires them to select a specific position or record but the selection criterion is inherently continuous (e.g., "the level of maximum diameter," "the frame with the best lighting," "the record with the most severe anomaly"), the agent keeps searching because no option is decisively better than the others. The agent lacks the commitment heuristic that professionals acquire through training.

**Affected task types**: Any task requiring the agent to find an optimal or "correct" position in a continuous space (image slices, animation frames, graph nodes, document sections), or to choose among records where all appear roughly equivalent.

### Task Design Response

1. **Pre-position the environment so the correct target is already visible at task start.**

   If the task is "measure the aorta diameter at the correct level," pre-scroll the volume to the correct axial level in `setup_task.sh` before the agent's session begins. The task's difficulty comes from *knowing how to measure* and *using the correct tool* — not from finding the slice. Conflating these challenges causes agents to spend all steps on the unintended part.

   ```bash
   # Example: pre-set a viewer to a specific slice before agent session
   # (use the app's scripting API or state file to pre-load the correct view)
   ```

2. **Bound the search space explicitly in the task description.**

   If the agent must locate a target, give a meaningful constraint: "the record with the highest `error_count`," "the frame at timestamp 00:04:22," "the entry dated 2024-03-15." This is not the same as handing the agent a recipe — it eliminates the open-ended search while preserving the judgment required to act on the target.

3. **Separate discovery tasks from execution tasks.**

   If the discovery component (finding the right target) is not itself the point of the task, remove it from the agent's burden. If it IS the point, treat it as a distinct subtask with its own step budget in your complexity estimate.

4. **Use a fixed reference, not a "best" judgment, when possible.**

   "Measure the width at the center slice" is easier to execute correctly than "measure the width at the optimal diagnostic level." If the professional workflow genuinely uses a canonical reference (standard anatomical landmarks, specified frame numbers, indexed records), use that in the task.

---

## Failure Pattern 2: Prepatory Overconsumption

**What it looks like**: The agent spends the majority of its step budget on legitimate but non-essential preliminary actions — opening menus, reading help text, configuring preferences, taking screenshots for "reference" — before reaching the core task action. By the time the agent attempts the primary goal, only a few steps remain, and the task is left incomplete.

**Why it happens**: Agents that have not seen the application before (which is always true in a benchmark) treat each screen as novel and tend to read/inspect everything before acting. They also hedge against uncertainty by doing thorough "reconnaissance" before committing.

### Task Design Response

1. **Set `max_steps` based on agent overhead, not the ideal professional path.**

   A professional user might complete a hard task in 12 actions. An agent unfamiliar with the application will spend 8-15 additional steps on navigation reconnaissance, reading menus, and recovery from minor wrong-clicks. Estimate `max_steps` as:

   ```
   max_steps ≈ (ideal_path_steps × 2.5) + (number_of_distinct_features_used × 5)
   ```

   For a hard task that a professional would finish in 20 steps, a reasonable `max_steps` is 50-60. For very_hard tasks, scale even higher.

2. **Set `timeout_sec` generously for GUI-heavy tasks.**

   Vision-language agents take 2-5 seconds per step (screenshot + reasoning + action). For a task with `max_steps=60`, allocate at least `timeout_sec = max_steps × 8 = 480` seconds. Tasks with heavy file operations (loading large data files, running computations) need even more.

3. **Ensure the application opens directly to a useful starting state.**

   If the task starts with the agent at an application's welcome/splash screen, the first 3-5 steps are always consumed by dismissing the splash, navigating to the right module, and orienting. Either design the task to account for this overhead, or configure `setup_task.sh` to dismiss first-run dialogs and navigate to the task-relevant module before the agent starts. (See also Lesson 37 in `05_learnings_best_practices.md`.)

---

## Failure Pattern 3: Preference for "Safe" Reversible Actions

**What it looks like**: When the agent must take an action that is difficult to undo (clicking "Submit," saving a file that overwrites a previous one, deleting a record, committing a transaction), it delays or avoids the action — instead performing more reversible preparatory steps, re-reading the task description, taking additional screenshots, or attempting an "undo" action that wasn't needed.

**Why it happens**: Agents have a learned bias toward caution that can be appropriate in general settings but counter-productive in benchmark tasks where the goal is precisely to perform the irreversible action.

### Task Design Response

1. **Make the success state clearly distinct from any default state.**

   Agents are more likely to commit when they can visually confirm the action was necessary. If the "before" and "after" states look identical except for a small detail, agents may conclude the action wasn't needed. Make the final state visually distinct (a new record appearing in a table, a file appearing on the desktop, a clearly changed value in a field).

2. **Do not require the agent to make a binary "are you sure?" decision at the critical step.**

   Tasks that force the agent to click a confirmation dialog ("Are you sure you want to delete? [Yes] [No]") add an extra layer of hesitation. If confirmation dialogs are unavoidable, note in the task description that confirming the action is required.

3. **Prefer "create" over "delete" for tasks where both options exist.**

   An agent adding a new record can always undo by deleting; an agent deleting a record may be overly cautious about irreversibility. Create/add tasks also give cleaner verification signals (baseline count → new count).

---

## The Pre-Positioning Principle

The empirical observation across multiple trajectory analyses is:

> **The single biggest predictor of task success is whether the target data is already visible to the agent when the task begins.**

When agents start with the target already on screen — the correct record open, the right module active, the relevant file loaded — they act decisively. When agents must first search for the target, they often get stuck before the actual work begins.

This principle is NOT about making tasks easier. It is about separating two distinct challenges:
- **Finding** the right target (discovery)
- **Acting** on the target (execution)

A hard task can require both, but the task creator should make a deliberate choice about which is the intended challenge. Accidentally combining both (where the finding is not intended to be hard but consumes most of the step budget anyway) produces tasks that test the wrong capability.

### Application

| Task Type | Recommended Initial State |
|-----------|--------------------------|
| "Fix the errors in patient X's record" | Patient X's record is already open |
| "Measure the aorta at level Y" | Volume is pre-scrolled to level Y |
| "Export records matching filter Z" | Filter Z is not pre-applied (filter setup IS the task) |
| "Find which patient has anomaly A and fix it" | No pre-positioning — discovery IS the task |
| "Refactor class X in file Y" | File Y is open in the editor on class X |

---

## Calibrating Step Count and Timeout

### Step Count (`max_steps`)

| Difficulty | Ideal path steps (professional) | Recommended `max_steps` |
|------------|--------------------------------|------------------------|
| Easy       | 5-10                           | 20-25                  |
| Medium     | 10-20                          | 35-45                  |
| Hard       | 20-35                          | 50-70                  |
| Very Hard  | 35-50                          | 70-100                 |

The multiplier accounts for: navigation overhead (~3-5 steps per distinct UI area), wrong-click recovery (~2-3 steps per mistake), and re-reading/orienting (~1-2 steps per decision point).

**Do not set `max_steps` to the ideal professional path.** Benchmark tasks are not testing speed — they are testing capability. A step budget that only allows the ideal path guarantees failure for any agent that takes even one wrong turn.

### Timeout (`timeout_sec`)

A practical formula:

```
timeout_sec = max_steps × 8   (for typical GUI tasks)
timeout_sec = max_steps × 15  (for tasks with heavy computation, large file loading, or slow app startup)
```

Minimum recommended: 300 seconds (5 minutes) for any task regardless of step count.

---

## Design Self-Check: Stress-Testing Against Agent Failure Modes

Before finalizing a task, walk through these questions:

1. **Could an agent loop at any step?**
   Identify every step that requires the agent to choose between roughly-equivalent options (which record? which level? which row?). For each: is the choice bounded? If not, add a constraint or pre-position the environment.

2. **How many steps does the "reconnaissance" phase consume?**
   If a new agent would spend 15+ steps just orienting to the application before attempting the task, either increase `max_steps` or configure `setup_task.sh` to pre-navigate to the task-relevant starting point.

3. **Is there a "point of no return" in the task?**
   If yes (a confirmation dialog, a final submit button, an irreversible delete), note explicitly in the task description that committing this action is required. Remove ambiguity about whether the agent should actually do it.

4. **Does the initial screenshot show something actionable?**
   After running `setup_task.sh`, look at the start screenshot saved to `/tmp/task_start_screenshot.png`. If the screenshot shows a welcome/splash screen, an empty state, or a screen with no obvious connection to the task, the agent will have to spend steps just getting to the right starting point. Ask: is that searching a deliberate part of the challenge, or incidental overhead?
