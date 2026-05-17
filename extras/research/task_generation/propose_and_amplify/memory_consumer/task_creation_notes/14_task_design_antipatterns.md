> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Task Design Anti-Patterns

Concrete failure modes discovered during real task-creation sessions. Each entry describes what went wrong, why it happens, and how to prevent it. These apply to any environment.

---

## Anti-Pattern 1: Difficulty Label Drift

**What happens**: Task creators assign `"very_hard"` to tasks that provide explicit target values and expected outcomes in the description. The reasoning is: "this task feels hard to complete." But difficulty is not about subjective effort — it is determined by what information the description gives the agent.

**The rule (from `01_core_principles.md`):**
- `hard`: description includes target identity AND expected values; agent must find the UI path itself
- `very_hard`: description states goal only; agent must discover targets, values, AND UI path

**The symptom**: A task.json reads `"difficulty": "very_hard"` but the description contains lines like:
```
Allergen: Aspirin, Reaction: Anaphylaxis, Severity: Severe.
Record vitals: BP 148/90 mmHg, Weight 87 kg...
```
That is `hard`, not `very_hard`. The label must match the description content, not the task creator's intuition.

**How to check**: Read your description as if you are an agent. If you can look up the correct answer in the description without reasoning, it is `hard`. If you would have to open the application and investigate to know what to do, it is `very_hard`.

---

## Anti-Pattern 2: Feature Matrix Designed After the Fact

**What happens**: Task creators design tasks ad hoc — picking scenarios that feel realistic — and then check the feature matrix at the end. The result is that all 5 tasks cluster around 2-3 features (whichever were most prominent in the tutorial or example task). Redesigning afterwards is expensive.

**The fix: Build the feature matrix first as a constraint, then fill in domain content.**

Concretely:
1. List all verifiable features of the environment (e.g., allergy_documentation, vitals_recording, condition_problem_list, medication_order, lab_order, appointment_scheduling).
2. Draw a 5×N table. Assign each task a unique combination of 3 features before naming any patients or scenarios.
3. Only then invent the clinical/domain story that fits each combination.

This order prevents the natural drift toward the path of least resistance (all tasks sharing the same 2 "easy" features) and eliminates the need for costly rewrites.

**Example of doing it right:**

| Task | allergy | vitals | condition | medication | lab_order | appointment |
|------|:-------:|:------:|:---------:|:----------:|:---------:|:-----------:|
| T1   | ✓ | ✓ | ✓ | | | |
| T2   | | ✓ | ✓ | ✓ | | |
| T3   | ✓ | | ✓ | | ✓ | |
| T4   | | ✓ | ✓ | | | ✓ |
| T5   | ✓ | ✓ | | | | ✓ |

Build this table first. Invent the five patient scenarios second.

---

## Anti-Pattern 3: Recording Baseline Count Before Cleanup

**What happens**: In `setup_task.sh`, the initial count of a resource (orders, allergies, conditions, appointments) is recorded before pre-existing instances are removed. The verifier then sees a baseline that includes items it just deleted, leading to incorrect delta computation.

**Wrong order**:
```bash
# WRONG: records count before cleanup
INITIAL_ORDER_COUNT=$(omrs_get "/order?patient=$UUID" | python3 -c "...print(len(results))")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count

# Now deletes the orders that were just counted
for order_uuid in $EXISTING_ORDERS; do
    omrs_delete "/order/$order_uuid"
done
```

**Right order**:
```bash
# CORRECT: cleanup first, then record count
for order_uuid in $EXISTING_ORDERS; do
    omrs_delete "/order/$order_uuid"
done

# Now count reflects clean state
INITIAL_ORDER_COUNT=$(omrs_get "/order?patient=$UUID" | python3 -c "...print(len(results))")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count
```

**Rule**: In any setup script that removes pre-existing instances of the target resource, the cleanup loop must run before the initial count is written to `/tmp/`. This applies to any environment where the verifier uses delta-based detection (count after > count before).

