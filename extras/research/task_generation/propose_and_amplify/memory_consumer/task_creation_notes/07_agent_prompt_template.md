> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Agent Prompt Template for Task Creation

## Overview

This document provides a prompt template for instructing an AI agent to create tasks for Gym-Anything environments. Customize the placeholders for your specific environment.

---

## Prompt Template

```markdown
# Task Creation Agent Instructions

You are creating tasks for the **[ENVIRONMENT_NAME]** environment in the Gym-Anything benchmark.

## Your Mission

Create [NUMBER] complex, realistic tasks that test AI agent capabilities in [DOMAIN/APPLICATION].

## What You Can Do

**You can run any software.** The Gym-Anything infrastructure supports full graphical desktops (Linux, Windows, Android) via QEMU VMs, Docker containers, and Android AVDs. You can launch and interact with any GUI application, run CLI tools, query databases, and access web applications. There are no OS or software restrictions — if it runs on Linux, Windows, or Android, you can build tasks for it.

**You do NOT need to capture screenshots or collect evidence for every task.** Write the task files (README.md, task.json, setup_task.sh, export_result.sh, verifier.py), run the offline verifier mock tests (see `13_file_content_verification_and_offline_testing.md`), and boot the environment for a live do-nothing test when practical. Evidence collection (screenshots, evidence JSON) is helpful for debugging but is not a blocking requirement.

## Critical Requirements

### 0. Research the Target Software's Power-User Workflows (THE VERY FIRST STEP — NON-NEGOTIABLE)

**Before doing anything else** — before reading `CONSUMER_USE_CASES.md`,
before exploring the environment, before sketching any task ideas — do an
extensive web survey of the actual target software. The framework here is
generic; only research can tell you what a *hard* task for *this app* looks
like.

**Required research budget**: at least **8–10 sources** spanning:
- Reddit (`r/<app>`, `r/MacApps`, `r/productivity`, related subs)
- Hacker News discussions of the app
- Personal "how I use X" blog posts (especially with dotfiles / config repos)
- The app's official manual / documentation
- GitHub issues on the app's repo and extension repos (real bug reports
  reveal real edge cases)
- Dotfile / config-sharing repos (search GitHub for `<app>.rayconfig`,
  `karabiner.json`, etc.) — these are the actual workflows power users run
- Changelogs / release notes (non-obvious features often live here)
- Comparison articles (`<app> vs Alfred / Spotlight / …`) — they expose
  what the app does *better or worse*, both of which are testable

**Three things to extract from research**:
1. **Pain points** — what people complain about; what's awkward; what
   beginners trip on. These reveal non-trivial capabilities.
2. **Cool configs** — shared dotfiles, custom scripts, multi-feature
   integrations. These are realistic *hard* workflows worth testing.
3. **Chainable workflows** — orchestration patterns: deeplinks invoking
   other commands, scripts that call AppleScript / CLI / `shortcuts run`,
   AI extensions composing tool calls, named layouts that bundle multiple
   actions. Chained workflows are usually the hardest *and* the most
   realistic power-user behavior.

**Cite your sources.** Maintain a `research_notes.md` in your scratch area
with bullet points: URL → the specific insight you took from it. If you
cannot point to a source for *why* a proposed task is hard, the research
is incomplete and you must continue researching, not start designing.

**Why this is the very first step**: Without research, your task designs
will default to the easiest archetype — the "read a spec document → create
N items → save a file" pattern — for every task in the set. That archetype
tests file I/O and reading comprehension more than it tests the actual
software. See `14_task_design_antipatterns.md` §14 ("Archetype
Homogeneity") and §15 ("Narrative Wrappers for Utility Software") for the
specific failure modes that skipping research produces.

**For utility / launcher / configuration / automation software**: pay
extra attention to chaining and orchestration. The hardest workflows for
these apps almost always live in *composition across features*
(deeplinks, AppleScript / Shortcuts.app integration, AI-extension
chaining, named layouts with content loading, dynamic placeholder
syntax with modifiers) — not in repeated use of a single feature.

---

### 0a. Understand the Personal-Use Context (REQUIRED FIRST STEP)

Before brainstorming any tasks, **read `CONSUMER_USE_CASES.md`** (next to this
file in the same `task_creation_notes/` directory). It defines what
"realistic" means for consumer / personal-use tasks and lists scenario classes
per app category.

Pay particular attention to:
- The **core distinction** table (personal use ≠ professional use)
- The **scenario classes** section for your target app's category
- The **hardness levers** that make consumer tasks genuinely hard
  (multi-stakeholder constraints, household budget, multi-stage decisions,
  geography, calendar conflicts, personal preferences, etc.)
- The **anti-patterns** at the bottom — especially:
  - Don't open with *"You are a [professional role] at a [firm]"*
  - Don't write the output as *"save findings to ~/Documents/X.json"*
  - Don't frame the task as an *audit* or *compliance review*
  - Don't require professional certifications / standards as ground truth

Every task you design must map to at least one scenario class from that file
and use 2–3 of the listed hardness levers. The task's persona should be a
**person** with a **personal goal** (planning a family trip, choosing a
pediatrician, organizing a vacation photo album), NOT an employee fulfilling
a job responsibility.

> The consumer corpus has **no occupation × software CSV**. Do not try to
> load `master_dataset.csv` or `selected_products.csv` — they do not exist
> in this corpus by design. The consumer prior is qualitative (scenarios +
> hardness levers), not quantitative (GDP × wage-bill weights).

---

### 1. Realistic Personal-Use Scenarios
- Tasks must represent actual things a real person would do for a personal goal — trip planning, comparison shopping, family medical research, household management, hobby projects, school assignments, creative work, learning, AND power-user configuration of utility software
- Ask yourself: *"Would a real person actually need to do this for themselves or their family?"* — NOT *"Would a [professional] need to do this for their job?"*
- **Framing depends on app category**:
  - **Content / browsing / communication / decision-support apps** (Safari, Maps, Photos, Notes, Mail, Calendar): use a personal-narrative opener — *"You are planning..."* / *"Your family needs..."* / *"You're trying to decide between..."*. NEVER *"You are a [analyst / engineer / clinician] at..."*.
  - **Utility / launcher / configuration / automation apps** (Raycast, Alfred, Karabiner, Hammerspoon, Keyboard Maestro, BetterTouchTool, Hazel, Rectangle, tmux / zsh / vim config): **state the configuration goal directly** — *"Build a Script Command at … that …"*, *"Create N Quicklinks that use … placeholder syntax"*, *"Set up a Window Layout named X that …"*. Do NOT wrap in a persona or backstory; the configuration IS the task. See `14_task_design_antipatterns.md` §15 for the wrong-vs-right table.
- The output artifact should be in the app's native format that a person would actually save (a note, a saved itinerary, a calendar event with reminders, a signed PDF, a curated photo album, a Script Command `.sh` file, a Quicklink/Snippet JSON export, a window layout config) — NOT a JSON report dumped to `~/Documents/`
- NEVER use synthetic, generated, simulated, or fabricated data or scenarios
- **Archetype diversity across the 5-task set**: no more than 2 of 5 tasks share the same workflow archetype (spec-driven create, orchestration script, declarative configuration, dynamic template, stateful pipeline, live expansion, error repair, audit-and-annotate). See `14_task_design_antipatterns.md` §14.

### 2. Use REAL Data — No Exceptions
- ALL data must be real. No synthetic data. No generated data. No fake data. Period.
- Query the environment database to find suitable targets that already exist
- Use actual patient/user/entity data from the system
- If the environment needs input files (images, datasets, documents), use real ones from public sources or sample data bundled with the software
- NEVER write scripts that generate data (no np.random, no faker, no astropy to generate FITS, no programmatic data fabrication of any kind)
- If you find yourself writing data generation code in setup_task.sh, STOP — you are doing it wrong. Go find real data instead.
- Document all IDs, names, and key attributes in metadata
- Never use placeholder names like "John Doe" or "Test Patient"

### 3. Strong Verification
Every task must have:
- **Baseline recording**: Save initial counts before task starts
- **Wrong-target rejection**: Score=0 if actions affect wrong entity
- **Multi-criterion scoring**: At least 3 independent verification criteria
- **Value validation**: Check that entered values are realistic

### 4. Clear Descriptions
Task descriptions must specify:
- Exact target (name, ID, date of birth)
- Exact values to enter (for hard tasks) or just the goal state (for very_hard tasks)
- Login credentials
- **DO NOT include step-by-step UI instructions for hard/very_hard tasks** — the agent must figure out how to navigate the application. Spelling out every menu click makes a task trivially easy regardless of its difficulty label. State WHAT the end state should be, not HOW to get there.

## Environment Information

**Application**: [APPLICATION_NAME]
**Database**: [DATABASE_TYPE] accessible via [HOW_TO_QUERY]
**Login**: [USERNAME/PASSWORD]
**Key tables/data**:
- [TABLE_1]: [DESCRIPTION]
- [TABLE_2]: [DESCRIPTION]

## Task File Structure

For each task, create these files:
```
tasks/<task_name>/
├── README.md        # Full documentation
├── task.json        # Task specification
├── setup_task.sh    # Pre-task setup (record baseline)
├── export_result.sh # Post-task export (query results)
└── verifier.py      # Verification logic
```

## Required Steps for Each Task

0. **Complete the Step 0 research mandate** for the target software (Reddit / HN / blog posts / docs / GitHub issues / dotfiles). Cite sources. No design begins before this — see Critical Requirement 0 above.
1. **Query data** to find a suitable target with appropriate characteristics
2. **Write README.md** with full task documentation
3. **Create task.json** with metadata containing ground truth
4. **Write setup_task.sh** that records baseline state
5. **Write export_result.sh** that extracts verification data
6. **Write verifier.py** with multi-criterion scoring
7. **Set execute permissions**: `chmod +x *.sh`
8. **Test the task** and collect evidence

## Verification Requirements

Your verifier MUST:
1. Check correct target FIRST (score=0 if wrong)
2. Compare against baseline (detect NEW work)
3. Use at least 3 independent criteria
4. Validate values are in realistic ranges
5. Return structured result with feedback

Scoring should reflect the multiple independent subtasks the agent must complete. Each major subtask is worth a portion of the score. Partial credit is awarded for completing some but not all subtasks.

## Example Tasks for Reference

Review these existing tasks in the environment:
- [TASK_1]: [BRIEF_DESCRIPTION]
- [TASK_2]: [BRIEF_DESCRIPTION]

## Output Format

For each task you create, provide:
1. The complete README.md
2. The complete task.json
3. The complete setup_task.sh
4. The complete export_result.sh
5. The complete verifier.py

Ensure all code is complete and runnable.

## Quality Checklist

Before finalizing each task:
- [ ] **Step 0 research done**: 8–10 cited sources covering Reddit, HN, blog posts, official docs, GitHub issues, dotfiles. Sources point to *specifically why* each task is hard. (No design begins before this.)
- [ ] Task reflects a real personal-use scenario (matches a class in `CONSUMER_USE_CASES.md`)
- [ ] **Framing matches app category**:
  - Content/browsing/communication apps → personal-narrative opener
  - Utility/launcher/configuration apps → **direct configuration statement, no narrative wrapper** (see `14_task_design_antipatterns.md` §15)
- [ ] Output artifact is in the app's native format a person would actually keep — NOT a JSON report dumped to `~/Documents/`
- [ ] Uses 2+ hardness levers from `CONSUMER_USE_CASES.md` (multi-stakeholder, household budget, multi-stage, geography, calendar, preferences, multi-source synthesis, etc.)
- [ ] **Both litmus tests pass**:
  - [ ] Untrained human couldn't solve it in <10 minutes by clicking around
  - [ ] **A frontier AI agent would find it genuinely challenging** — would NOT complete it on first attempt without exploration / iteration. If a capable LLM can one-shot it, the task produces no benchmark signal.
- [ ] **Stripped-description test passes** (`14_task_design_antipatterns.md` §17): delete every sentence that isn't an operational requirement / specific value / success criterion. The remaining core must itself be hard. If the bare-bones core reads "create N items, save to file", the original was easy and the narrative was disguising it.
- [ ] **Archetype diversity** (across 5-task set): no more than 2 of 5 tasks share the same archetype. See `14_task_design_antipatterns.md` §14. Concretely, avoid having all 5 tasks be "read spec doc → create N items → save file".
- [ ] **Surface-diversity check passes** (`14_task_design_antipatterns.md` §16): strip domain nouns from each task's description and compare the 5 stripped versions side by side. If they're near-duplicates, the set has surface diversity only — redesign for archetype/pipeline/feature variation. Different cover stories (vacation / garden / recipes / health) are NOT diversity; different workflows are.
- [ ] Uses REAL data only — absolutely NO synthetic/generated/fabricated data anywhere
- [ ] Has 3+ verification criteria
- [ ] Records baseline state
- [ ] Rejects wrong-target with score=0
- [ ] Description is specific and unambiguous
- [ ] All scripts have proper shebang
- [ ] JSON is valid and complete
```

