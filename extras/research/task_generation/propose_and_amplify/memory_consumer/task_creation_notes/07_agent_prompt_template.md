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

### 0. Understand Who Uses This Software (REQUIRED FIRST STEP)

Before brainstorming any tasks, look up the software's occupation and industry
context from the dataset files shipped with this notes folder. The CSVs live
at `extras/research/task_generation/propose_and_amplify/memory/task_creation_notes/`
relative to the repo root. This takes 2 minutes and will transform the quality
of your tasks.

**Step 1 — Quick summary from `selected_products.csv`:**
```python
import csv, ast

NOTES_DIR = "extras/research/task_generation/propose_and_amplify/memory/task_creation_notes"

with open(f"{NOTES_DIR}/selected_products.csv") as f:
    for r in csv.DictReader(f):
        if r["product"].strip().lower() == "[PRODUCT_NAME]".lower():
            print("Categories:", ast.literal_eval(r["category"]))
            print("Top SOC groups:", ast.literal_eval(r["soc_major_group"]))
            print("Total GDP: $" + r["product_total_gdp_usd"])
            break
```
> Note: `category` and `soc_major_group` are stored as Python-list strings — use `ast.literal_eval()` to parse them.

**Step 2 — Top occupations from `master_dataset.csv`:**
```python
import csv

with open(f"{NOTES_DIR}/master_dataset.csv") as f:
    rows = [r for r in csv.DictReader(f)
            if r["product"].strip().lower() == "[PRODUCT_NAME]".lower()]

rows.sort(key=lambda r: float(r["product_gdp_usd"] or 0), reverse=True)
for r in rows[:10]:
    print(f"  {r['occupation_title']:50s}  importance={r['onet_importance']:4s}  "
          f"gdp=${float(r['product_gdp_usd']):>15,.0f}")
    print(f"      why: {r['category_rationale']}")
```

**Column meanings:**
| Column | Meaning |
|--------|---------|
| `onet_importance` | 0–100 scale of how important this software is for this occupation |
| `product_gdp_usd` | Economic output of this (occupation × software) pair — higher = more economically central |
| `category_rationale` | Free text: WHY this occupation uses this software (read these!) |
| `soc_major_group` | Occupational category (e.g., "Educational Instruction and Library") |
| `job_zone_category` | `high_skill` or `low_skill` |

**Step 3 — Contemplate before designing tasks:**

Ask yourself: What do the top-5 occupations by `product_gdp_usd` actually do with this software? Not "what features does it have" but "what real problem does a [Health Specialties Teacher / Research Scientist / Policy Analyst] solve with it each week?" Read the `category_rationale` for each — they describe the real workflow pain points.

Only after this reflection should you design tasks. Every task should be something a real member of one of these top occupations would recognise as "yes, that's a thing I genuinely need to do."

> If the product is not found in `selected_products.csv` or `master_dataset.csv`, skip this step and rely on your own knowledge of the software.

---

### 1. Realistic Professional Workflows
- Tasks must represent actual work that professionals do
- Ask yourself: "Would a [ROLE: doctor/analyst/designer] actually need to do this?"
- NEVER use synthetic, generated, simulated, or fabricated data or scenarios

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
- [ ] Task reflects real professional workflow
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
5. **Model real workflows** - Research how professionals use the application
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