---

## Anti-Pattern 4: Partial Credit Total Can Exceed the Pass Threshold

**What happens**: A 3-criterion verifier awards partial credit for each criterion independently. But if partial credit totals from all criteria can exceed the pass threshold even when none pass fully, a partial agent incorrectly scores a pass.

**Example of a bad design**:
```
Criterion 1: 33 pts full / 20 pts partial
Criterion 2: 34 pts full / 20 pts partial
Criterion 3: 33 pts full / 20 pts partial
Pass threshold: 50
```
An agent that hits partial on all three scores 60 — a pass — even though it completed nothing correctly. The pass threshold of 50 is wrong relative to the partial credit levels.

**The check**: Before finalizing any verifier, compute the maximum score achievable if every criterion scores only its partial credit value (not full):
```
max_partial_total = sum(partial_pts for each criterion)
```
This must be strictly less than the pass threshold.

**Correct design for the example above**:
```
Pass threshold: 67  # > max_partial_total (60 in this case)
```
Or reduce partial credit so that max_partial_total < pass_threshold.

**General rule**: For N criteria scored at P_full and P_partial each, set:
```
pass_threshold > sum of all P_partial values
```
This ensures that only genuine task completion — at least one criterion at full score — can cross the pass line.

---

## Anti-Pattern 5: Agent Required to Create Environmental Prerequisites

**What happens**: A task requires the agent to record vitals, place a medication order, or order a lab test. All of these actions require an active visit/session/context to already exist in the system. The task description does not mention the visit, and setup_task.sh does not create one. The agent spends many steps trying to figure out why the action is failing, or succeeds in creating an unintended visit with the wrong type/location.

**The fix**: Any environmental prerequisite for agent actions must be handled in `setup_task.sh`, not left for the agent. If the application requires:
- An active session/visit before recording clinical observations
- An open project before adding files
- An initialized workspace before running commands

Then `setup_task.sh` must create or ensure that prerequisite exists in the correct state before the agent takes its first step.

**General principle**: The setup script's job is to place the environment in the state that a professional would already be in before the agent begins. If a nurse would start a shift with a patient's visit already open, `setup_task.sh` should open that visit. If an engineer would open the project before the work begins, `setup_task.sh` should open the project.

The agent's job is to complete the task, not to discover or create the conditions under which the task becomes possible.

---

## Anti-Pattern 6: Export Script and Verifier JSON Field Name Mismatch

**What happens**: `export_result.sh` writes a JSON file with a field named `"constraints"`, but `verifier.py` reads `result.get("dist_constraints", [])`. Both scripts are written at different times, and the mismatch is invisible during development because the offline test uses a hand-crafted result dict — which the test author writes with the name they *expect* the verifier to use, not necessarily the name the export script *actually* produces.

**Why it's hard to catch**: The do-nothing test (empty result → score=0) passes correctly. The full-completion test (fabricated result → score=100) also passes correctly — because the test author writes the dict with the verifier's expected field name. Only when the real export script runs in the environment does the bug manifest: the verifier silently gets an empty list and scores 0 even when the agent did everything right.

**Symptoms**:
- Offline tests all pass (do-nothing returns 0, fabricated-success returns 100)
- Live run where agent clearly completed the task still returns score 0 or very low
- Partial credit checks that should catch "file saved" pass, but value-matching checks never score

**The fix**: After writing both scripts, add an explicit cross-reference test with the *actual* export script output format:

```python
# At the end of the offline test suite — simulate the exact JSON export_result.sh produces
result = {
    "task_start": NOW - 100,
    "output_file_exists": True,
    "output_file_is_new": True,
    "output_file_size": 5000,
    "constraints": [{"type": 30, "valA": 85.0}]  # field name from export_result.sh
}
# This must match what the verifier actually reads, not what you wish it read
```

Read your `export_result.sh` cat block, copy its exact field names into the test, and confirm the verifier scores correctly. Do not write the test from memory of the verifier — write it from reading the export script.