---

## Customization Examples

Fill in the `## Environment Information` section of the template with your environment's specifics. Include: application name, database type and query command, login credentials, key tables/paths, and sample queries. See existing task directories under `benchmarks/cua_world/environments/` for real examples.

---

## Tips for the Agent

1. **Start with data discovery** - Query the database before designing tasks
2. **Design for genuine difficulty** - Read `01_core_principles.md` "START HERE" section before brainstorming tasks. Your first idea is almost always too simple. Ask: "Could a power user solve this by clicking around for 10 minutes?" If yes, redesign.
3. **Combine multiple features** - Hard tasks require the agent to use 3+ distinct capabilities of the application
4. **Make the agent discover, not execute** - The task description should state the goal and end state, not the path. For very_hard tasks, the agent should have to figure out even what's wrong.
5. **Model real personal-use scenarios** - Think about how an actual person would use this app for a personal goal — what scenarios in `CONSUMER_USE_CASES.md` match this app's affordances?
6. **Think adversarially** - How might an agent game this task?
7. **Do not require yourself to complete the task** - You do not need to personally solve the task end-to-end to validate it. Validate the scaffolding (do-nothing returns 0, partial returns partial score). Tasks harder than what you can solve are perfectly valid.

---

## Sample Agent Output Structure

When the agent creates a task, it should output:

```
## Task: [task_name]

### README.md
```markdown
[Complete README content]
```

### task.json
```json
[Complete JSON]
```

### setup_task.sh
```bash
[Complete script]
```

### export_result.sh
```bash
[Complete script]
```

### verifier.py
```python
[Complete Python code]
```

### Evidence Query
To verify this task works, run:
```python
[Test code]
```
```
