> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Getting Started with Task Creation

## Welcome

This guide will help you create high-quality tasks for Gym-Anything environments. Tasks are the core of what makes this benchmark valuable - they must be realistic, robust, and properly verified.

---

## What You Can Run

The Gym-Anything infrastructure supports **any operating system and any desktop application**:

- **Linux desktop apps** — full graphical desktop via VNC (GNOME, KDE, etc.). You can run any GUI application: Firefox, LibreOffice, Blender, GIMP, 3D Slicer, QGIS, etc.
- **Windows desktop apps** — full Windows 10/11 desktop via VNC. You can run any Windows GUI application: Excel, Word, Visual Studio, AutoCAD, etc.
- **Android apps** — Android Virtual Device with full touchscreen interaction.
- **Web applications** — via a browser running inside any of the above environments.
- **CLI/server tools** — via SSH into any environment.

Environments run as QEMU VMs, Docker containers, or Android AVDs. You interact with them through `from_config()` and `env.reset()`. There are **no restrictions** on what software you can launch or interact with inside these environments. If the software runs on Linux, Windows, or Android, you can create tasks for it.

---

## Before You Begin

### Prerequisites
1. Familiarity with the target environment (software, workflow)
2. Access to run the environment (`from_config()`)
3. Understanding of bash scripting and Python
4. Ability to query databases (if applicable)

### Required Reading Order

Read these documents in order:

1. **[01_core_principles.md](01_core_principles.md)** - The philosophy of task design
   - Realistic data requirements
   - Strong verifiability
   - Adversarial robustness
   - Must read before creating ANY task

2. **[02_repository_structure.md](02_repository_structure.md)** - Technical structure
   - Where files go
   - What each file does
   - How hooks work

3. **[03_verification_patterns.md](03_verification_patterns.md)** - Creating robust verifiers
   - Baseline recording
   - Wrong-target rejection
   - Multi-criterion scoring

4. **[04_evidence_documentation.md](04_evidence_documentation.md)** - Proving your task works
   - What evidence to collect
   - How to collect it
   - Evidence review checklist

5. **[05_learnings_best_practices.md](05_learnings_best_practices.md)** - Lessons learned
   - Common pitfalls
   - Debugging workflows
   - Performance tips
   - §220: Never hardcode auto-incremented FK/PK IDs — always resolve at runtime using stable natural keys
   - §221: Boolean values from bash are strings — verifiers must accept both `True` and `"true"`

6. **[06_task_creation_checklist.md](06_task_creation_checklist.md)** - Step-by-step checklist
   - Use this for every task you create
   - Don't skip steps

7. **[11_agent_behavior_patterns.md](11_agent_behavior_patterns.md)** - Agent failure modes and task design implications
   - Search loops and the pre-positioning principle
   - Step budget calibration for agent overhead
   - Design self-check questions before finalizing any task

8. **[12_new_environment_onboarding.md](12_new_environment_onboarding.md)** - Required if you are working with a software environment you have never used before
   - Systematic protocol for establishing a stable baseline
   - How to discover the app's scripting seam (CLI, API, data files, export, UI dump)
   - Identifying verifiable actions before designing tasks
   - Pilot trajectory testing to calibrate difficulty before committing to a full task suite

9. **[13_file_content_verification_and_offline_testing.md](13_file_content_verification_and_offline_testing.md)** - Required when the task target is a text file the agent edits (config, code, list)
   - The `\\n` escape issue: file content stored in JSON must be unescaped before line-by-line analysis
   - Offline verifier unit testing: mock `copy_from_env` to test do-nothing/partial/full scenarios without a live VM
   - Do-nothing invariant clarification: `passed=False` is required; `score=0` is NOT always required (seeded-conflict tasks may score >0 in the initial state)

---

## Quick Start: Creating Your First Task

### Step 1: Explore the Environment

```python
from gym_anything.api import from_config

# Load environment without a task
env = from_config("benchmarks/cua_world/environments/<env_name>")
obs = env.reset(seed=42)

# Get connection info
print(f"SSH: {env._runner.ssh_port}, VNC: {env._runner.vnc_port}")

# Query the database to understand available data
output = env._runner.exec_capture(
    'docker exec db-container mysql -u user -ppass db -e "SELECT * FROM patients LIMIT 10"'
)
print(output)

env.close()
```

### Step 1b: Look Up Who Actually Uses This Software (REQUIRED)

Before choosing a task, consult the occupation/industry data shipped with
this notes folder. The CSVs live at
`extras/research/task_generation/propose_and_amplify/memory/task_creation_notes/`
relative to the repo root:

```python
import csv, ast

NOTES_DIR = "extras/research/task_generation/propose_and_amplify/memory/task_creation_notes"

# Quick lookup — replace PRODUCT_NAME with the exact name from selected_products.csv
PRODUCT = "PRODUCT_NAME"

# 1. Top-level context
with open(f"{NOTES_DIR}/selected_products.csv") as f:
    for r in csv.DictReader(f):
        if r["product"].strip().lower() == PRODUCT.lower():
            print("Categories:", ast.literal_eval(r["category"]))
            print("SOC groups:", ast.literal_eval(r["soc_major_group"]))
            break

# 2. Top occupations by economic importance
with open(f"{NOTES_DIR}/master_dataset.csv") as f:
    rows = [r for r in csv.DictReader(f)
            if r["product"].strip().lower() == PRODUCT.lower()]
rows.sort(key=lambda r: float(r["product_gdp_usd"] or 0), reverse=True)
for r in rows[:8]:
    print(f"  {r['occupation_title']:50s}  imp={r['onet_importance']:4s}  "
          f"why: {r['category_rationale']}")
```

Read the `category_rationale` fields carefully — they describe the *actual* pain points and workflows that justify this software's value to each occupation. Your tasks should feel natural to someone in those roles.

### Step 2: Choose a Task

Ask yourself:
- What would a professional from the **top-occupation list** actually do with this software?
- What data exists to support this task?
- How would I verify the task was done correctly?
- **Could a power user who has never used this software solve this in under 10 minutes by clicking around?** If yes, the task is too easy — go back and make it harder.
- Does the task require using 3+ distinct features of the application, or just one workflow?
- Does the agent need to *discover* what's wrong, or am I just telling it what to fix?

### Step 3: Document First

Create the README.md before any code. The description should state the goal and expected end state — not a sequence of UI steps (for hard/very_hard tasks). See `01_core_principles.md` Principle 6 for guidance on what to include vs. omit by difficulty level.

### Step 4: Create the Files

```bash
ENV_DIR=benchmarks/cua_world/environments/<env_name>
mkdir -p $ENV_DIR/tasks/<task_name>

# Create files (see templates in 06_task_creation_checklist.md)
touch $ENV_DIR/tasks/<task_name>/README.md
touch $ENV_DIR/tasks/<task_name>/task.json
touch $ENV_DIR/tasks/<task_name>/setup_task.sh
touch $ENV_DIR/tasks/<task_name>/export_result.sh
touch $ENV_DIR/tasks/<task_name>/verifier.py

# CRITICAL: Set permissions
chmod +x $ENV_DIR/tasks/<task_name>/*.sh
```

### Step 5: Test Incrementally

1. Test environment loads with task
2. Test setup script creates expected files
3. Test export script creates valid JSON
4. Test verifier returns correct scores

### Step 6: Collect Evidence

Run your evidence collection script and verify:
- Screenshots show correct state
- Database evidence matches expectations
- All verification criteria testable

---

## Task Quality Checklist

Use the full checklist in **[06_task_creation_checklist.md](06_task_creation_checklist.md)** for every task you create. It covers all phases from research through finalization.

---

## Common Mistakes and Anti-Patterns

See **[01_core_principles.md](01_core_principles.md)** (especially the "Summary Checklist" at the bottom) and **[14_task_design_antipatterns.md](14_task_design_antipatterns.md)** for a comprehensive list of failure modes and how to prevent them.

---

## Getting Help

- **Environment issues**: See `extras/research/software_as_env/creation_audit/memory/env_creation_notes/`
- **Verification patterns**: See `03_verification_patterns.md`
- **Debugging**: See `05_learnings_best_practices.md`
- **Task difficulty guidance**: See `01_core_principles.md` "START HERE" section — do not pattern-match on existing tasks for difficulty calibration, as many existing tasks may be too simple

---

## File Summary

```
task_creation_notes/
├── 00_getting_started.md          # This file - entry point
├── 01_core_principles.md          # Philosophy and requirements
├── 02_repository_structure.md     # Technical structure
├── 03_verification_patterns.md    # Robust verification
├── 04_evidence_documentation.md   # Proving tasks work
├── 05_learnings_best_practices.md # Lessons learned
├── 06_task_creation_checklist.md  # Step-by-step checklist
├── 07_agent_prompt_template.md    # Prompt template for the task-creation agent
├── 08_windows_environment_patterns.md  # Windows-specific script/verification patterns
│                                       #   §11: xlsx verification (openpyxl); §12: docx/OOXML verification (zipfile+regex)
├── 09_android_environment_patterns.md  # Android AVD-specific patterns
├── 10_linux_desktop_environment_patterns.md  # Linux GUI desktop patterns (DISPLAY, su, wmctrl, etc.)
├── 11_agent_behavior_patterns.md             # Agent failure modes & task design implications
├── 12_new_environment_onboarding.md          # First-contact protocol for brand-new apps: stable
│                                             #   baseline, scripting seam discovery, verifiable action
│                                             #   mapping, pilot trajectory testing
├── master_dataset.csv             # ~17k products × occupations; key cols: occupation_title,
│                                  #   onet_importance (0-100), product_gdp_usd, category_rationale
└── selected_products.csv          # ~488 products; category & soc_major_group are Python list
                                   #   strings — parse with ast.literal_eval()
```

---

## Next Steps

1. Read [01_core_principles.md](01_core_principles.md)
2. Explore your target environment
3. Identify a suitable task
4. Follow the checklist in [06_task_creation_checklist.md](06_task_creation_checklist.md)