**Prevention checklist**:
1. After writing both scripts, grep each field name in the verifier against the JSON object in `export_result.sh`
2. In the offline test, explicitly copy the exact field names from the `cat > /tmp/*.json` heredoc in `export_result.sh`
3. If the export script uses `"constraints"`, the verifier must call `result.get("constraints", [])`, and the test dict must have key `"constraints"` — all three must agree

---

## Anti-Pattern 7: Update-Style Setup Does Not Reset the Target Fields

**What happens**: A task requires the agent to *update* an existing record — add an attendee, change a location, set a reminder, write a description. `setup_task.sh` ensures the record exists, but does not touch the specific fields the agent must modify. The record is therefore already in the "correct" end state (or close to it) from whatever data was seeded at environment setup time. The do-nothing verifier scores partial or full points because the required values were already there before the agent acted.

**Why it's subtle**: For *creation* tasks, the setup script obviously must ensure the target does not already exist (clean slate). For *update* tasks, creators correctly ensure the target exists — but forget the second step: the specific fields the agent must set must be deliberately reset to a "challenge baseline" (wrong or absent values). Without this reset, any pre-seeded correct values give the agent free credit.

**The fix: Always explicitly reset the to-be-modified fields in `setup_task.sh`.**

For each field the agent must update, force it to a neutral or wrong value before the agent starts:

```python
# WRONG: just ensure the record exists
event = find_event('Investor Update Preparation')
# (If it already has location='Board Room', the agent gets free points)

# RIGHT: reset the fields the agent must set
models.write(event_id, {
    'location': 'Zoom Meeting',    # agent must change this to Board Room
    'description': False,          # agent must write an agenda
    'alarm_ids': [(5, 0, 0)],      # clear all alarms; agent must add a reminder
    'partner_ids': [(3, karen_id)] # remove the attendee the agent must add
})
```

**The rule for every update-style task**: After ensuring the target record exists, write a `setup_task.sh` block that explicitly sets every to-be-modified field to its *opposite* or *absent* value. Document the challenge baseline in comments so future maintainers understand why the values look wrong.

**How to check**: After running `setup_task.sh` but before any agent action, run `export_result.sh` and inspect the result JSON. Every field that the verifier checks should be at its "nothing done" value (`False`, `0`, `""`, or the wrong value). If any criterion already scores points, the setup did not fully reset that field.

**Applies to**: Any task in any environment where the agent must modify, edit, or update an existing entity (calendar event, database record, config file, contact, document) rather than create one from scratch. In API-backed web apps (Odoo, OpenEMR, Redmine, etc.), this is especially important because the seeding script may have set correct values that the agent is supposed to "add."

---

## Anti-Pattern 8: Per-Entity Partial Credit Amplification in Multi-Entity Tasks

**What happens**: Anti-Pattern 4 describes the case where independent criteria each award partial credit that sums past the pass threshold. Multi-entity tasks introduce a compounding variant: when the same scoring logic runs once per entity (N users registered, N measurement entries recorded, N records created), the partial credit for "some entities done" scales with N. This makes it far easier to accidentally exceed the pass threshold even when no criterion is fully satisfied.

**Example**:

A task requires:
- Register 4 research participants (7 pts each × 4 = 28 pts total, partial: 5 pts each)
- Create 3 measurement categories (4 pts each = 12 pts, no partial)
- Create a training routine with description (10 pts)
- Schedule 3 training days (9 pts total, 3 pts each)

Original pass threshold: 60 pts.

An agent that creates all 4 users (28 pts) + all 3 categories (12 pts) + the routine (10 pts) + 2 of 3 days (6 pts) scores **56 pts** — a near pass with no nutrition, no measurement entries, and incomplete scheduling. But if a partial-credit award of 5 pts per user is granted for "account exists without email set":

- 4 users × 5 pts partial = 20 pts
- 3 categories × 4 pts (no partial, binary) = 12 pts
- Routine with description: 10 pts
- 3 days: 9 pts

