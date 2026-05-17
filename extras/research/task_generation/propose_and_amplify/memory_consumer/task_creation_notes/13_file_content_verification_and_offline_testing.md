> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# File-Content Verification and Offline Verifier Testing

## Overview

Two practical gaps that arise when the verification target is a **text file the agent edited** (config files, code files, list files, reports) rather than a database record or numeric output. These gaps are not covered by the database/form patterns in `03_verification_patterns.md`.

---

## Gap 1: The `\\n` Escape Issue in File-Content JSON

When a setup or export script reads a file and stores its **text content** inside a JSON field — whether via PowerShell's `ConvertTo-Json` or bash's `cat` + `jq` — newlines and tabs inside the file become double-escaped in the JSON:

```
Actual file:          list: user.letter\n-\nalpha: a\n
Stored in JSON field: "list: user.letter\\n-\\nalpha: a\\n"
```

The verifier receives the string literally containing `\n` (two characters: backslash + n), **not** a real newline character. Any line-by-line operation (`splitlines()`, `re.MULTILINE`, `str.split('\n')`) will fail silently — it will see the whole content as one line.

**Always unescape before processing:**

```python
# In verifier.py — do this immediately after reading the JSON field
raw = result.get('file_content', '')
text = raw.replace('\\n', '\n').replace('\\t', '\t')

# Now text has real newlines — splitlines(), regex, etc. all work correctly
lines = text.splitlines()
```

This applies to both Windows (PowerShell `ConvertTo-Json`) and Linux (any tool that serializes raw file content to a JSON string field). Make it a habit: every string field that represents file content must be unescaped before use.

**Contrast**: If your export script reads a file and stores structured *derived data* (counts, presence flags, specific extracted values) rather than the raw text, this issue does not apply — you are comparing structured values, not parsing raw content.

---

## Gap 2: Offline Verifier Unit Testing (No Live VM Required)

The verification checklist requires testing do-nothing, partial, and full-completion scenarios. The straightforward approach — actually running tasks in a live VM — is slow and requires the environment to be set up correctly. A faster approach: unit-test the verifier locally by **mocking `copy_from_env`**.

The verifier receives `copy_from_env` through `env_info`. It always calls it the same way:
```python
copy_from_env(source_path_in_vm, local_temp_path)
```

You can replace this with a function that writes a synthetic result JSON directly to `local_temp_path`:

```python
import importlib.util, json, tempfile, os

def load_verifier(task_path):
    """Load a verifier module from its file path."""
    spec = importlib.util.spec_from_file_location('verifier', task_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def make_env(result_data):
    """Create an env_info dict with a mocked copy_from_env."""
    def copy_from_env(src, dst):
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump(result_data, f)
    return {'copy_from_env': copy_from_env}

def make_env_missing():
    """Simulate the result file not existing yet (export script never ran)."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {'copy_from_env': copy_from_env}

# Load verifier
mod = load_verifier('benchmarks/cua_world/environments/myenv/tasks/mytask/verifier.py')
task_info = {'metadata': {'result_file': 'C:\\Users\\Docker\\mytask_result.json'}}

# Do-nothing test: result file doesn't exist
r = mod.verify_mytask([], make_env_missing(), task_info)
assert r['passed'] is False and r['score'] == 0, f"Expected 0/False, got {r}"

# Do-nothing test: file exists, nothing changed
r = mod.verify_mytask([], make_env({'field_a': 'original_value', 'field_b': ''}), task_info)
assert r['passed'] is False, f"Do-nothing should not pass: {r}"

# Partial completion test
r = mod.verify_mytask([], make_env({'field_a': 'corrected', 'field_b': ''}), task_info)
assert not r['passed'] and 20 <= r['score'] <= 59, f"Partial score out of range: {r}"

# Full completion test
r = mod.verify_mytask([], make_env({'field_a': 'corrected', 'field_b': 'done'}), task_info)
assert r['passed'] and r['score'] >= 60, f"Full completion failed: {r}"

print("All verifier unit tests passed")
```