**Total partial = 51 pts < 60 threshold** — looks safe. But if partial for "3 of 4 users" at 5 pts each gives 15 pts, and the user also creates the routine + days, the total can easily exceed 60 before the nutrition, measurement entries, or correct data are in place.

**The compounding factor**: With N per-entity awards, the maximum partial score formula is:

```
max_partial_total = (per_entity_partial_pts × N_entities)
                  + sum(partial_pts for each non-entity criterion)
```

This must be strictly less than the pass threshold. When N is large (4–10 entities), even a small per-entity partial award dominates.

**The fix**:

1. **Make entity creation binary at the full-N level**: Award points only when *all N* entities are created correctly — not proportionally for partial count. This eliminates the per-entity amplification entirely.

2. **If proportional scoring is necessary** (e.g., 3/4 users correct is better than 0/4), precompute the worst-case partial total assuming each entity scores its partial value, and raise the pass threshold above that sum.

3. **Document the computation explicitly in the verifier docstring** (see Lesson 188 in `05_learnings_best_practices.md` for the convention).

**How to check**: Before finalizing the verifier, fill in this table:

```
Criterion      | Full pts | Partial pts | Notes
-------------- | -------- | ----------- | ------
N entities     | N × full | N × partial | per-entity scoring
Category A     | X        | Y           |
...
TOTAL partial  | -        | SUM         | must be < pass_threshold
```

If the "TOTAL partial" row can reach or exceed the pass threshold, you have an amplification problem.

**Applies to**: Any task requiring the agent to create or modify multiple homogeneous entities — user registration batches, measurement entry series, product catalog imports, test subject enrollment, bulk configuration changes. The risk is highest when N ≥ 3 and per-entity partial credit is awarded.

---

## Anti-Pattern 9: Absence Criteria Pass Trivially When the Data Source Is Unreachable

**What happens**: A verifier awards points for criteria of the form "X was removed", "user has 0 credentials", or "member is not in group Y". When the export script queries an external service (REST API, inner VM, Docker container, remote database) that was offline or not yet started, the export returns empty collections. Every "absence" criterion then trivially passes — there is nothing in the empty collection — and the do-nothing score is incorrectly inflated.

This is distinct from the "Preservation Criteria on Do-Nothing" anti-pattern. That pattern concerns criteria that pass because the agent took no action. This pattern concerns criteria that pass because the data source returned nothing — the agent could have done anything (or nothing at all) and the score is the same.

**Example**: A PACS offboarding task awards 30 pts for "user has 0 credentials" per contractor. If the access control service is still starting up when export runs, `GET /api/v3/users` returns `{}` or an empty list. The verifier sees 0 credentials for 0 users — not because credentials were revoked, but because no data came back at all. The "0 credentials" criterion passes for all three contractors, scoring 90 pts → passed=True.

**The telltale sign**: Your do-nothing test returns score > 0 when you substitute an empty or near-empty result dict for the mock data, even though the agent took no action.

**The fix — include a reachability sentinel in the export JSON**:

For every service your export queries, export a field that is only truthy when the service actually responded with the data you expected:

```bash
# In export_result.sh — good
ALL_USERS=$(curl -sk -b "$COOKIE" "$AC_URL/api/v3/users")
echo "$ALL_USERS" | python3 - << 'EOF'
import json, sys
users = json.loads(sys.stdin.read()) or []

result = {
    "users": users,
    "total_user_count": len(users),           # sentinel: 0 means service offline
    "target_users": {
        "alice": next((u for u in users if u["email"] == "alice@corp.com"), None),
    }
}
json.dump(result, open("/tmp/result.json", "w"))
EOF
```

```python
# In verifier.py — gate absence criteria on the sentinel
total_users = result.get("total_user_count", 0)
if total_users < expected_minimum:
    return {"passed": False, "score": 0,
            "feedback": f"Service appears offline — only {total_users} users found. "
                        "Criteria cannot be scored."}

# Now absence criteria are safe to evaluate
alice = result.get("target_users", {}).get("alice")
if alice and alice.get("credential_count", 999) == 0:
    score += 30
    feedback.append("PASS: Alice's credentials revoked (+30)")
```

**Sentinel design rules**:

1. **Use "expected entities found" not "no errors returned"**: An offline service can return HTTP 200 with an empty body. Use the count of entities that should exist regardless of agent actions (e.g., total users, legitimate group members, baseline records). If that count is below the expected minimum, the service was not reachable.

2. **Choose a sentinel that is insensitive to the agent's actions**: If the agent could legitimately delete users, don't use total user count as the sentinel — use a different entity class the agent cannot remove. In group membership audits, use "Meridian users found in the system at all" rather than "legitimate group members present" (since the agent might move legitimate members too).

3. **Return early with score=0**: When the sentinel indicates the service was offline, return immediately. Do not attempt to score individual criteria — any score above 0 on offline data is noise.

4. **Document the sentinel in the verifier docstring**: State clearly what the sentinel checks and what threshold triggers the offline guard.

**Where this occurs**:
- Any environment where the PACS, EHR, ERP, or CRM runs as a separate process that must warm up (inner VM, Docker container)
- Tasks that run export immediately after setup (the service may still be starting)
- Any "cleanup" or "offboarding" task where the verifier checks that records were removed/cleared

**The related offline test edge case**: Your offline mock test for "do-nothing" must simulate the actual do-nothing state, not the offline state. The do-nothing mock should have real-looking data (all target entities present, all in wrong state, no work done by agent). A mock with empty collections tests the sentinel path, not the do-nothing path — write a separate test case if you want to confirm the sentinel fires correctly.

**Applies to**: Any task in any environment where `export_result.sh` queries a service that may not be running or may return empty data for reasons unrelated to the agent's actions. This includes all API-backed PACS, EMR, ERP, ITSM, and similar systems where the backend is a separate process from the outer host.

---

## Anti-Pattern 10: Embedded Language `print()` Calls Leaking Ground Truth in Setup Scripts

**What happens**: `setup_task.sh` contains an inline Python (or other interpreter) block using a heredoc (`python3 << 'PYEOF' ... PYEOF`). Inside the block, the task creator adds `print()` statements to log what the setup is doing — e.g., `print(f"Injected slide at position {pos}: '{title}'"`)` or `print(f"Changed title to: {new_title}")`. These `print()` calls write to stdout and are therefore indistinguishable from shell `echo` commands from the perspective of output visibility.

**Why it's easy to miss**: Shell `echo` commands feel "explicit" — creators know they produce output. But Python `print()` inside an embedded heredoc feels like "internal logging", not "shell output". The mental model is: "this is Python code, not a shell statement." In reality, stdout from an embedded interpreter block is merged into the setup script's stdout — it is identical to `echo` at the shell level.

**The `01_core_principles.md` principle this violates**: "Do not print ground truth in setup output. `setup_task.sh` must not echo the specific items injected, their names, or their distinguishing properties in completion messages. Treat all setup output as potentially agent-visible."

The word "echo" in that principle applies equally to `print()`, `console.log()`, `puts`, `printf`, or any other output statement inside any embedded interpreter block.

**Concrete example (wrong)**:

```bash
python3 << 'PYEOF'
from pptx import Presentation

prs = Presentation("/home/ga/Documents/performance.pptx")
injected_titles = [
    "Target Market Segmentation",
    "Campaign ROI Analysis Q3",
    "Brand Messaging Framework",
]
for title in injected_titles:
    # ... injection logic ...
    print(f"Injected slide: '{title}'")  # ← LEAKS ground truth to stdout

PYEOF
echo "Setup complete."
```

An agent that can read setup output (in any debug mode or via shell access) sees the exact marketing slide titles it is supposed to identify and remove through domain reasoning.

**The fix**:

```bash
python3 << 'PYEOF'
from pptx import Presentation