This runs in under a second and catches the vast majority of bugs before any VM interaction. Build and run these tests immediately after writing the verifier — before writing the setup or export scripts. If the verifier is wrong, you want to know before the scripts are built around incorrect assumptions.

**What to put in the synthetic result dicts**: Copy the initial state from your setup script (do-nothing) and the corrected state you expect the agent to produce (full). For partial scenarios, correct some fields but leave others in their broken state.

---

## Gap 3: The Do-Nothing Invariant Is `passed=False`, Not `score=0`

The verification checklist table in `03_verification_patterns.md` shows:

| Scenario | Expected Result |
|----------|-----------------|
| Agent does nothing | Score: 0, Passed: False |

**This is incomplete.** For tasks where the initial *seeded state* already satisfies some verifier criteria, the do-nothing score will legitimately be greater than 0. The real invariant is only:

> **Do-nothing must return `passed=False`.**

### When do-nothing score > 0 is expected

This happens specifically in **seeded-conflict tasks**: tasks where you pre-create files with deliberate problems for the agent to find and fix. Even before the agent does anything, some criteria may already be satisfied:

- "All 3 config files exist" — files were created by setup, so this is 15 pts in the initial state
- "No crashes on launch" — if the app is already running, this might award points before any agent action
- "File X is present" — if X was seeded as part of the scenario, the verifier may award existence points

**This is correct behavior.** The seeded files are real; the verifier correctly detects them. The task is still valid because `passed=False` in the do-nothing state (the problems are not yet fixed, so the score is below the pass threshold).

**The design rule**: Set the pass threshold high enough that seeded-state satisfaction alone cannot reach it. If your setup seeds content that satisfies 15 pts worth of criteria, ensure the pass threshold is far enough above 15 that the do-nothing state fails clearly (e.g., threshold=60 with do-nothing score=15 gives a comfortable gap).

### When score=0 in do-nothing is required

For **creation tasks** (the agent must build something from scratch, nothing is pre-seeded):