prs = Presentation("/home/ga/Documents/performance.pptx")
injected_titles = [
    "Target Market Segmentation",
    "Campaign ROI Analysis Q3",
    "Brand Messaging Framework",
]
for title in injected_titles:
    # ... injection logic ...
    # No print() here — injected content must not appear in stdout

prs.save("/home/ga/Documents/performance.pptx")
print(f"Setup complete. Total slides: {len(prs.slides)}")  # ← counts only, no titles

PYEOF
echo "Setup complete."
```

**What is safe to print from embedded blocks**:
- Total counts: `print(f"Total slides: {len(prs.slides)}")`  — reveals nothing about which slides are injected
- Generic completion messages: `print("Injection complete.")`
- Structural facts unrelated to injected content: `print(f"File saved: {output_path}")`

**What must never appear in any stdout from setup_task.sh**:
- The specific titles, names, values, or IDs that were injected
- The positions (by meaningful label, not just index) of injected items
- The exact target values the agent must fix, compute, or discover
- Any field value that constitutes ground truth the agent is supposed to derive independently

**The scanning rule**: Before finalizing `setup_task.sh`, grep every `print()`, `echo`, `console.log()`, `puts`, or equivalent output statement in the entire script — including those inside heredoc blocks. For each one, ask: "If the agent read this line, would it reveal something the agent is supposed to figure out?" If yes, remove or neutralize the statement.

**Applies to**: Any `setup_task.sh` that uses an embedded interpreter block (Python, Ruby, Perl, JavaScript via Node, PHP, etc.) to inject errors, seed data, or modify files. The language does not matter — all stdout produced during `setup_task.sh` execution is subject to the same confidentiality constraint as shell `echo` output.

---

## Anti-Pattern 11: Absence Criteria Trivially Satisfied by Minimal Agent Output in Value-Swap Repair Tasks

**What happens**: A task requires the agent to replace wrong values with correct ones in a structured file (constraint values, config fields, database records). The verifier checks two categories of criteria: (a) correct values are present, and (b) wrong values are absent. The task creator sets the pass threshold high enough to prevent an agent from passing with only one category — but fails to check whether the absence-only score combined with the file-existence score can reach the threshold. An agent that saves an output file with *no content at all* (empty file, zero constraints, blank record) passes all absence criteria trivially, since there are no wrong values in an empty file.

**Why it's not obvious**: When you write the verifier, you test three cases: missing file (score=0), wrong values still present (partial), and all corrections done (score=100). You do not naturally test the fourth case: file exists but is completely empty. In this case the absence criteria all award their points, and if the total is high enough, the task is incorrectly scored as passed.

**Concrete example of a broken scoring**:
```
File exists and is new:        20 pts
Correct value A present:       15 pts
Correct value B present:       15 pts
Wrong value X absent:          25 pts
Wrong value Y absent:          25 pts
Pass threshold: 80

Agent saves empty file:
  File exists and is new:       20  ✓
  Correct A (empty file, no match): 0
  Correct B:                     0
  Wrong X absent (trivially):   25  ✓
  Wrong Y absent (trivially):   25  ✓
  Total = 70 → does NOT pass
```

That example is safe. But if wrong-absent points totalled 45 instead of 50:
```
  20 + 45 = 65 < 80  → still safe
```
And if pass threshold were 60:
```
  20 + 50 = 70 ≥ 60  → BROKEN: empty file passes
```

**The invariant to check before finalizing any repair-task verifier**:

```
file_existence_pts + sum(absence_criterion_pts) < pass_threshold
```

If this inequality does NOT hold, an agent that saves a file containing no domain content whatsoever will pass the task.

**The fix**: Adjust either the absence point values or the pass threshold so the invariant holds. A safe design keeps absence criteria worth less than presence criteria — since the removal of wrong values is the *means*, not the *end*, of a repair task.

```
Preferred structure:
  File exists and is new:   20 pts   (gate)
  Correct value A present:  20 pts   (correct outcome — worth more)
  Correct value B present:  20 pts
  Wrong value X absent:     20 pts   (evidence of correction)
  Wrong value Y absent:     20 pts
  Pass threshold: 80