- All file-existence criteria start as FAIL (the target file doesn't exist yet)
- All content criteria start as FAIL (nothing to parse)
- Score is genuinely 0 in the do-nothing state

This is the simpler case and more natural for creation-from-scratch tasks. Prefer this structure when possible because it makes the do-nothing test trivially obvious: if nothing was created, score=0.

### Summary

| Task type | Do-nothing score | Do-nothing passed |
|-----------|-----------------|-------------------|
| Create-from-scratch | 0 (nothing exists) | False |
| Seeded-conflict (fix pre-existing bugs) | 0 to ~20 pts (some criteria satisfied by seeded state) | False |
| Both must satisfy | — | **passed=False** |

When writing offline unit tests (see Gap 2), allow for this: test `passed=False` explicitly, and use a score range rather than requiring exactly 0.

---

## Gap 4: Offline Testing for `exec_capture`-Based Verifiers (No Result File)

Gap 2 covers verifiers that use `copy_from_env` to pull a pre-built JSON result file from the VM. But some environments — particularly web apps backed by a live database (MySQL/MariaDB, PostgreSQL) — use a different pattern: the verifier calls `exec_capture` directly to run shell commands in the VM (e.g., `mysql -u root db -N -B -e "SELECT ..."`) and parses the stdout. There is no intermediate JSON file; every check is a live query.

The mock strategy is different: instead of writing a synthetic JSON file, you mock the **command dispatch** — inspect each command string and return simulated output.

### The Pattern

```python
def make_exec_capture(profile_row, exists_set, member_set, rss_count=0):
    """
    Mock exec_capture for DB-querying verifiers.

    profile_row:  Tab-separated values for the admin profile query.
                  Match the column order in the verifier's SELECT statement.
    exists_set:   Set of record names (teams, groups, etc.) that "exist"
                  (query should return "1"). Everything else returns "0".
    member_set:   Set of (record_name, user_email) tuples where membership
                  exists (returns "1"). All others return "0".
    rss_count:    Simulated count for POST-based activity checks.
    """
    def exec_capture(cmd):
        # Multi-step RSS check: write script step (return "ok")
        if 'PYEOF' in cmd or 'heredoc' in cmd.lower():
            return 'ok'
        # Multi-step RSS check: run script step (return JSON)
        if '_rss_check.py' in cmd or 'rss_count' in cmd:
            return '{{"rss_count": {}}}'.format(rss_count)
        # Profile query (SELECT first_name, last_name, ... WHERE email = 'admin@...')
        if 'first_name' in cmd and 'admin@' in cmd:
            return profile_row
        # Membership check (JOIN query with both a record name and a user email)
        if 'JOIN' in cmd and '@' in cmd:
            for name, email in member_set:
                safe = name.replace("'", "\\'")
                if (f"'{safe}'" in cmd or f"'{name}'" in cmd) and email in cmd:
                    return '1'
            return '0'
        # Record existence check (COUNT(*) WHERE name = '...')
        if 'COUNT(*)' in cmd:
            for name in exists_set:
                safe = name.replace("'", "\\'")
                if f"'{safe}'" in cmd or f"'{name}'" in cmd:
                    return '1'
            return '0'
        return '0'
    return exec_capture
```

Pass the mock via `env_info`:

```python
env_info = {
    'exec_in_env': make_exec_capture(
        profile_row='Tyler\tMorrison\tplaceholder bio.\t0000000000\tAmerica/New_York',
        exists_set={'Archive Team A', 'Archive Team B'},   # pre-seeded teams that exist
        member_set=set(),                                   # no memberships yet
        rss_count=0,
    )
}
result = mod.verify_mytask([], env_info, {'metadata': {}})
assert result['passed'] is False
assert result['score'] < 60
```

### Pre-Calculating the Do-Nothing Score

For tasks with "exclusion" criteria (user must NOT be in a team), non-existent teams trivially satisfy the exclusion check — the user can't be in a team that doesn't exist yet. This means the do-nothing score is always greater than zero when the task creates new records. Pre-calculate it before testing:

```
Do-nothing score = (exclusion checks × pts each) + (seeded records × pts each)

Example:
  5 excluded teams × 4 pts = 20 pts  (teams don't exist → exclusion trivially satisfied)
  2 contaminator teams × 2 pts = 4 pts  (pre-created by setup → exist in DB)
  All other criteria = 0 pts  (nothing created yet)
  Total do-nothing = 24 pts  → passed=False (threshold 60) ✓
```

Write the assertion to match this calculation:

```python
# Do-nothing: expect 24 pts (not 0), but definitely passed=False
assert result['passed'] is False
assert result['score'] == 24, f"Expected 24, got {result['score']}"
```

### What the Mock Must Distinguish

| Command characteristic | Return |
|---|---|
| Contains `PYEOF` or heredoc | `'ok'` (script-write step) |
| Contains script filename + `.py` | `'{"rss_count": 0}'` (script-run step) |
| Contains `first_name` + `admin@` | Tab-separated profile row |
| Contains `JOIN` + `@email` | `'1'` if in member_set, else `'0'` |
| Contains `COUNT(*)` | `'1'` if name in exists_set, else `'0'` |
| Anything else | `'0'` |

Keep mock logic simple and keyword-based. Do not parse SQL — match on distinctive substrings. If two query types share a substring, add a more specific distinguisher.

### When This Applies

Use this pattern when the verifier:
- Gets `exec_in_env` or `exec_capture` from `env_info` (no `copy_from_env`)
- Runs shell commands (`mysql`, `psql`, `sqlite3`, `grep`) directly
- Has no intermediate JSON result file written by an export script

The `copy_from_env` mock from Gap 2 is **not** applicable here — these verifiers never call `copy_from_env`.

**Applies to**: Any environment where verification is done via direct command execution (DB queries, log grep, API calls) rather than through an export-then-parse pipeline.