Empty-file score: 20 + 0 + 0 + 20 + 20 = 60 < 80  ✓  (does not pass)
```

**How to check**: Before finalizing the verifier, fill in:

```
file_existence_pts = X
sum of absence_criterion_pts = Y
pass_threshold = T

Check: X + Y < T
```

If `X + Y >= T`, either raise `T` or reduce the per-criterion absence points.

**Applies to**: Any task in any environment where the agent must correct, replace, or remove specific values from a file or database, and the verifier checks both the presence of correct values and the absence of wrong ones. This includes constraint-repair tasks (CAD, physics simulation), config-fix tasks, metadata-correction tasks, and database-cleanup tasks.

---

## Anti-Pattern 12: Python Heredoc stdout Capture in export_result.sh Silently Fails on Exception

**What happens**: `export_result.sh` uses a Python heredoc to parse a structured file (XML, JSON, binary format) and capture the output into a bash variable, which is then written into the result JSON. If the Python block raises an unhandled exception, Python writes the traceback to stderr and nothing to stdout. The bash variable captures the empty stdout, producing a malformed or empty JSON field. The verifier then silently gets no data, returning score=0 even when the agent correctly saved a valid output file.

**What it looks like**:
```bash
# In export_result.sh — dangerous pattern
PARSED_DATA=$(python3 << 'PYEOF'
import json
with open('/home/ga/output.slvs', 'rb') as f:
    data = parse_format(f.read())  # Can raise FileNotFoundError, UnicodeDecodeError, etc.
print(json.dumps(data))
PYEOF
)

cat > /tmp/task_result.json << EOF
{"parsed_data": $PARSED_DATA}
EOF
```

If `parse_format` raises, `$PARSED_DATA` is empty and the JSON is `{"parsed_data": }` — invalid JSON. The verifier's `json.load()` will raise, returning score=0 with a confusing error message.

**Why it's hard to diagnose**: The export script exits with code 0 (the `python3` failure doesn't propagate if the `cat >> EOF` succeeds). The verifier reports "Result file not found" or "JSON parse error" — both messages suggest the file doesn't exist or is malformed, not that Python crashed internally. The agent did everything right; the export script failed.

**The fix**: Always wrap the main logic in try/except inside Python heredoc blocks that capture stdout. Return a safe default on failure, and write the error to stderr separately.

```bash
PARSED_DATA="[]"  # safe default — if Python fails, this value is preserved
if [ -f "$OUTPUT_FILE" ]; then
    PARSED_DATA=$(python3 << 'PYEOF'
import json, sys

def parse_output(filepath):
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
        # ... parsing logic ...
        return parsed_results
    except Exception as e:
        print(f"Parse error: {e}", file=sys.stderr)
        return []

results = parse_output('/home/ga/output.slvs')
print(json.dumps(results))  # Always prints valid JSON
PYEOF
    )
fi
```

**Key properties of the safe pattern**:
1. Initialize the bash variable to a valid JSON default (`"[]"` or `"{}"`) before the Python block runs. If Python exits with error, the safe default is used in the JSON.
2. Wrap the main parsing logic in `try/except`. Return the empty/default value on any exception.
3. The outermost `print(json.dumps(...))` is always reached — it never raises, because `json.dumps([])` is always valid.
4. Gate the Python block on `[ -f "$OUTPUT_FILE" ]` so it does not run at all if the file is missing.

**When to apply**: Any `export_result.sh` that uses a Python (or other interpreter) heredoc to parse a file and capture the output into a bash variable that is then embedded in JSON. This includes: parsing `.slvs` constraint blocks, reading XML config trees, parsing binary file formats, extracting fields from structured text formats.

---

## Anti-Pattern 13: Contamination-Injection Threshold Set Without Strategy Enumeration

**What happens**: A contamination-injection task (see `01_core_principles.md`) seeds a mix of correct and incorrect items. The verifier includes an "anti-gaming" criterion that awards points for *not* touching a correct item. The task creator sets the pass threshold intuitively ("70 sounds right") without computing the score for every plausible agent shortcut. A mass-action strategy (e.g., "delete everything" or "discontinue all medications") scores just at or above the threshold because the anti-gaming criterion's weight is too low relative to the positive-action criteria.

**Concrete example that failed**:

A medication safety review task seeds 3 medications — Warfarin (keep), Aspirin (discontinue), Ibuprofen (discontinue). Initial scoring:
```
Aspirin discontinued:    25 pts
Ibuprofen discontinued:  25 pts
Warfarin still active:   20 pts  (anti-gaming)
INR lab ordered:         10 pts
Encounter created:       10 pts
Pass threshold:          70
```

Strategy enumeration reveals the bug:
| Strategy | Aspirin | Ibuprofen | Warfarin | INR | Encounter | Score | Pass? |
|----------|---------|-----------|----------|-----|-----------|-------|-------|
| Do-nothing | 0 | 0 | 20 | 0 | 0 | **20** | No |
| Mass-discontinue all + INR + encounter | 25 | 25 | 0 | 10 | 10 | **70** | **Yes** |
| Correct behavior | 25 | 25 | 20 | 10 | 10 | **100** | Yes |

The mass-discontinue shortcut scores exactly 70 — a pass! The agent can game the task by blindly discontinuing everything without understanding drug interactions.

**The fix**: Increase the anti-gaming criterion weight and/or raise the threshold so that no shortcut strategy crosses the pass line:
```
Warfarin still active:   30 pts  (was 20)
Pass threshold:          75      (was 70)
```

Now mass-discontinue scores 70 (< 75) — correctly fails.

**The general technique — strategy enumeration table**: Before finalizing any task with seeded/contaminated state, enumerate ALL plausible agent strategies in a table:

1. **Do-nothing**: No actions taken. Score comes entirely from criteria satisfied by seeded state.
2. **Mass-action**: Agent applies the same action uniformly to all items (delete all, discontinue all, approve all, mark all as complete). This is the most common gaming shortcut.
3. **Inverse-action**: Agent acts on the wrong items (keeps what should be removed, removes what should be kept).
4. **Correct behavior**: The intended solution.
5. **Partial-correct**: Only some criteria satisfied.

For each strategy, compute the exact score and verify:
- Do-nothing score < threshold
- Mass-action score < threshold
- Inverse-action score < threshold
- Correct score >= threshold
- Partial-correct score < threshold (unless you intentionally allow partial passes)

**Why Anti-Pattern 4 doesn't catch this**: Anti-Pattern 4 checks whether independent partial credits can sum above the threshold. But in contamination-injection tasks, criteria are *correlated through the agent's strategy* — mass-discontinuation simultaneously gains points on "item X discontinued" criteria and loses points on "item Y still active" criteria. The issue is not about partial vs. full credit on individual criteria, but about which *combination* of criteria a shortcut strategy satisfies.

**Prevention checklist**:
- [ ] For every criterion that awards points for "item still in correct state" (retention/anti-gaming), verify that the mass-action strategy's total score (all positive-action criteria met, all retention criteria failed) is strictly below the pass threshold
- [ ] For every criterion that awards points in the do-nothing state (seeded items satisfying retention criteria), verify that the do-nothing total is strictly below the pass threshold
- [ ] Document the strategy enumeration table in the task's README.md (see `medication_safety_review/README.md` for an example)

**Applies to**: Any task using the contamination-injection pattern, error-injection pattern, or any design where setup seeds a mix of correct and incorrect items that the agent must selectively act upon. Common in: medication management, data cleanup, security audit, code review (planted bugs), and configuration correction tasks.
