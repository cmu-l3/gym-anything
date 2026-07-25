> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Learnings and Best Practices

## Overview

This document captures practical lessons about script mechanics, verification patterns, and debugging. These apply to any environment.

---

## Critical Lessons

### 1. Script Permissions Are Silent Killers

**The Problem**: Scripts without execute permission fail silently with exit code 126.

**Symptoms**:
- Hook runs but creates no files
- No error messages in output
- Setup files (`/tmp/initial_*`) don't exist
- Export says "Export Complete" but JSON is empty/wrong

**The Fix**:
```bash
# ALWAYS run this after creating scripts
chmod +x benchmarks/cua_world/environments/<env_name>/tasks/<task_name>/*.sh

# Verify permissions
ls -la benchmarks/cua_world/environments/<env_name>/tasks/<task_name>/*.sh
# Should show: -rwxr-x--- (x means executable)
```

**Prevention**: Add a reminder in your task creation workflow to always set permissions.

---

### 2. Bash Syntax Compatibility

**The Problem**: Some bash syntax doesn't work in all shell environments.

**Example that broke**:
```bash
# This failed in the VM environment
if [[ "$APPT_DATE" >= "$TODAY" ]]; then
```

**Error**:
```
syntax error in conditional expression
syntax error near `"$TODAY"'
```

**The Fix**: Use POSIX-compliant alternatives:
```bash
# Convert to epoch seconds and use numeric comparison
APPT_EPOCH=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
TODAY_EPOCH=$(date -d "$TODAY" +%s 2>/dev/null || echo "0")

if [ "$APPT_EPOCH" -ge "$TODAY_EPOCH" ]; then
    # ...
fi
```

**Best Practice**: Test your bash scripts with `shellcheck` before deploying.

---

### 3. Database Query Patterns

**The Problem**: MySQL query results need careful parsing.

**What works**:
```bash
# Query returns tab-separated values, one row per line
RESULT=$(docker exec mysql-container mysql -u user -ppass db -N -e "SELECT id, name FROM table WHERE id=1")

# Parse fields with cut
ID=$(echo "$RESULT" | cut -f1)
NAME=$(echo "$RESULT" | cut -f2)
```

**What doesn't work**:
```bash
# This captures header row too (without -N flag)
RESULT=$(docker exec mysql-container mysql -u user -ppass db -e "SELECT id, name FROM table")
```

**Key flags**:
- `-N`: No header row
- `-e "..."`: Execute query
- Result is tab-separated

---

### 4. JSON Escaping in Shell Scripts

**The Problem**: Special characters in shell variables break JSON.

**What breaks**:
```bash
REASON="Patient's follow-up"  # Apostrophe breaks JSON
cat > /tmp/result.json << EOF
{"reason": "$REASON"}
EOF
# Results in: {"reason": "Patient's follow-up"} - invalid JSON
```

**The Fix**:
```bash
# Escape special characters
escape_json() {
    echo "$1" | sed 's/"/\\"/g' | tr '\n' ' '
}

REASON_ESCAPED=$(escape_json "$REASON")
cat > /tmp/result.json << EOF
{"reason": "$REASON_ESCAPED"}
EOF
```

**Alternative**: Use heredoc with single quotes to prevent variable expansion:
```bash
cat > /tmp/result.json << 'EOF'
{"static_field": "value"}
EOF
```

---

### 5. Screenshot Timing

**The Problem**: Screenshots captured too early show loading states.

**What happens**:
```bash
# Screenshot while page still loading
DISPLAY=:1 scrot /tmp/screenshot.png  # Shows blank or loading spinner
```

**The Fix**:
```bash
# Wait for application to stabilize
sleep 2  # Give UI time to render
DISPLAY=:1 scrot /tmp/screenshot.png
```

**Better approach**: Wait for specific window:
```bash
# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla"; then
        break
    fi
    sleep 1
done
DISPLAY=:1 scrot /tmp/screenshot.png
```

---

### 6. copy_from_env Failures

**The Problem**: File copy from VM fails silently or with confusing errors.

**Symptoms**:
```
[QemuApptainer] SCP copy_from failed, trying SFTP with password...
[QemuApptainer] SFTP: source not found: /tmp/file.png
```

**Common causes**:
1. File doesn't exist (script failed earlier)
2. File path is wrong
3. Permissions prevent reading

**Debugging**:
```python
# Check if file exists first
exists = env._runner.exec_capture('ls -la /tmp/result.json 2>&1')
print(exists)

# Only then try to copy
if 'No such file' not in exists:
    env._runner.copy_from('/tmp/result.json', 'local.json')
```

---

### 7. Docker Container Names

**The Problem**: Container names might differ from expected.

**What you assume**:
```bash
docker exec openemr-mysql mysql ...
```

**What actually exists**:
```bash
# Check actual container names
docker ps --format "{{.Names}}"
# Might show: openemr-mysql-1 or different name
```

**The Fix**: Check containers programmatically:
```bash
# Find MySQL container dynamically
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -1)
docker exec "$MYSQL_CONTAINER" mysql ...
```

---

### 8. Empty Query Results

**The Problem**: Empty query results cause cascading failures.

**What breaks**:
```bash
RESULT=$(openemr_query "SELECT * FROM table WHERE id=999")
ID=$(echo "$RESULT" | cut -f1)  # ID is empty
echo "Found ID: $ID"  # Shows "Found ID: " - looks like it worked
```

**The Fix**: Always check for empty results:
```bash
RESULT=$(openemr_query "SELECT * FROM table WHERE id=999")

if [ -z "$RESULT" ]; then
    echo "No results found"
    FOUND="false"
else
    FOUND="true"
    ID=$(echo "$RESULT" | cut -f1)
fi
```

---

### 9. Bash Default Value Consistency

**The Problem**: When a DB query returns empty (e.g., no root grade category exists), different scripts default to different values, causing the do-nothing test to fail with a non-zero score.

**What broke**:
```bash
# setup_task.sh - query returns empty, saves empty string to file
ROOT_AGGREGATION=$(moodle_query "SELECT aggregation FROM ... WHERE depth=1")
echo "$ROOT_AGGREGATION" > /tmp/initial_aggregation  # saves ""

# export_result.sh - uses different defaults for the same concept
INITIAL_AGGREGATION=$(cat /tmp/initial_aggregation 2>/dev/null || echo "13")  # defaults to 13
ROOT_AGGREGATION=${ROOT_AGGREGATION:-0}  # defaults to 0
# Now initial=13 and current=0, so verifier thinks something changed!
```

**The Fix**: Use the same default value everywhere for the same concept:
```bash
# Both must default to 13 (Moodle's Natural aggregation)
ROOT_AGGREGATION=${ROOT_AGGREGATION:-13}
# ...
"initial_aggregation": ${INITIAL_AGGREGATION:-13},
"root_aggregation": ${ROOT_AGGREGATION:-13},
```

**Rule**: When a field can be empty/missing, pick ONE canonical default and use it consistently in setup, export, and the JSON template. Test with `cat /tmp/file | wc -c` to check if your baseline files are empty.

---

### 10. Fallback Function Definitions

**The Problem**: `source /workspace/scripts/task_utils.sh` may not make all functions available depending on the shell environment, sourcing order, or VM state.

**The Fix**: Add inline fallback definitions after sourcing:
```bash
# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions in case sourcing fails
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    moodle_query() {
        local query="$1"
        mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi
```

**Why**: This makes task scripts self-contained — they work even if the shared utils fail to load. The test for `type function_name &>/dev/null` is a clean way to check availability.

---

### 11. Cached Boot for Faster Testing

**The Problem**: Full environment boot (pre_start + post_start) takes 90+ seconds per task. Testing 5 tasks means 7+ minutes just waiting for boots.

**The Fix**: Use cached checkpoints when testing:
```python
# Full boot (slow, needed for first run):
obs = env.reset(seed=42, use_cache=False)

# Cached boot (fast, use for testing existing tasks):
obs = env.reset(seed=42, use_cache=True, cache_level="pre_start", use_savevm=True)
```

**How it works**:
- `use_cache=True`: Reuse existing checkpoint if available
- `cache_level="pre_start"`: Skip pre_start hook (installation), run post_start and pre_task
- `use_savevm=True`: Use QEMU's savevm/loadvm for fast VM state restore

**When to rebuild cache**: After changing `install_*.sh` or `setup_*.sh` scripts, run once with `use_cache=False` to regenerate the checkpoint.

### 12. Use Python Instead of Bash for Complex Export Analysis

**The Problem**: Export scripts that need to parse JSON, validate CSV structure, check GeoJSON features, or do any non-trivial data analysis become fragile and unreadable when written in pure bash. Nested quoting, `jq` pipeline errors, and string escaping bugs are common.

**The Fix**: Use inline Python (`python3 -c '...'` or `python3 << 'PYEOF'`) inside export scripts for any analysis beyond simple file existence checks:
```bash
# BAD: fragile bash parsing
FEATURE_COUNT=$(cat "$FILE" | jq '.features | length' 2>/dev/null)
HAS_FIELD=$(cat "$FILE" | jq '.features[0].properties | has("name")' 2>/dev/null)

# GOOD: robust Python analysis
python3 << 'PYEOF'
import json, sys
try:
    with open("/path/to/file.geojson") as f:
        data = json.load(f)
    result = {
        "feature_count": len(data.get("features", [])),
        "has_field": "name" in data["features"][0].get("properties", {})
    }
    # Write partial results to files that bash can read
    with open("/tmp/analysis.json", "w") as f:
        json.dump(result, f)
except Exception as e:
    print(f"Analysis failed: {e}", file=sys.stderr)
PYEOF
```

**Why**: Python has built-in JSON/CSV parsing, proper error handling, and no quoting hell. Most VMs already have Python installed. Keep the bash wrapper for file existence checks and final JSON assembly, but delegate any data inspection to Python.

---

### 13. Flexible Column/Keyword Detection for File-Output Tasks

**The Problem**: Tasks that require the agent to produce a CSV (or similar) file cannot dictate exact column names. Different agents will label the same measurement differently: `red_channel`, `channel1`, `ch1`, `rhodamine` all mean "red channel data". Requiring an exact column name causes false negatives for any agent that chose a different but correct label.

**What breaks**:
```python
# BAD: Fails if agent labels the column "channel1" instead of "red"
has_red = 'red' in df.columns
```

**The Fix**: Use synonym sets — a list of accepted names for each concept. Check if *any* of the synonyms appear as column headers or in the data:
```python
# GOOD: Accepts any reasonable label for "red channel"
red_terms   = ['red', 'channel1', 'ch1', 'rhodamine', 'r_channel', 'red_ch']
green_terms = ['green', 'channel2', 'ch2', 'fitc', 'g_channel', 'green_ch']
coloc_terms = ['coloc', 'pearson', 'manders', 'overlap', 'colocalization', 'r_coef']

combined_text = ' '.join(str(h).lower() for h in df.columns)
has_red   = any(t in combined_text for t in red_terms)
has_green = any(t in combined_text for t in green_terms)
has_coloc = any(t in combined_text for t in coloc_terms)
```

**Also apply this in export_result.sh** — use `grep -qi` with alternation patterns rather than exact string checks:
```bash
# BAD
grep -q "red_channel" "$CSV"

# GOOD
grep -qiE "red|channel1|ch1|rhodamine" "$CSV"
```

**When to use**: Any task where the output format is a CSV/TSV/text file produced by the agent (not a structured database record). Verifiers for DB-record tasks can check exact field names because the schema is fixed; file-output verifiers cannot.

---

### 14. Built-In Sample Data as Real Data

**The Observation**: Many professional desktop applications (scientific tools, analysis suites, creative software) ship real sample data accessible via `File > Open Samples` or a similar menu. These samples are real datasets collected for actual purposes — not synthetic. Using them fully satisfies the real-data requirement without external downloads, network dependencies, or large data files to manage.

**Examples**:
- Fiji/ImageJ: `File > Open Samples` — Fluorescent Cells (real microscopy), Mitosis (real 5D confocal), HeLa Cells (real z-stack)
- MATLAB: `load fisheriris`, `load patients` — real classic datasets
- R: `data(iris)`, `data(mtcars)` — real collected data
- QGIS: Sample datasets bundled with installer

**How to find them**: Before searching external repositories, always check `File > Open Samples`, `Help > Sample Data`, `File > Examples`, or the application's documentation for bundled real datasets.

**Why this matters**: Built-in samples are always available in the VM, load instantly, and don't require setup scripts to download or copy files. They also vary in type (2D, 3D, time series, multi-channel), which enables diverse tasks within a single environment.

---

### 15. Sub-Second mtime Precision Causes False Positives in Timestamp Checks

**The Problem**: File modification time (`os.path.getmtime()`) returns a float with sub-second precision, while task start time from `date +%s` is an integer. When setup_task.sh copies a file at T.18s and records `TASK_START = T` (integer), the comparison `mtime > TASK_START` returns `True` even though the file was created at the same integer second — before the agent touched anything.

**What breaks**:
```python
# In export_result.sh — mtime is a float, TASK_START is an integer
import os, json
TASK_START = int(open("/tmp/task_start_timestamp").read().strip())
mtime = os.path.getmtime("/home/ga/some_file.ext")    # e.g. 1772296463.18
result["file_modified_after_start"] = mtime > TASK_START  # True! (0.18 > 0)
```

This gives the agent +N points on the **do-nothing test** just because setup_task.sh copied a starter file.

**The Fix**: Always cast both sides to `int` before comparing:
```python
result["file_modified_after_start"] = int(mtime) > TASK_START
```

**Why it happens**: `cp` and `date +%s` often run in the same calendar second. The integer second matches, but the float mtime is slightly later within that second, making it appear the file was modified after the task started.

**Applies to**: Any environment that checks file modification time in export_result.sh. Always use `int(mtime) > TASK_START` — not `mtime > TASK_START`.

---

### 16. Starter File Keyword Contamination

**The Problem**: When you provide a starter file (broken diagram, template code, sample data, config file) for the agent to modify, every word in it is visible to your verifier. If your keyword-based detection looks for terms that already appear in the starter file, the do-nothing test will return a non-zero score — the agent gets points without doing anything.

**Classic examples**:
- Starter BPMN file contains a gateway labeled `"Budget Approved?"` → verifier finds `"approved?"` and awards XOR gateway detection points
- Starter network diagram contains annotation `"WAN CORE DISTRIBUTION ACCESS layers"` → verifier finds layer keywords and awards topology points
- Starter DFD contains a red annotation `"Apply STRIDE threat model"` → verifier finds `"stride"` and awards methodology points
- Starter CSV comment says `"highest waste steps: Welding, Stamping"` → verifier finds process names and counts them as detected processes

**The Fix**:

1. **Grep your starter file against every keyword in your verifier before finalizing it:**
```bash
# Check if any verifier detection keywords appear in the starter file
grep -ioE "keyword1|keyword2|keyword3" data/starter_file.ext
```

2. **Rephrase, anonymize, or remove any matching terms in the starter file.** A note that says `"Approval gateway here"` is different from `"Approved?"`.

3. **For annotation/comment cells in starter files**: Use neutral styling (grey, not red/orange), and write instructions in generic terms that don't match your detection patterns.

4. **The test**: After any change to starter files, always re-run the do-nothing test and confirm score=0.

**Applies to**: Any task that (a) provides a starter/template file AND (b) uses keyword scanning in the verifier or export script. Particularly common in diagram editors, code editors, and document editors.

---

### 17. Dual-Path Verification — The `or` Logic Pitfall

**The Problem**: A common pattern is to have TWO sources of verification data: the export script's JSON and an independent re-analysis of the output file in the verifier. The logic typically is:

```python
modified = result.get('file_modified_after_start', False) or independent.get('file_modified_after_start', False)
```

The danger: if the independent analysis function **hardcodes `True`** for `file_modified_after_start` (a mistake often made because "the file must have been created if we got this far"), then the `or` expression is always `True` whenever the output file exists — even a stale file from a previous task run.

**What breaks**:
```python
def _analyze_output(file_path):
    # ... parses the file ...
    return {
        "shape_count": 5,
        "file_modified_after_start": True,  # BUG: always True!
    }
```

In a do-nothing test: if a stale output file happens to exist from a previous run, the independent function will be called and will return `True`, giving free points.

**The Fix**: Independent analysis functions must NEVER set `file_modified_after_start` to `True` unconditionally. They should:
- Either skip the field entirely (let the export script own timestamp verification), OR
- Actually compute it from the file's real mtime against task_start_timestamp

```python
def _analyze_output(file_path):
    # ...
    # SAFE: let export script own timestamp verification
    return {
        "shape_count": 5,
        "file_modified_after_start": False,   # conservative; export script determines this
    }
```

**General rule**: For any boolean field that gates scoring, the **conservative** (False) value should be the default in the independent function. Only the export script — which has access to `/tmp/task_start_timestamp` — should authoritatively determine modification time.

**Applies to**: Any verifier that has both an export_result.sh and an independent re-analysis function (`_analyze_*`) that both contribute to the same boolean check via `or` logic.

---

### 18. `grep -c pattern file || echo "0"` Produces Malformed JSON

**The Problem**: A very common bash pattern for safely getting a grep count is:
```bash
COUNT=$(grep -c "pattern" file.txt 2>/dev/null || echo "0")
```
This looks safe but is **broken**. When `grep -c` finds zero matches, it outputs `"0"` to stdout **and** exits with code 1. The `|| echo "0"` then also runs and appends another `"0"`. The variable captures `"0\n0"` (a string with a newline), which produces malformed JSON:
```json
"my_count": 0
0,
```
This causes `json.load()` in the verifier to throw an exception, and the verifier silently returns score=0 — meaning the task appears to pass the do-nothing test for the wrong reason. Once you fix the bug, hidden false positives may appear.

**The Fix**: Choose one of these approaches depending on whether you need a binary flag or an actual count:

```bash
# Option A: Binary flag (does the pattern exist at all?)
MY_FLAG=0
grep -q "pattern" file.txt 2>/dev/null && MY_FLAG=1

# Option B: Actual count (how many matching lines?)
MY_COUNT=$(grep -c "pattern" file.txt 2>/dev/null)
[ -z "$MY_COUNT" ] && MY_COUNT=0   # guard against file-not-found (empty output)

# Option C: Count with guaranteed non-empty output
MY_COUNT=$(grep -c "pattern" file.txt 2>/dev/null; echo "fallback_never_reached")
# NO — don't do this either. Just use option B.
```

**Why `grep -c` with 0 matches exits 1**: POSIX `grep` has three exit codes: 0 (match found), 1 (no match), 2 (error). The count output is separate from the exit code. `grep -c` always prints a number — including "0" — but still exits 1 when there are no matches. The `||` operator triggers on any non-zero exit.

**Rule**: Never use `$(grep -c "..." file || echo "0")`. Always either use `grep -q` for binary results, or use `grep -c` without `||` and add a separate `[ -z "$VAR" ] && VAR=0` for missing-file protection.

**Applies to**: Any export_result.sh that uses `grep -c` to count code patterns, config entries, or file content. This bug silently masks errors and then re-surfaces them as phantom false positives once the malformed JSON is fixed.

**Additional fix options** (from common variations of this bug):

```bash
# Option D: Use `; true` to suppress exit code without adding output
COUNT=$(grep -c "pattern" file 2>/dev/null; true)

# Option E: Two-step assignment with default
COUNT=$(grep -c "pattern" file 2>/dev/null)
COUNT=${COUNT:-0}   # replace empty string with 0 (handles missing file case)

# Option F: Use grep -o | wc -l (always exits 0)
COUNT=$(echo "$TEXT" | grep -o "pattern" 2>/dev/null | wc -l)

# Option G: Inline Python for robust counting
COUNT=$(echo "$TEXT" | python3 -c "import sys; print(sys.stdin.read().count('pattern'))")
```

**Broader principle**: `grep`, `awk`, and `sed` exit non-zero for "no match" or "no input" — this is not an error, but `||` treats it as one. Always verify the *semantics* of non-zero exit codes for counting/searching commands before using them in export scripts.

---

### 19. Source Code Comment Keyword Contamination in Code Task Data Projects

**The Problem**: This is a code-specific extension of Lesson 16 (Starter File Keyword Contamination). When you create a source code project for agents to modify (legacy code to refactor, bugs to fix, vulnerabilities to patch), Javadoc comments and inline code comments naturally describe what's wrong and hint at what to do. If these comments use the exact API names that your verifier greps for, the export script reports non-zero counts before the agent changes anything.

**Classic examples**:
- `// LEGACY: should be Map<Integer, Employee>` → grep for `Map<Integer` finds this comment, inflating the "generics added" counter
- `* migrate to Period.between(hireDate, LocalDate.now())` → grep for `LocalDate` finds this Javadoc, inflating "java.time API used" counter
- `// migrate to StringBuilder` → grep for `StringBuilder` finds this comment, inflating the "StringBuffer replaced" counter

Unlike GUI diagram annotations (Lesson 16), code comments are often pedagogically appropriate — you *want* the code to hint at the problem. But exact API names in comments cause false positives just as much as they do in any other file type.

**What makes this harder to spot**: The malformed JSON bug (Lesson 18) can mask this. If the export script has a JSON bug, `json.load()` throws an exception and the verifier returns score=0 regardless of the grep counts. Only after fixing the JSON bug do the comment false positives become visible.

**The Fix**:

1. **Audit every comment in your data project against your grep patterns**:
```bash
# Find all comment lines that match your verifier's grep targets
MAIN_SRC="benchmarks/cua_world/environments/myenv/data/my-project/src/main/java"
grep -rn "LocalDate\|Period\|Map<Integer\|List<Employee" "$MAIN_SRC" | grep -E "//|/\*|\*"
```

2. **Keep the intent of the comment, but remove the exact API name**. Compare:
```java
// BAD (causes false positive):
// LEGACY: should use Map<Integer, Employee>

// GOOD (no false positive):
// LEGACY: raw type, no type parameter specified
```

3. **For verifier-side mitigation** (complementary, not a substitute): strip comments before applying regex patterns. In Python verifiers, strip comment lines before matching:
```python
def _strip_comments(source_code: str) -> str:
    """Remove single-line and Javadoc/block comment lines."""
    import re
    # Remove line comments
    source_code = re.sub(r'//[^\n]*', '', source_code)
    # Remove block comments
    source_code = re.sub(r'/\*.*?\*/', '', source_code, flags=re.DOTALL)
    return source_code

# Then grep-equivalent logic applies to stripped source
```

4. **Test**: After neutralizing comments, verify counts are 0 in do-nothing state:
```bash
grep -r "LocalDate\|Period\|Map<Integer" src/main/java/ | wc -l   # should be 0
```

**Applies to**: Any task where the data project is source code (Java, Python, TypeScript, etc.) and the verifier uses grep or regex to detect whether the agent applied specific code patterns (API usage, class names, method calls). IDE environments (Eclipse, IntelliJ, Android Studio, VSCode) and code-review environments are the primary targets.

**Additional strategies from Kotlin/Android tasks:**

5. **Require code-only context via negative lookbehind**: Instead of bare keyword search, require the pattern to appear outside comments:
```python
# Only match @Inject not preceded by * or // (i.e., not in a comment)
has_inject = bool(re.search(r'^(?!\s*[*/])\s*@Inject', source, re.MULTILINE))
```

6. **Use MD5 hash change-detection as a gate**: Only award points if the relevant file was actually modified. Record MD5 hashes of key files in `setup_task.sh` and check in the verifier:
```bash
# setup_task.sh
md5sum "$PKG_DIR/AppModule.kt" 2>/dev/null | awk '{print $1}' > /tmp/initial_module_hash
```
```python
# verifier.py
module_changed = result.get('module_changed', False)
if module_changed:
    has_module = bool(re.search(r'@Module', source_text))
```

7. **Guard export script file discovery**: If `export_result.sh` uses `find -exec grep -l` to locate relevant files, it will also find files that mention the pattern only in comments:
```bash
# PROBLEM: finds CoinData.kt because it has "@SerializedName" in a comment
DTO_FILE=$(find "$PKG_DIR" -name "*.kt" -exec grep -l "@SerializedName" {} \; | head -1)

# FIX: restrict to lines that are NOT comments
DTO_FILE=$(find "$PKG_DIR" -name "*.kt" -exec grep -lP "^(?!\s*[/*]).*@SerializedName" {} \; | head -1)
```

**Pre-flight check**: Before finalizing any code-editing task, run:
```bash
grep -rn "@YourPattern\|keyword_you_check" benchmarks/cua_world/environments/<env>/data/<AppName>/
```
and inspect each hit — is it in actual code or just a comment? Every comment match is a potential false positive.

---

### 20. Build-Passes Criterion Must Be Gated on Actual Code Changes

**The Problem**: For tasks in code/IDE environments, a common criterion is "the project builds successfully after changes." But if the data project starts in a compilable state (which is typical for refactoring, migration, and test-coverage tasks — the code is *bad*, not broken), then `mvn clean test` or equivalent passes before the agent does anything. This gives free points in the do-nothing test.

**Example**: A legacy Java project with raw types and old APIs compiles perfectly fine — Java doesn't enforce generics at the type-erasure level, and `java.util.Date` still exists. So `build_passes = True` in the do-nothing state, and the verifier awards those points.

**The Fix**: Gate the build-passes criterion on at least one other substantive criterion being met first:

```python
# BAD: build_passes gives free points if project already compiles
if result.get('build_success'):
    score += 10
    feedback_parts.append("Build passes (10/10)")

# GOOD: build credit only if actual changes were made
any_change_applied = (
    subscores.get('criterion_1') not in (False, None) or
    subscores.get('criterion_2') not in (False, None) or
    subscores.get('criterion_3') not in (False, None)
)
if result.get('build_success') and any_change_applied:
    score += 10
    feedback_parts.append("Build passes with changes applied (10/10)")
elif result.get('build_success') and not any_change_applied:
    feedback_parts.append("Build passes but no changes applied — build credit requires actual fixes (0/10)")
```

**When this applies**: Whenever the starting code project is syntactically valid (compiles or lints without errors). This covers:
- Refactoring tasks (code works, just has smells)
- Migration tasks (old API still works)
- Security hardening (vulnerable code compiles fine)
- Coverage tasks (no tests, but source compiles)

**When it does NOT apply**: If the starting project is intentionally broken (won't compile) — e.g., a "fix the build errors" task. In that case, build_passes is a good indicator of actual work.

**Key distinction from wrong-target gates**: This is not a hard gate (score=0 immediately). It's a soft gate: the build criterion is simply skipped unless changes are present. The agent can still score points for the individual subtasks even if the build is never run.

**Applies to**: All code/IDE environments (Eclipse, IntelliJ, Android Studio, VSCode, Xcode, etc.) where the task is to improve existing code rather than fix broken code.

---

### 21. Always Audit Existing Verifiers for Stubs Before Using Them as Examples

**The Problem**: When exploring a new environment, an agent will naturally look at the existing tasks' `verifier.py` files as reference examples. But in many environments — especially those created early in the project or as scaffolding — the verifiers are **stubs** that always return `{"passed": True, "score": 100}` regardless of what the agent did. Treating a stub as a real example produces broken new verifiers that follow the same non-verification pattern.

**What a stub looks like**:
```python
def verify_some_task(traj, env_info, task_info):
    return {"passed": True, "score": 100, "feedback": "Stub verifier -- VLM evaluation is external"}
```

**What a real verifier looks like**:
```python
def verify_some_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    result = {}
    # ... copy result JSON, check criteria, compute score ...
    return {"passed": score >= 60, "score": score, "feedback": " | ".join(feedback_parts)}
```

**Why it happens**: Stub verifiers are placeholders written when an environment was first scaffolded, with the intention of replacing them later. That replacement often never happens for the "easy" starter tasks because they were only meant to demonstrate the environment, not to be a real benchmark.

**The Fix**: When exploring an existing environment, open **every** `verifier.py` in the existing task directories and confirm they contain real programmatic logic. If they are stubs, you must write real verifiers for your new tasks from scratch — do not model them on the stubs.

**Rule**: `return {"passed": True, "score": 100}` with no conditions is a stub. Any verifier for a hard task must have at minimum: (1) a `copy_from_env` call to retrieve results from the VM, (2) at least 3 independent scoring criteria, (3) a score < 100 unless all criteria are met.

**Applies to**: Any environment you are exploring to create new tasks. Always do a quick `grep -r "passed.*True.*score.*100" benchmarks/cua_world/environments/<env>/tasks/` audit before writing new verifiers.

---

### 22. Application Config Files in evidence_docs Reveal Bundled Data Paths

**The Problem**: When creating tasks for a new environment, a key challenge is knowing what real data is already available inside the VM without having to boot it. This is especially important for Windows applications (which can't be easily queried from the outside) and for applications that ship with bundled example datasets.

**The Discovery**: Application configuration files stored in `evidence_docs/` often record exactly what files the application has recently opened — giving you the full paths of bundled datasets.

**Examples**:
- Epi Info 7: `epiinfo_config.xml` in evidence_docs contained `<RecentView Name="C:\EpiInfo7\Projects\Mumps\Mumps.prj:Survey" .../>` — revealing all bundled datasets with exact paths and table names
- Windows apps often write to `%APPDATA%\<AppName>\config.xml` or equivalent — capturing this in evidence is standard setup
- GUI apps frequently write recently-opened file paths to preference files

**How to use this**:
1. Before designing tasks, search `evidence_docs/` for any XML, JSON, INI, or config files
2. Look for paths of recently-opened files, example databases, or sample projects
3. Use these exact paths in your setup_task scripts — they are guaranteed to exist in the VM

**Why this is valuable**: It eliminates the need to boot the VM just to discover what data is available. It also ensures paths are correct (no guessing at installation directories).

**Applies to**: Windows environments especially, but also any environment where the post_start hook or install script generates config/log files that are stored in evidence_docs.

---

### 23. Download-Failure Fallback to Synthetic Generation Is a Synthetic Data Violation

**The Problem**: A common "defensive programming" pattern in `setup_task.sh` is:

```bash
# Try to download real data
wget -q "$URL" -O data.zip && unzip -q data.zip || {
    # Fallback: generate synthetic data for offline testing
    python3 -c "
import random, struct
# ... generate fake images/CSVs/data ...
"
}
```

This appears reasonable (it looks like "offline testing support"), but **it IS a synthetic data violation** — the programmatically generated images, CSVs, or models are not real. The agent's work on synthetic data is uncalibrated, and the benchmark result is meaningless.

**What makes this hard to spot**: The synthetic generation is buried in an `except` block or a download-failure branch, often labeled as "offline fallback" or "testing convenience." It may have been written with good intent (allowing CI to run without network), but the effect is the same as generating the data from scratch.

**The Fix**:

1. **If the download fails AND there is no built-in alternative in the software:**
```bash
wget -q "$URL" -O data.zip
if [ ! -s data.zip ]; then
    echo "ERROR: Could not download required dataset from $URL"
    echo "ERROR: This task requires real data. Please check network connectivity."
    exit 1
fi
```

2. **If the download fails AND the software ships equivalent built-in sample data** (e.g., Fiji's `File > Open Samples > MRI Stack`, or an IDE's bundled project templates):
```bash
wget -q "$URL" -O data.zip
if [ ! -s data.zip ]; then
    echo "WARNING: Could not download from $URL."
    echo "NOTE: The software provides an equivalent built-in sample via [menu path]."
    echo "NOTE: Setup will continue; the agent may use the built-in sample."
fi
# Do NOT generate synthetic data — continue, letting the agent use the built-in
```

**How to identify the violation**: Scan every `except`, `else`, or download-failure branch for any of these patterns:
- `np.random`, `random.randint`, `random.gauss` — numerical data generation
- `faker`, `Faker()` — fake text/record generation
- PIL/Pillow drawing (`ImageDraw`, `fromarray`) used to create new images
- Any loop that generates rows and writes them to a file

**Applies to**: Any `setup_task.sh` that downloads real data from the internet. The rule applies equally to image data, tabular data, 3D volumetric data, time series, audio, documents, and any other data type. The presence of a download attempt does not make the fallback data real.

---

### 24. Test Do-Nothing in Two Steps: Copy-Raises and Baseline-JSON

**The Problem**: A single do-nothing test (running the verifier with a fresh VM where the agent did nothing) is not sufficient. There are two distinct do-nothing failure modes, and each catches different bugs:

1. **The export script never ran** — the agent did nothing, so `post_task` hook was skipped or the VM was never started. `copy_from_env` will raise `FileNotFoundError` because the result JSON doesn't exist.

2. **The export script ran but captured a pre-agent state** — `setup_task.sh` created some output files (e.g., a starter CSV, a baseline config) as part of task setup. `export_result.sh` then captured these files' metadata into the result JSON. The result JSON exists but contains all-False/zero values — what the environment looks like before the agent touches anything.

If you only test failure mode (1), you miss bugs where the baseline JSON itself contains non-zero values (e.g., `csv_exists=True` because setup_task.sh created a blank CSV). That would give the agent free points without doing anything.

**The Fix**: Always write and run **two** do-nothing scenario tests:

```python
# Scenario A: export script never ran → copy raises
def test_do_nothing_no_export():
    env_info = {"copy_from_env": lambda src, dst: (_ for _ in ()).throw(
        FileNotFoundError(f"No such file on environment: {src}")
    )}
    result = verify_my_task([], env_info, task_info)
    assert result["passed"] is False
    assert result["score"] == 0

# Scenario B: export ran, but agent did nothing → baseline JSON (all False/zero)
BASELINE_JSON = {
    "task_start": 1700000000,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "n_items": 0,
    # ... all other fields at their "nothing done" values ...
}
def test_do_nothing_baseline():
    env_info = {"copy_from_env": lambda src, dst: open(dst, "w").write(json.dumps(BASELINE_JSON))}
    result = verify_my_task([], env_info, task_info)
    assert result["passed"] is False
    assert result["score"] == 0
```

**What the baseline JSON should contain**: Run `setup_task.sh` in the VM, then immediately run `export_result.sh` without doing any agent work. The resulting JSON is your baseline. All `file_modified_after_start` fields must be `False` (because no agent-created files exist), and all counts must be 0.

**Critical check on the baseline**: If `setup_task.sh` creates ANY files that `export_result.sh` would detect (e.g., a blank starter CSV at the output path), make sure those files either:
- Are created before `TASK_START` is recorded (so timestamp checks correctly show `modified_after_start = False`), OR
- Are not at the output path the agent is expected to create

**Applies to**: All environments that use the result-JSON pattern (`copy_from_env` reads `/tmp/<task>_result.json`). This includes virtually all non-GUI-screenshot-based verifiers. The pipeline test file (`test_new_tasks_pipeline.py`) should always contain both scenario A and scenario B.

---

### 25. Score Cap Gate for Tasks Requiring Multiple Independent Deliverables

**The Problem**: A task often requires two (or more) genuinely independent deliverables — e.g., a data export CSV *and* a written analysis report, or three separate export files. Points are distributed across all deliverables. But because ancillary criteria (SF ran, domain confirmed, row count, etc.) also contribute points, an agent who produces only *one* deliverable can accumulate enough total points to exceed the pass threshold even though the second deliverable was never produced.

**Example**: A task worth 100 points: 15 (app ran) + 25 (CSV structure) + 20 (domain confirmed) + 25 (written report) + 15 (specific content). An agent who exports the CSV but skips the written report scores 15+25+20+15 = 75 → passes at threshold 60, even though the report was a required deliverable.

**Why this is different from the wrong-target gate**: The wrong-target gate (Lesson 5) immediately returns score=0 when the wrong entity was acted on. Here the agent did *real work* — just incomplete work. Hard-zeroing the score would be too harsh. The right behaviour is to cap, not zero.

**Why this is different from the build-passes gate (Lesson 20)**: The build-passes gate conditionally skips one criterion unless other criteria were met. The score cap gate doesn't skip a criterion — it limits the total score ceiling when a *required* deliverable is absent.

**The Fix**: After computing the full score, check each required deliverable. If it is absent and the score exceeds `pass_threshold - 1`, cap the score:

```python
# After all scoring criteria have been computed:

# GATE: Both deliverables are required to pass.
# If the written report is missing, cap score to prevent CSV-only completion from passing.
if not result.get('report_exists', False) and score >= PASS_THRESHOLD:
    score = PASS_THRESHOLD - 1
    feedback_parts.append(
        f"Score capped at {PASS_THRESHOLD - 1}: written report is a required deliverable"
    )

passed = score >= PASS_THRESHOLD
```

**How to discover you need this gate**: Run the partial-completion pipeline test for "deliverable X missing, everything else done". If that test scenario yields `passed=True`, add a gate for deliverable X.

**Implementation checklist**:
1. Identify every *independently completable* deliverable the task requires
2. For each deliverable D, run a mock test with all other criteria satisfied but D missing
3. If the result `passed=True`, add: `if not D_present and score >= threshold: score = threshold - 1`
4. Apply gates in order from most to least important (if multiple deliverables need gates)
5. Re-run all partial tests to confirm they now return `passed=False`

**Applies to**: Any task with ≥2 independently completable deliverables where the points for non-deliverable criteria (app running, domain confirmed, row count, etc.) could combine with one deliverable's points to exceed the pass threshold.

---

### 26. Derive Pipeline Test Mock Field Names From Verifier Source, Not Intuition

**The Problem**: When writing pipeline test cases, you must construct mock JSON dictionaries that represent what the export script would produce. It is tempting to invent these field names from memory or from reading the README. But if any field name in your mock data doesn't exactly match what the verifier reads with `result.get('field_name')`, the verifier silently receives `None` (or whatever default you gave `get()`), and the test produces incorrect results — often passing when it should fail or failing with the wrong score.

**What breaks**:
```python
# Mock data written from memory:
mock = {"has_price_data": True, "row_count": 30}

# Verifier actually reads:
has_price = result.get('custom_has_price_data', False)  # reads 'custom_has_price_data'
row_count = result.get('custom_row_count', 0)           # reads 'custom_row_count'

# Result: has_price=False, row_count=0 — verifier sees empty data despite your mock
# The test may still pass for the wrong reason (score=0, passed=False "as expected" in do-nothing)
# But the full-completion test silently gets score=40 instead of 100 — looks like a verifier bug
```

**The Fix**: Before writing any mock test data, grep the verifier for every `result.get(` call to extract the canonical list of field names:

```bash
grep -oP "result\.get\('\K[^']+" benchmarks/cua_world/environments/<env>/tasks/<task>/verifier.py | sort -u
```

Use the output of this command as the keys for your mock dictionaries. Never invent field names from scratch.

**Additional check**: After writing your full-success mock data, check that your full-success scenario actually yields score=100. If it yields anything less, some field name is wrong or some mock value doesn't satisfy the verifier's condition (e.g., row count too low, size too small). Work backward from the score to find the mismatch.

```python
# Quick audit: run full-success mock and print which criteria scored 0
result = verify_my_task([], make_env(FULL_MOCK), {})
print(result['score'], result['feedback'])
# If score < 100, one or more criteria didn't fire — check field names and values
```

**Why this is a silent failure**: `result.get('nonexistent_key', False)` returns `False` without raising an exception. The verifier continues normally, simply treating the missing field as "criterion not met". No error, no warning — just incorrect test behaviour.

**Applies to**: Every pipeline test script (`test_<env>_new_tasks.py`). Always derive mock field names from the verifier source before writing test data, for every task in the pipeline.

---

### 27. Verifying GUI Apps That Produce No Structured Data Output

**The Problem**: Some GUI applications (educational software, creative tools, standalone desktop apps) have no database, no log files, no structured export API, and no config worth querying. The only observable effect of agent actions is what appears on screen and what files are written to disk. Standard verification patterns (DB queries, file structure checks, API calls) don't apply.

**The Pattern — Domain-Specific Report as Proof of Navigation**: Require the agent to produce a free-text professional report (written to `~/Desktop/<task>_report.txt` or equivalent) that must contain vocabulary only discoverable by genuinely navigating the application. The key design principle: **use the application's own vocabulary** — specific names of activities, menus, features, data labels, or internal identifiers that appear nowhere in the task description and can only be known by exploring the software.

**What makes a keyword un-gameable**:
- Generic: `"math"`, `"science"`, `"educational"` — guessable without touching the app → DON'T use these
- Specific: `"Numeration"`, `"Gravity Experiment"`, `"Canal Lock"`, `"mixing paint"` — only appear inside the app's UI → USE these

**Implementation pattern** (export_result.sh):
```bash
REPORT_FILE="/home/ga/Desktop/task_report.txt"
REPORT_MTIME=0
REPORT_EXISTS="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# Check for app-specific vocabulary (use -qi for case-insensitive, no -c)
HAS_FEATURE_A=0; HAS_FEATURE_B=0; HAS_FEATURE_C=0
grep -qi "exact feature name from app UI" "$REPORT_FILE" 2>/dev/null && HAS_FEATURE_A=1
grep -qi "another feature name from app UI" "$REPORT_FILE" 2>/dev/null && HAS_FEATURE_B=1
grep -qi "third feature name from app UI" "$REPORT_FILE" 2>/dev/null && HAS_FEATURE_C=1
```

**Verifier design**:
- Always gate on `int(report_mtime) > task_start` (timestamp check, Lesson 15)
- Require minimum file size (proxy for analytical completeness, Lesson 11 in Pattern 11)
- Award points proportional to how many specific features the agent discovered
- Pass threshold should require covering most of the required feature vocabulary (not all — an agent may miss one activity out of 10 and still have done genuine work)

**Secondary verification channel**: If the app writes a config or settings file (INI, JSON, registry), use it as an independent second signal — e.g., confirm the agent changed a setting. This is independent of the report and catches agents who fake the report but didn't interact with the app. (See also Lesson 28.)

**When to use**: Any GUI app that:
- Has no database
- Produces no structured output (no XML export, no API, no log)
- Has a rich feature vocabulary specific to its domain (unique activity names, tool names, parameter labels)

**Examples**: Educational software (GCompris, Khan Academy Desktop), creative apps (Blender, Inkscape), scientific tools with no export, standalone kiosks.

---

### 28. Desktop App Config Files: Terminate the Process Before Reading

**The Problem**: Many desktop applications (especially Qt-based apps, Java apps, and Electron apps) buffer their configuration changes in memory and only flush them to the on-disk config file when the process exits cleanly. If your `export_result.sh` reads the config file while the app is still running, you read the **stale on-disk state**, not the current in-memory state — even if the user just changed a setting through the GUI.

**What breaks**:
```bash
# In export_result.sh — reads config while GCompris/AnyApp is still running
CONFIG_VALUE=$(grep "settingName" /home/ga/.config/app/app.conf | grep -oE '[0-9]+')
# Returns the pre-change value! The app hasn't flushed to disk yet.
```

This means: if the agent changed a setting and the verifier reads the config while the app is running, the verifier sees `False` for the setting change — giving the agent zero points for work that was actually done.

**The Fix**: Kill the application process before reading its config, then add a brief sleep to ensure the flush completes:
```bash
# Kill the app gracefully so it flushes config to disk
pkill -f "gcompris-qt" 2>/dev/null || true
# Or use the shared utility if available:
kill_gcompris   # or kill_myapp — from task_utils.sh

sleep 2   # Wait for config to be written

# NOW safe to read config
CONFIG_VALUE=$(grep "settingName" /home/ga/.config/app/app.conf | grep -oE '[0-9]+')
```

**How to identify which apps have this problem**: Any app that writes settings through a framework with deferred writes:
- Qt apps (`QSettings`) — always deferred; must exit to flush
- Java apps using `Preferences` API — may be deferred
- Electron apps using `electron-store` or similar — may be in-memory until exit
- Apps using INI/TOML write libraries — check library docs

**How to tell in task_utils.sh**: If the environment has a `kill_<appname>()` function in task_utils.sh, call it before reading config. If not, `pkill -f <binary_name> && sleep 2` is the safe fallback.

**Applies to**: Any `export_result.sh` that reads an application's config/preferences/settings file as a verification signal. Always terminate the process first.

---

### 29. Efficient Live Testing: One VM Boot for All Tasks

**The Problem**: When an environment's `pre_start` hook runs a slow install (apt packages, pip installs, compilation), each VM boot takes 5–15 minutes. If you boot a new VM per task for do-nothing testing, 5 tasks = 25–75 minutes of waiting. This friction discourages thorough live testing.

**The Fix**: Boot the VM once (with any task's `task_id`), then run each subsequent task's `setup_task.sh` and `export_result.sh` manually via `exec_capture`, and call the verifier Python function directly:

```python
from gym_anything.api import from_config

# Boot once — pre_start runs (installs app), post_start runs (configures app)
env = from_config("benchmarks/cua_world/environments/<env_name>", task_id="task_1")
obs = env.reset(seed=42, use_cache=True)
runner = env._runner

# Task 1: pre_task hook already ran during reset — just run export + verify
export_out = runner.exec_capture("bash -l /workspace/tasks/task_1/export_result.sh 2>&1")
copy_fn = lambda src, dst: runner.copy_from(src, dst)
result_1 = verify_task_1([], {'copy_from_env': copy_fn}, {'metadata': {}})
assert result_1['score'] == 0 and result_1['passed'] is False

# Tasks 2-5: manually run setup then export on the SAME VM
for task_name, verify_fn in remaining_tasks:
    runner.exec_capture(f"bash -l /workspace/tasks/{task_name}/setup_task.sh 2>&1")
    runner.exec_capture(f"bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1")
    result = verify_fn([], {'copy_from_env': copy_fn}, {'metadata': {}})
    assert result['score'] == 0 and result['passed'] is False

env.close()
```

**Important caveats**:
- Task setups may conflict if they leave files, config changes, or running processes. Kill the app (if applicable) before each new task's setup.
- Timestamp checks (`int(mtime) > task_start`) still work because each `setup_task.sh` records a fresh task_start. Make sure the export runs *after* setup, not before.
- This pattern is only valid for do-nothing tests. Actual agent runs must boot fresh per task (agent state carries over otherwise).
- If tasks heavily modify shared global state (user accounts, system config), run them in a fixed order and verify that each setup resets what it needs to.

**When this doesn't work**: If individual task setups are destructive to each other's preconditions (e.g., task 2 deletes files that task 3's setup requires), you must boot separate VMs. In practice, this is rare for do-nothing tests because each setup.sh typically just resets its own task-specific state.

**Applies to**: Any environment where the `pre_start`/`post_start` install is slow (>2 minutes) and you need to do-nothing test 3+ tasks. Saves 60–80% of testing wall-clock time.

---

### 30. Use Procedure Vocabulary, Not Domain Vocabulary, in Keyword Checks

**The Problem**: When verifying analysis tasks (statistical tests, diagnostic procedures, scientific measurements), it is tempting to use domain-level terms as detection keywords — words like "cointegration", "heteroskedasticity", "panel data", "clustering". These words are **domain vocabulary**: they describe the topic but appear everywhere — in section headers, method introductions, output descriptions, and agent-written commentary — regardless of whether the specific analysis was actually performed.

**Classic example**:
```bash
# BAD: "cointegrat" is domain vocabulary — appears in ANY mention of cointegration
if grep -qiE "engle.granger|cointegrat|EG.test" "$OUTPUT_FILE"; then
    HAS_COINTEGRATION_TEST="true"
fi
# Result: an agent who writes "Cointegration Analysis: Permanent Income Hypothesis"
# as a section header triggers HAS_COINTEGRATION_TEST=true, scoring full points
# without running any cointegration test.
```

**The Fix**: Use **procedure vocabulary** — terms that appear exclusively in the actual output of the specific test or algorithm. Statistical and scientific procedures have canonical output formats with characteristic strings that only appear when the procedure was executed:

```bash
# GOOD: "engle.granger", "ADF.*resid", "residual.*unit.root" are procedure vocabulary
# — they only appear in genuine Engle-Granger test output
if grep -qiE "engle.granger|EG.test|cointegration test|ADF.*resid|resid.*ADF|resid.*unit.root" "$OUTPUT_FILE"; then
    HAS_COINTEGRATION_TEST="true"
fi
```

**How to identify procedure vocabulary**: For any specific test or algorithm, ask: "What string appears in the software's output that ONLY appears when this specific procedure ran?" Examples:
- Statistical tests: test statistic labels, critical value tables, p-value labels with the test name
- SQL operations: table names, constraint names, specific error codes
- File format operations: magic bytes, format-specific section headers
- Compiler/build steps: the specific tool's progress messages

**Corollary for two-tier verification**: When using both an export script (primary) and an independent re-analysis in the verifier (secondary bonus path), calibrate them differently:
- **Primary (export_result.sh)**: Strict procedure vocabulary. Full points only when the specific test ran.
- **Secondary (verifier.py re-analysis)**: Looser domain vocabulary is acceptable, but should award *smaller bonus points* (`score + 10`) that don't by themselves cross the pass threshold.

Misaligning these — loose primary, strict secondary — means the primary freely grants full points for topic mentions while the safety net is harder to trigger than the main path.

**Applies to**: Any `export_result.sh` that uses `grep -qiE` to detect whether a specific analysis, test, or algorithm was performed. Especially common in scientific analysis environments (statistics, chemistry, bioinformatics, finance), code review environments, and any task where the agent writes free-text output that naturally uses domain terminology.

---

### 31. Never Edit JSON Files with `sed` — It Leaves Structural Debt

**The Problem**: When a JSON field in `task.json` (or any task file) needs to be removed or changed after the fact, it is tempting to use `sed -i '/fieldname/d'` to delete the line. This is always wrong. `sed` deletes the target line but leaves the JSON structure broken: the preceding field's trailing comma becomes a dangling comma (invalid JSON), or the removed field was the last value in an object and the preceding comma is left in place.

**What breaks**:
```bash
# Original task.json hooks section:
"hooks": {
    "pre_task": "/workspace/tasks/mytask/setup.sh",
    "pre_task_timeout": 120,
    "post_task": "/workspace/tasks/mytask/export.sh",
    "post_task_timeout": 120    ← field to remove
}

# After: sed -i '/"post_task_timeout"/d' task.json
"hooks": {
    "pre_task": "/workspace/tasks/mytask/setup.sh",
    "pre_task_timeout": 120,
    "post_task": "/workspace/tasks/mytask/export.sh",    ← trailing comma: INVALID JSON
}
```

This produces a `json.JSONDecodeError` at runtime (or silently wrong behaviour if the parser is lenient). The bug often isn't caught until the task is actually tested.

**The Fix**: Always edit JSON files programmatically:

```python
# CORRECT: use Python's json module for any structural JSON edit
import json

with open('task.json', 'r') as f:
    data = json.load(f)

# Remove a field
data['hooks'].pop('post_task_timeout', None)

with open('task.json', 'w') as f:
    json.dump(data, f, indent=2)
```

Or use `jq` if available:
```bash
# jq produces structurally valid JSON output
jq 'del(.hooks.post_task_timeout)' task.json > task_fixed.json && mv task_fixed.json task.json
```

**Equally applies to `awk`, `grep -v`, and manual text editing** of JSON: any line-based text edit that removes a field can leave structural debt. The only safe approaches are a JSON-aware tool (Python json, jq, node -e) or a full rewrite of the file.

**Applies to**: Any `task.json`, `env.json`, or other JSON configuration file in the task pipeline. Also applies to any export script that assembles JSON via `cat >> /tmp/result.json` — prefer a single heredoc or Python-generated JSON over incremental append patterns.

---

### 32. `env.step([], mark_done=True)` Is One-Shot Per Episode in Test Scripts

**The Problem**: Pipeline test scripts often need to run two verifier checks in sequence — for example, a do-nothing check (nothing done, expect score=0) and a partial-completion check (minimal output injected, expect partial score). The natural approach is to call `env.step([], mark_done=True)` twice. But this fails silently: the first call finalizes the episode and runs the `post_task` hook; the second call within the same episode returns `None` or a `{}` dict for `info`, so `info.get("verifier", {})` returns empty and the test produces incorrect results (typically apparent score=-1 or a Python `AttributeError`).

**What breaks**:
```python
# First call — works correctly
_, _, _, info = env.step([], mark_done=True)
score = info["verifier"]["score"]   # e.g., 0 — correct

# Second call — info is None or {} because episode is already done
_, _, _, info2 = env.step([], mark_done=True)
score2 = info2["verifier"]["score"]   # AttributeError: 'NoneType' has no attribute 'get'
```

**The Fix**: Use `env.step` exactly once per episode, for whichever test most needs the live verifier. Validate the other scenario via the JSON content already captured in Phase 4b rather than a second env.step call.

```python
# Phase 4b: Run export script while nothing is done; capture the result JSON
export_out = runner.exec_capture(f"bash -l /workspace/tasks/{task}/export_result.sh 2>&1")
result_raw = runner.exec_capture(f"cat /tmp/{task}_result.json")
result_json = json.loads(result_raw)

# Do-nothing gate: verify via the JSON directly (no env.step needed)
assert result_json.get("report_exists", -1) == 0, "Do-nothing should have report_exists=0"

# Inject a partial state, re-run export, then use env.step ONCE for the partial test
runner.exec_capture(f"printf 'Partial content\\n' > {report_file}")
runner.exec_capture(f"bash -l /workspace/tasks/{task}/export_result.sh 2>&1")
_, _, _, info = env.step([], mark_done=True)   # Only call — for partial check
verifier = (info or {}).get("verifier", {}) or {}
assert 0 < verifier.get("score", 0) < PASS_THRESHOLD
```

**Why this works**: The Phase 4b export runs before any agent action, so `result_json` represents the do-nothing state. If `report_exists=0` (or whichever gate field is 0), the verifier gate will short-circuit to score=0. This validates the gate without consuming the one live verifier call.

**Ordering rule**: Always inject the partial state BEFORE calling `env.step`, so the single live verifier call covers the partial-completion scenario. Use Phase 4b JSON inspection to confirm the do-nothing gate.

**Applies to**: Every pipeline test script (`test_<env>_new_tasks.py`). The limitation is inherent to the Gym-Anything episode lifecycle — once `mark_done=True` is processed, the episode is over.

---

### 33. Partial Test Content Must Be Pre-Scored Before Injection

**The Problem**: When constructing the partial report for the partial-completion test (Phase 5), it is easy to accidentally include content that triggers more criteria than expected, causing the partial test to unexpectedly pass. This masks the fact that the pass threshold is too low, or that criteria weights are unbalanced.

**Classic failure mode**: A partial report that says "Meeting URL: http://... | Lobby feature: enabled" is minimal-looking, but if the verifier awards 20 (modified) + 15 (URL) + 25 (lobby) = 60 and the pass threshold is 60, the partial test passes — invalidating the test.

**What breaks silently**: When the partial test passes, the test script marks it as `[FAIL]`, but without pre-scoring you may not realize it's the *content* that's wrong versus the *verifier weights* that are wrong. Debugging is slow.

**The Fix**: Before injecting partial content, compute the theoretical score for that exact content against each criterion:

```python
# Pre-score partial content against each criterion before injecting
# For a report-based verifier with these criteria:
#   modified_after_start: 20 pts (will always be True for injected content)
#   has_url: 15 pts   (content contains "http://")
#   has_lobby: 20 pts (content contains "lobby")
#   has_muted: 15 pts (content does NOT contain "muted")
#   clipboard_url: 20 pts (clipboard empty at start → 0)
# Expected partial score: 20 + 15 + 0 + 0 + 0 = 35  (below threshold of 60) ✓

# If the expected partial score >= pass_threshold, simplify the content
# until expected partial score is roughly 20-55% of max score
```

**Minimal-content rule**: For the partial test, use the most *minimal* partial content that still demonstrates the scoring system awards non-zero points. A single criterion being satisfied is enough:

```bash
# GOOD: only URL, no other criteria terms
partial_content = "Session Report\nMeeting URL: http://localhost:8080/RoomName\nDate: 2026-03-02\n"
# Expected score: modified(20) + url(15) = 35 — unambiguously partial
```

**After changing the partial content**: Re-check the expected score by tracing through the verifier criteria one-by-one. If the expected partial score is less than the pass threshold, the content is safe to use.

**Applies to**: The partial-completion test in every pipeline test script. Particularly important for report-based verifiers (Lessons 27, 30) where the agent writes free text and multiple vocabulary terms can appear together.

---

### 34. Clipboard State as an Independent Verification Channel

**The Problem**: For applications where verification relies primarily on agent-written report files (Lesson 27 pattern), a determined adversarial agent could write a fake report containing all the correct vocabulary without actually using the application. Report-file verification has no secondary corroboration unless you use a completely independent signal.

**The Pattern**: The system clipboard provides an independent, zero-configuration verification channel. For any task that involves a "copy link", "share invite", "copy URL", or similar action, checking the clipboard in `export_result.sh` verifies that the agent actually triggered that action in the UI — not just mentioned it in a report.

```bash
# In export_result.sh — read clipboard state after agent work
CLIPBOARD=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")
CLIPBOARD_HAS_URL=0
if echo "$CLIPBOARD" | grep -qiE "localhost:8080|your-app-url|invite-token"; then
    CLIPBOARD_HAS_URL=1
fi
```

**To distinguish genuinely new clipboard content from pre-existing content**: Record the clipboard at task start in `setup_task.sh` before opening the application, save it to `/tmp/initial_clipboard`, and compare in the verifier.

```bash
# In setup_task.sh — record baseline clipboard
INITIAL_CLIP=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null | head -c 200 || echo "")
echo "$INITIAL_CLIP" > /tmp/initial_clipboard
```

**Why clipboard works as an independent signal**: The clipboard can only be changed by an action in the running application. Unlike report content (which the agent can type anything it wants), triggering a "copy meeting link" button is a specific, observable UI event. An agent who fakes the report but never clicked the share button will have stale or empty clipboard content.

**Calibrating clipboard points**: Because the clipboard can be cleared or overwritten by other actions, do not make clipboard the only path to passing. Assign it 15–25% of the total score — enough to meaningfully reward genuine sharing actions, but not required to pass if the agent completed all other subtasks.

**When clipboard is NOT a reliable signal**:
- If the application autofills the clipboard at startup (some apps do), the initial clipboard capture in setup_task.sh prevents false positives.
- If the task runs on a headless display without clipboard support (no Xvfb or xcb), `xclip` will silently fail — guard with `2>/dev/null || echo ""`.
- For tasks where copying to clipboard is NOT a required action, skip this signal entirely.

**Applies to**: Any task involving web-based or desktop applications where sharing, invite links, one-click copy, export URL, or "copy to clipboard" is a meaningful workflow action. Particularly relevant for collaboration tools (video conferencing, file sharing, document editors, ticketing systems).

---

### 35. SQLite Database Locking: Kill the App Before Direct Database Access

**The Problem**: Many desktop applications open their SQLite database with an exclusive write lock that persists for the entire session. If your `setup_task.sh` or `export_result.sh` attempts to write to (or sometimes even read from) the database while the application is running, Python or bash receives:

```
sqlite3.OperationalError: database is locked
```

The script then exits with code 1 *silently* — setup appears to "complete" (the bash wrapper continues), but zero items were actually inserted.

**What makes this hard to detect**:
- The bash heredoc wrapper around the Python block does not always propagate exit code 1 to the outer script
- The export script may still write an empty JSON (`total_items=0`) and print "Export Complete" — making it look like success
- The do-nothing test then shows 0 items, which looks like a successful baseline, masking the bug

**The Fix**: Kill the application process before any direct database access, then sleep to ensure the lock is fully released:

```bash
# In setup_task.sh — before any Python DB writes
pkill -f "application_binary_name" 2>/dev/null || true
sleep 3
echo "Application stopped for database setup"

python3 << 'PYEOF'
import sqlite3
conn = sqlite3.connect("/path/to/app.sqlite")
# ... now safe to write
PYEOF
```

**Diagnostic check**: After running setup, verify the item count directly:

```bash
# Immediately after running setup_task.sh:
sqlite3 /path/to/app.sqlite "SELECT COUNT(*) FROM items WHERE libraryID=1"
# If this returns 0 when you expect N, the DB was locked during setup
```

**How it differs from Lesson 28 (config file reads)**: Lesson 28 describes apps that *defer writes* to config files — reading the config while the app runs gives you stale data. This lesson is about *write locking* of the database file — writing to the DB while the app holds an exclusive lock fails entirely. Both require killing the app first, but for different reasons.

**Applies to**: Any `setup_task.sh` or `export_result.sh` that directly reads or writes an application's SQLite database. Common in: Zotero/Jurism, Firefox profile databases, KeePass, Thunderbird, Obsidian, and any Electron app with an SQLite backend.

---

### 36. Verify the Actual Database Schema Before Writing SQL Queries

**The Problem**: When writing SQL queries against an application's internal database, it is tempting to infer the schema from documentation, source code, or the app's conceptual model. Application databases often differ significantly from what you'd expect:

- A `tags` table may only have `(tagID, name)` — not `(tagID, name, libraryID, type)` as you'd expect from an app with multi-library support
- Junction tables (`itemTags`, `userGroups`) may lack the foreign key columns you assume belong to them
- Columns that exist in the app's API may be stored in a separate settings table, not as a column on the primary table

**What breaks**: SQL that references non-existent columns raises `OperationalError: table X has no column named Y`, causing Python to exit with code 1. If this happens inside the setup script's Python heredoc, zero items are seeded. The bash wrapper continues past the Python block, so the script prints "Setup complete" while all inserts failed silently.

**The Fix**: Before writing any SQL, boot the VM and inspect the actual schema:

```bash
# SSH into the VM, then:
sqlite3 /path/to/app.sqlite

# In the SQLite shell:
.tables                         # list all tables
.schema tablename               # see exact column definitions
SELECT * FROM tablename LIMIT 1; # see a sample row
```

**Correct pattern for filtering by library/owner through a junction table** (when the junction table lacks the expected column):

```sql
-- WRONG: assumes libraryID exists on the tags table
DELETE FROM tags WHERE libraryID = 1

-- CORRECT: join through the junction table to the table that HAS libraryID
DELETE FROM tags WHERE tagID IN (
    SELECT tagID FROM itemTags
    WHERE itemID IN (SELECT itemID FROM items WHERE libraryID = 1)
)
```

**Rule**: Never write SQL against an app's internal database without first verifying `.schema` output from a live VM. Documentation and source code are unreliable — the actual on-disk schema is ground truth.

**Applies to**: Any `setup_task.sh` or `export_result.sh` that issues SQL against an application's internal SQLite (or other embedded) database. Especially critical for reference managers, note-taking apps, email clients, and any Electron app, where the internal schema may differ significantly from the public API.

---

### 37. Always Relaunch the Application After Seeding Data

**The Problem**: Many `setup_task.sh` scripts follow this pattern:
1. Kill the application (to unlock the database)
2. Seed data directly into the database
3. Script ends — application is NOT restarted

The agent then starts its session with a blank desktop and no application running. The agent must figure out how to launch the application before it can begin the actual task. This:
- Wastes agent steps on a mechanical launch operation (not the intended work)
- Means the initial evidence screenshot shows an empty desktop instead of the application with seeded data
- Makes it harder to verify setup worked (no visual confirmation of loaded data)

**The Fix**: Always relaunch the application at the end of `setup_task.sh`, wait for it to fully initialize, and take a start screenshot:

```bash
# After seeding data into the DB:

# Relaunch the application
echo "Relaunching application..."
setsid sudo -u ga bash -c 'DISPLAY=:1 /opt/appname/appname --no-remote >> /home/ga/app.log 2>&1 &'
sleep 5

# Wait for the app to fully load and dismiss any startup alerts
if type wait_and_dismiss_app_alerts &>/dev/null; then
    wait_and_dismiss_app_alerts 30
fi

# Maximize and focus the window for better agent UX
DISPLAY=:1 wmctrl -r "AppWindowTitle" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "AppWindowTitle" 2>/dev/null || true
sleep 1

# Take start screenshot as evidence
DISPLAY=:1 scrot /tmp/task_name_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/task_name_start.png"
```

**Wait for the window before screenshotting**: Many apps have splash screens or startup sync that take 3–15 seconds. Use `wmctrl -l` to poll for the window rather than a fixed sleep:

```bash
# Wait up to 30s for app window to appear
for i in $(seq 1 30); do
    DISPLAY=:1 wmctrl -l | grep -qi "AppWindowTitle" && break
    sleep 1
done
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true
```

**Why the start screenshot matters**: Copying this screenshot in your evidence collection proves that setup worked and the seeded data is visible — not just that the Python script ran without errors. A screenshot of Jurism showing "14 items in this view" is definitive proof that 14 items were successfully seeded.

**Applies to**: All `setup_task.sh` scripts that kill the application to access its database and finish without relaunching it. The agent should find the application already running and displaying the seeded data when the task begins — never an empty desktop.

---

### 38. Offline Mock Testing Is Complete for Server-Side DB Environments

**The Observation**: For environments where the scripting seam is a server-side database (PostgreSQL, MySQL accessed via `docker exec`), all three required verification scenarios — do-nothing, wrong-target, and partial completion — can be fully tested **without booting the VM at all**.

**Why this works**: In these environments, `export_result.sh` queries the live DB, formats results into a JSON file at `/tmp/<task>_result.json`, and `verifier.py` reads that JSON via `copy_from_env`. The verifier has no direct contact with the VM — it only sees a JSON dict. This means you can construct any mock JSON dict, wire it through a `shutil.copy`-based mock, and test every verifier code path locally.

**The pattern** (works in a standard Python script, no VM required):

```python
import json, tempfile, shutil, importlib.util

def load_verifier(task_name):
    path = f'benchmarks/cua_world/environments/<env>/tasks/{task_name}/verifier.py'
    spec = importlib.util.spec_from_file_location(f'v_{task_name}', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, f'verify_{task_name}')

def run_verifier(fn, result_dict):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(result_dict, f)
        temp_path = f.name
    try:
        def mock_copy(src, dst):
            shutil.copy(temp_path, dst)
        return fn([], {'copy_from_env': mock_copy}, {})
    finally:
        os.unlink(temp_path)

# Test 1: do-nothing (all fields at baseline — False/zero)
empty_result = run_verifier(fn, EMPTY_RESULTS[task])
assert empty_result['score'] == 0 and not empty_result['passed']

# Test 2: wrong-target (base entity found but wrong name/ID → export returns mostly empty)
wrong_result = run_verifier(fn, WRONG_TARGET_RESULTS[task])
assert wrong_result['score'] == 0 and not wrong_result['passed']

# Test 3: partial completion (some criteria met, not all)
partial_result = run_verifier(fn, PARTIAL_RESULTS[task])
assert 0 < partial_result['score'] < PASS_THRESHOLD and not partial_result['passed']
```

**When this is especially valuable**: DB-backed environments often have slow first-boot times (10+ minutes for Docker image pulls), making live VM testing impractical during iterative development. The offline mock approach lets you validate all verifier logic before ever running the full environment.

**What offline testing cannot replace**: It does not test whether `export_result.sh` actually queries the right tables or produces the right JSON structure — that still requires a live VM run (at least once). The split of responsibilities: offline mocks validate verifier logic; one live run validates the export script.

**Constructing the three mock dicts**:
- **Empty**: Set all boolean fields to `False`, all counts to `0`. Run `setup_task.sh` then immediately `export_result.sh` without any agent work — the resulting JSON is your canonical empty dict.
- **Wrong-target**: Change the base entity identifier (e.g., set `project_found: False` or use a different project name). Everything that depends on the base entity cascades to False/zero automatically.
- **Partial**: Enable 30–50% of criteria. Derive field names from the verifier using `grep -oP "result\.get\('\K[^']+" verifier.py | sort -u` (Lesson 26) to ensure keys match exactly.

**Applies to**: Any environment where the scripting seam is a server-side database (PostgreSQL, MySQL, Oracle, MongoDB) accessed by the export script directly. This includes ELN/LIMS systems (SciNote, Benchling), EMR systems (OpenEMR), CRM systems, and any web app with a separate DB container.

---

### 124. Maximum-Count Gate for Specific-Subset Export Tasks

**The Problem**: When a task requires exporting a specific *subset* of content — a frame range, a date window, a record filter, a page range — the easiest agent shortcut is to export *everything* and rely on the verifier not penalizing extra content. Standard minimum-count and file-existence criteria all pass even when the agent dumped the full dataset.

**Classic example**: A task says "render only frames 1–16 for web delivery." An agent renders all 48 frames. Criteria — `frame_count >= 16` (✓), `resolution correct` (✓), `files newer than start` (✓) — all pass. The agent never trimmed anything.

**The Fix**: Before any other scoring, add a maximum-count gate when the task specifies a specific subset:

```python
# GATE: If more than ~2× the target is produced, the agent did not subset correctly.
item_count = result.get('item_count', 0)
max_allowed = metadata.get('max_item_count', target_count * 2)

if item_count > max_allowed:
    return {
        "passed": False,
        "score": 0,
        "feedback": (
            f"GATE FAIL: {item_count} items exported — task requires only ~{target_count}. "
            "Exporting the full dataset does not satisfy the subset delivery requirement."
        )
    }
```

**Calibrating `max_allowed`**: Set it at approximately 2× the target count to allow for off-by-one errors in frame/page/record numbering, but well below the total available items. If target is 16 frames and the full scene has 48, set `max_allowed = 30`.

**When to apply**: Any task whose description contains phrases like:
- "render only frames X through Y"
- "export the last N months of records"
- "deliver a trimmed version"
- "extract only [specific layer/channel/section]"
- "produce only the first/last/selected N items"

**When NOT to apply**: Tasks with a minimum-quantity requirement ("at least 24 frames"). For those, use the minimum gate from Pattern 12 in `03_verification_patterns.md`.

**Distinction from Pattern 12**: Pattern 12 (Content Volume Gate) prevents *under-delivery*. This lesson prevents *over-delivery*. They are complementary gates used in opposite task directions.

**Applies to**: Any render, export, or extraction task where the target is a specific portion — animation frame ranges, document page ranges, time-series date windows, layer/channel extraction, record ID filters.

---

### 125. Video Output Verification with ffprobe

**The Problem**: For tasks requiring a *video file* output (MP4, MOV, AVI, WebM) rather than an image sequence, standard image tools (PIL, ImageMagick) cannot validate the output. A video file can exist, have non-zero size, and still be a truncated/corrupted file or an audio-only container. PIL raises an exception on all of these without distinguishing the failure.

**The Fix**: Use `ffprobe` (part of the `ffmpeg` suite, typically pre-installed in Ubuntu environments) in `export_result.sh`:

```bash
# In export_result.sh — validate the output video
VIDEO_FILE=$(find "$OUTPUT_DIR" -maxdepth 3 \
    \( -name "*.mp4" -o -name "*.mov" -o -name "*.avi" \
       -o -name "*.webm" -o -name "*.mkv" \) \
    -type f 2>/dev/null | sort | head -1)

FFPROBE_VALID="false"
VIDEO_DURATION_SEC=0
VIDEO_WIDTH=0
VIDEO_HEIGHT=0

if [ -n "$VIDEO_FILE" ] && command -v ffprobe &>/dev/null; then
    DUR=$(ffprobe -v quiet -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
    if echo "$DUR" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        FFPROBE_VALID="true"
        VIDEO_DURATION_SEC=$(echo "$DUR" | awk '{printf "%d", $1}')
    fi
    DIMS=$(ffprobe -v quiet -select_streams v:0 \
        -show_entries stream=width,height \
        -of default=noprint_wrappers=1:nokey=0 "$VIDEO_FILE" 2>/dev/null)
    VIDEO_WIDTH=$(echo "$DIMS" | grep "^width=" | cut -d= -f2 || echo "0")
    VIDEO_HEIGHT=$(echo "$DIMS" | grep "^height=" | cut -d= -f2 || echo "0")
fi
```

**In verifier.py**: Use `ffprobe_valid` as one verification criterion. A non-zero duration confirms the file is a real, playable video. Give partial credit when the file exists and has size but ffprobe cannot read it (allows for unusual codecs):

```python
# Criterion: valid playable video file
ffprobe_valid = result.get('ffprobe_valid', False)
duration_sec = result.get('video_duration_sec', 0)
video_size_kb = result.get('video_size_kb', 0)

if ffprobe_valid:
    score += 15
    feedback_parts.append(f"Valid video: duration {duration_sec}s (ffprobe verified)")
elif video_size_kb >= min_size_kb:
    score += 5  # File exists and has size, but can't confirm playability
    feedback_parts.append("Video file present but ffprobe validation failed")
```

**Accept multiple video formats**: The agent may produce MP4, MOV, AVI, WebM, or MKV — all are valid. Use `find` with multiple `-name` patterns (see Lesson 126) rather than hardcoding one extension.

**Note**: `ffprobe` is bundled with `ffmpeg`. Check availability with `command -v ffprobe`. If absent, fall back to file-size verification only and note this in the README.

**Applies to**: Any task where the required output is a video file — animation export, video editing, screen recording, render-to-video tasks. Common environments: OpenToonz, Blender, Kdenlive, DaVinci Resolve, ffmpeg-based pipeline tasks.

---

### 126. Accept Multiple Equivalent File Formats Throughout the Task Pipeline

**The Problem**: Creative and rendering software often supports multiple equivalent output formats — OpenToonz renders PNG or TGA; video tools output MP4 or MOV; document editors export PDF or ODT. If a `setup_task.sh` cleanup only removes `.png` files, but the agent renders `.tga` files, old PNGs may remain uncleaned and inflate counts. If `export_result.sh` only searches for `.png`, it reports 0 frames for a valid TGA render — a false failure.

**The Fix**: Apply format-agnostic patterns at every stage of the pipeline:

**1. setup_task.sh — cleanup**: Delete all potentially valid formats:
```bash
find "$OUTPUT_DIR" -maxdepth 3 \
    \( -name "*.png" -o -name "*.tga" -o -name "*.tif" -o -name "*.jpg" \) \
    -delete 2>/dev/null || true
```

**2. export_result.sh — counting and dimension extraction**: Search all valid formats:
```bash
# Count any valid image format
FRAME_COUNT=$(find "$OUTPUT_DIR" -maxdepth 3 \
    \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) \
    -type f 2>/dev/null | wc -l)
FRAME_COUNT=${FRAME_COUNT:-0}

# Get dimensions from whichever format the agent used
FIRST_IMG=$(find "$OUTPUT_DIR" -maxdepth 3 \
    \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | sort | head -1)
```

**3. verifier.py and task.json**: Document that multiple formats are accepted:
```json
"metadata": {
    "accepted_image_formats": ["png", "tga", "tif"],
    "note": "Any lossless image format is acceptable for delivery"
}
```

**When to enforce a specific format**: Only when the format IS the delivery requirement — e.g., "export PNG specifically for web transparency" or "deliver TGA for the VFX pipeline DCC handoff". In those cases the format check is a legitimate verification criterion.

**General rule**: If the task goal is measured by content (correct frames at correct resolution), accept any equivalent format. Only enforce format when the format itself is part of the delivery specification.

**Also applies to subdirectory depth**: OpenToonz and similar tools sometimes create a named subfolder inside the output directory. Use `-maxdepth 2` or `-maxdepth 3` rather than `-maxdepth 1` in all `find` calls to avoid false negatives when the app creates an intermediate directory.

**Applies to**: Any task in creative/multimedia environments — image editors, 3D renderers, animation tools, video editors, document processors — where multiple output formats produce equivalent content.

---

### 127. Pre-Compute Ground Truth at Setup Time for Analytical Tasks

**The Problem**: For tasks where the agent must compute answers to analytical questions (e.g., "which city has the highest average salary?", "which manager has the most direct reports?", "what is the average salary increase on job change?"), hardcoding the expected answers in `task.json` metadata is fragile. The values may be computed incorrectly during task design, may change if the seed data is updated, and are hard to audit without re-running the queries yourself.

**The Pattern**: Run the ground truth queries inside `setup_task.sh` and write the results to `/tmp/<task>_ground_truth.json`. The verifier then loads this file (via `copy_from_env`) to compare against what the agent produced.

```bash
# In setup_task.sh — compute and store ground truth answers
python3 << 'PYEOF'
import json, <db_driver>

# Connect to DB and compute correct answers
conn = <db_driver>.connect(...)
cursor = conn.cursor()

cursor.execute("SELECT city, AVG(salary) FROM ... GROUP BY city ORDER BY 2 DESC FETCH FIRST 1 ROW ONLY")
row = cursor.fetchone()
q1_city = row[0]
q1_avg_salary = float(row[1])

ground_truth = {
    "q1_city": q1_city,
    "q1_avg_salary": q1_avg_salary,
    # ... more questions
}

with open("/tmp/<task>_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

conn.close()
PYEOF
echo "Ground truth stored to /tmp/<task>_ground_truth.json"
```

```python
# In verifier.py — load ground truth instead of using hardcoded values
import json, os

copy_from_env = env_info.get('copy_from_env')

# Load pre-computed correct answers
gt_local = '/tmp/ground_truth_local.json'
try:
    copy_from_env('/tmp/<task>_ground_truth.json', gt_local)
    with open(gt_local) as f:
        ground_truth = json.load(f)
except Exception:
    ground_truth = {}  # fall back to task.json metadata if unavailable

expected_city = ground_truth.get('q1_city') or task_info.get('metadata', {}).get('expected_q1_city', '')
```

**Why this is better than hardcoded metadata**:
- The ground truth is always consistent with the actual data in the VM
- Updating the seed data automatically updates the ground truth
- Verifier correctness is testable by comparing ground truth against agent output in the same environment
- Eliminates "the task.json says Seattle but the real answer is Toronto" class of bugs

**Dual-path fallback**: Keep a `task.json` metadata entry as a last-resort fallback for when the ground truth JSON isn't available (e.g., in unit tests). The `ground_truth.get(...) or metadata.get(...)` pattern ensures this.

**Applies to**: Any task where the expected answer is a single value derived from a database query, data analysis, or computational procedure — not a structural check like "table has 4 columns" but a factual check like "the answer is X".

---

### 128. Grant Required Privileges in setup_task.sh for Advanced Platform Features

**The Problem**: Environments with fine-grained permission systems (Oracle DB, PostgreSQL, Linux capabilities, Windows UAC, Docker security profiles) often have a task-executing user that lacks privileges for advanced features by default. If `setup_task.sh` does not explicitly grant required privileges, the agent's work will fail at runtime with cryptic errors — not because the agent wrote bad code, but because the user isn't authorized.

**Common failure modes**:
- Oracle: `CREATE TABLE ... PARTITION BY RANGE` fails with `ORA-00604: insufficient privileges` unless `CREATE TABLE` + `UNLIMITED TABLESPACE` are granted
- Oracle: `CREATE MATERIALIZED VIEW ... ENABLE QUERY REWRITE` fails without `CREATE MATERIALIZED VIEW` + `QUERY REWRITE` system privileges
- PostgreSQL: `CREATE INDEX CONCURRENTLY` requires superuser or `pg_monitor` membership
- PostgreSQL: Row-level security policies require the user to have `BYPASSRLS` or a specific policy grant
- Linux: Writing to a monitored directory may require `CAP_DAC_OVERRIDE` or group membership

**The Fix**: For each advanced feature the task requires, include the corresponding GRANT in `setup_task.sh` executed as a privileged user (DBA, superuser, root):

```bash
# Oracle example — grant privileges to the task user before the agent session starts
docker exec oracle-xe sqlplus -S system/SystemPassword@XEPDB1 << 'EOF'
GRANT CREATE MATERIALIZED VIEW TO hr;
GRANT QUERY REWRITE TO hr;
GRANT UNLIMITED TABLESPACE TO hr;
EXIT;
EOF
```

```bash
# PostgreSQL example — grant role and extension privileges
docker exec postgres psql -U postgres -c "GRANT pg_monitor TO taskuser;"
docker exec postgres psql -U postgres -c "GRANT USAGE ON SCHEMA extension_schema TO taskuser;"
```

**Rule for task design**: For every DDL statement or system call the agent must execute, ask: "Can the task user run this with default privileges?" If the answer is uncertain, test it — connect as the task user and run the command manually. If it fails, add the grant to `setup_task.sh`.

**Also applies to file system permissions**: If the task requires writing to a directory owned by another user, add a `chmod`/`chown` in `setup_task.sh` rather than assuming the agent can use `sudo`.

**Applies to**: Any environment where the agent authenticates as a non-privileged user (the standard pattern) but the task requires DDL operations, system calls, or resource access that needs explicit authorization. Especially important for database environments (Oracle, PostgreSQL, MySQL), container environments, and any task involving advanced schema features.

---

### 129. Free-Text Answer Verification Needs Partial/Fuzzy Matching

**The Problem**: Tasks that require the agent to write a report containing specific factual answers (city names, person names, percentages, counts) cannot use exact string matching in the verifier. Agents format answers differently: "Steven King", "King, Steven", "S. King", "Steven J. King", "KING" are all valid ways to write the same name. Exact match causes false negatives for correct but differently-formatted answers.

**Common failure modes**:
```python
# BAD: fails for "King, Steven" and "KING" even though both are correct
if 'Steven King' in report_text:
    score += 15
```

**The Fix**: Use a multi-level matching strategy:

```python
def _name_found(text, first, last):
    """Accept any reasonable formatting of a name."""
    text_lower = text.lower()
    # Sufficient: distinctive last name alone (rare enough to be unambiguous)
    if last.lower() in text_lower:
        return True
    # Also accept "First Last" or "Last, First"
    if f"{first.lower()} {last.lower()}" in text_lower:
        return True
    if f"{last.lower()}, {first.lower()}" in text_lower:
        return True
    return False

def _city_found(text, city):
    """Case-insensitive city name check."""
    return city.lower() in text.lower()

def _close_enough(text, expected_float, tolerance=0.02):
    """Accept any numeric value within tolerance of expected."""
    import re
    for m in re.finditer(r'[\d]+\.?[\d]*', text):
        try:
            if abs(float(m.group()) - expected_float) / max(expected_float, 1) < tolerance:
                return True
        except ValueError:
            pass
    return False
```

**For numeric answers (percentages, averages, counts)**:
- Parse all numbers from the report with regex rather than looking for one specific value
- Accept any number within ±2% relative tolerance for floating-point quantities
- Accept ±1 absolute tolerance for counts/integers (off-by-one edge cases in date boundaries)

**For text labels (city, job title, person name)**:
- Check for the most distinctive part (last name, unique city name) case-insensitively
- If the entity name is short or common (e.g., "Lee"), require a broader context match
- List all plausible synonyms / alternate spellings in a list and check any match

**Boundary case — when specificity matters**: If the answer is ambiguous without full context (e.g., there are two "Smith" managers), require the full name match. Use the uniqueness of the answer in the data to decide how much specificity to require.

**Applies to**: Any task where the agent produces a free-text report containing factual answers derived from data analysis. Particularly common in analytics, reporting, and business intelligence tasks. Also applies to export_result.sh keyword scanning — use `-qi` (case-insensitive) and scan for the distinctive substring rather than the full formatted value.

---

### Lesson 130: Verify UI Visibility of Directly-Injected DB Records

**Problem**: When seeding test data via direct SQL `INSERT` statements, records that exist in the database may not appear in the application's UI. Web applications often have:
- Status/active columns (e.g., `status = 1`, `deleted = 0`) that must be set correctly
- Required foreign-key relationships (e.g., a schedule record must have a valid `user_date_total_id`) that the ORM auto-populates but raw SQL skips
- Computed columns or denormalized caches that are only updated via the application's own data layer
- Soft-delete filtering that hides records unless the application marks them as active

**Fix**: After inserting test data via SQL, always confirm the records are visible through the application's own query path. At minimum:
- Run the same `SELECT` query the application UI executes (not a simplified raw-table query)
- If possible, do a brief UI smoke-check (screenshot of the relevant list/page) in `setup_task.sh` after seeding
- Set every status/active/deleted column explicitly in the `INSERT` — never rely on DB defaults matching the application's expected defaults

**Applies to**: Any environment where `setup_task.sh` seeds data via direct SQL into a web application's database (TimeTrex, ERPNext, OpenProject, etc.)

---

### Lesson 131: Derive App-Specific Type/Policy IDs Dynamically at Setup Time

**Problem**: Applications use lookup/reference tables (e.g., `absence_policy`, `appointment_type`, `payment_method`, `shift_template`) with numeric IDs. Hardcoding these IDs in `setup_task.sh` is fragile:
- Demo data differs between app versions, fresh installs, and after migrations
- IDs auto-increment and reset differently across environments
- A hardcoded `VACATION_POLICY_ID=10` that works locally may be `3` in the graded VM

**Fix**: Always query reference-table IDs at setup time, with a fallback default:
```bash
VACATION_POLICY_ID=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c \
    "SELECT id FROM absence_policy WHERE LOWER(name) LIKE '%vacation%' LIMIT 1;" \
    2>/dev/null | tr -d ' \n')
VACATION_POLICY_ID=${VACATION_POLICY_ID:-10}   # fallback if query fails
```

Apply the same pattern to any numeric foreign key whose value depends on pre-existing application data: policy IDs, type codes, status codes, department IDs, etc.

**Applies to**: Any task that inserts records referencing application-managed lookup tables.

---

### Lesson 132: Export Scripts Must `rm -f` Their Temp Output Files Before Writing

**The Problem**: The `pre_task` hook (`setup_task.sh`) is executed by the framework as root. Any `/tmp/` files it creates are root-owned. If `export_result.sh` later tries to write to the same paths (or to paths that were left over from a previous test run under root), the `ga` user gets `Permission denied`:

```
/workspace/tasks/my_task/export_result.sh: line 52: /tmp/my_task_result.json: Permission denied
```

This is especially likely when:
- You run the same environment multiple times with the same task (the stale files from run N are root-owned)
- `setup_task.sh` pre-writes any of the same `/tmp/` paths that `export_result.sh` will also write to
- A previous test framework run left behind root-owned temp files in a shared COW image layer

**The Fix**: At the top of every `export_result.sh`, unconditionally remove all temp files that the script will create:

```bash
#!/bin/bash
echo "=== Exporting my_task Result ==="

# Remove any stale temp files (may be root-owned from previous runs)
rm -f /tmp/my_task_result.json \
      /tmp/my_task_intermediate_a.json \
      /tmp/my_task_intermediate_b.json \
      2>/dev/null || true

source /workspace/scripts/task_utils.sh
# ... rest of export logic ...
```

**Why `rm -f` works**: Even if the files are root-owned, the `ga` user can remove them because `/tmp` is world-writable (sticky bit allows owners of the *directory* to delete files they don't own — and `/tmp` is owned by root with the sticky bit, which only prevents non-owners from deleting *each other's* files, but `rm -f` by the file's creator or by a user with write permission to the parent directory can still succeed). More precisely: the framework mounts tasks with write access, so the `ga` user has sufficient permissions.

Actually, the safe fallback that always works regardless of sticky-bit semantics:
```bash
sudo rm -f /tmp/my_task_result.json 2>/dev/null || rm -f /tmp/my_task_result.json 2>/dev/null || true
```

**Rule**: Every `export_result.sh` must begin with a cleanup of all `/tmp/<task>_*.json` files it will write, before any logic runs. This makes the export idempotent and immune to stale file ownership from prior runs.

**Applies to**: All environments where the task framework runs hooks as root (including the standard QemuApptainerRunner). This affects every task that writes intermediate JSON files to `/tmp/` during export.

---

### Lesson 133: Verifier Target Strings Must Be Copy-Pasted Verbatim From the Task Description

**The Problem**: When writing verifier comparison strings (user fullnames, layout names, system names, file paths, etc.), it is tempting to paraphrase or abbreviate from memory. Even a small deviation causes the verifier to silently reject correct agent completions:

```python
# Task description says: "Create user 'External Security Auditor' (vendor.tech@client.com)"
# Verifier written from memory:
expected_fullname = "external auditor"   # WRONG — missing "security"

# Agent creates the user exactly as specified in the task:
actual_fullname = "External Security Auditor"
# Verifier: "external security auditor".lower() != "external auditor" → 0 points
```

This is a silent bug — it does not crash, the do-nothing test still passes (the user doesn't exist), but the full-completion test fails even when the agent is correct.

**The Fix**: After writing any verifier string literal, open the task's `task.json` prompt field (or README) in a second window and visually confirm word-for-word:

```bash
# Quick audit: grep the task prompt for the exact string
grep -i "external" benchmarks/cua_world/environments/my_env/tasks/my_task/task.json

# Then check the verifier uses the same words
grep -i "external" benchmarks/cua_world/environments/my_env/tasks/my_task/verifier.py
```

**Common offenders**:
| Task says | Verifier should NOT use |
|-----------|------------------------|
| "External Security Auditor" | "External Auditor" |
| "Incident Command Center" | "Incident Commander Center" |
| "Security Operations Center" | "Security Operations" |
| "Vendor Technical Support" | "Vendor Technician" |

**Rule**: Never write verifier comparison strings from memory. Always copy-paste from the task description, then `.lower().strip()` for case/whitespace normalization. Run a `grep` comparison between the task prompt and the verifier source as a final check.

**Applies to**: Every verifier that matches user fullnames, layout names, system names, tag names, file names, or any other human-readable string the task specifies must be created with a precise name.

---

### Lesson 134: Multi-State Fields Need All-or-Nothing Verifier Gates

**The Problem**: `setup_task.sh` sometimes intentionally configures the environment in a *partial* or *intermediate* state to make the task realistic — for example:
- A camera is enabled with motion-only recording (agent must upgrade to 24/7 continuous)
- A user exists with read-only permissions (agent must upgrade to admin)
- A service is running with an insecure config (agent must apply the secure config)

A naïve verifier that checks `is_enabled` or `exists` and awards points will give the agent free partial credit for the setup script's work, even when the agent did absolutely nothing:

```python
# BAD — awards points for any enabled recording, even the setup-configured motion-only schedule
entrance = result.get("entrance_camera_recording", {})
if entrance.get("is_enabled"):          # True from setup — agent gets 10 pts for free!
    score += 10
```

This is distinct from Lesson 24's baseline-file pitfall. Here the initial state is not binary (file exists / doesn't exist) but a continuous state machine where the setup deliberately parks the environment at an intermediate position.

**The Fix**: Gate every criterion on the COMPLETE target state, not just on any partial progress:

```python
# GOOD — only awards points when fully configured to the target
entrance = result.get("entrance_camera_recording", {})
has_always = entrance.get("has_always_type", False)
is_enabled = entrance.get("is_enabled", False)
days_covered = entrance.get("days_covered", 0)

if is_enabled and has_always and days_covered >= 7:
    score += 10        # Full credit: 24/7 continuous confirmed
else:
    score += 0         # All-or-nothing: partial setup state gets 0
    feedback_parts.append(
        f"Entrance Camera: not fully configured (enabled={is_enabled}, always={has_always}) (0/10)"
    )
```

**Detection**: After writing the verifier, construct a mock result JSON that exactly mirrors the state `setup_task.sh` creates (not all-False — the actual intermediate values). Run the verifier against this mock and confirm score=0. If any intermediate-state criterion fires, make it all-or-nothing.

**Contrast with partial-credit tasks**: This lesson applies when the criterion requires a specific *target* configuration. Tasks that explicitly reward *any positive progress* (e.g., "partially migrate at least 3 of 10 items") are the exception and intentionally award intermediate points.

**Applies to**: Any task where `setup_task.sh` configures the environment at an intermediate state rather than a neutral baseline. Common in: recording/streaming configuration, permission escalation, security hardening, workflow activation, and any "upgrade" or "fix" task pattern.

---

## Design Best Practices

### 1. Start with README

Before writing any code:
1. Write the README.md describing the task
2. Document ground truth data
3. Define verification criteria
4. Get review/approval

**Why**: Forces clear thinking, catches design issues early.

### 2. Query Data First

Before defining a task, explore the full breadth of what's in the environment — not just enough to find one record to act on. Understanding the shape of the data helps you design tasks that require discovery and multi-entity reasoning rather than a single lookup.

**Why**: You can't create realistic tasks without knowing your data. And you can't create *hard* tasks without understanding what messy or inconsistent state is possible in it.

### 3. Test Setup Script Alone

Before testing the full task:
```bash
# Run setup script manually
bash /workspace/tasks/my_task/setup_task.sh

# Verify files created
ls -la /tmp/initial_* /tmp/task_*

# Check values
cat /tmp/initial_count
```

**Why**: Isolates setup issues from application issues.

### 4. Test Export Script Alone

```bash
# After some manual work in the app, test export
bash /workspace/tasks/my_task/export_result.sh

# Check output
cat /tmp/result.json | python -m json.tool  # Validates JSON
```

**Why**: Ensures export works before running full verification.

### 5. Multi-Signal Verification

Never rely on a single check:
```python
# BAD: Single check
passed = new_record_exists

# GOOD: Multiple signals
passed = (
    correct_patient and
    new_record_exists and
    values_in_range and
    timestamp_valid
)
```

**Why**: Single checks can be gamed; multiple checks require actual completion.

---

## Common Pitfalls by Task Type

### Database Tasks (Add/Update Records)

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Pre-existing records counted | "Passes" without agent work | Record baseline counts |
| Wrong patient | Appears to work but wrong target | Check patient_id FIRST |
| Stale query results | Old data in verification | Query with ORDER BY id DESC |

### File Creation Tasks

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Wrong path | File not found | Check exact path in task description |
| Permission denied | File creation fails | Ensure user owns directory |
| Content not verified | Any file passes | Check content patterns |

### Multi-Step Tasks

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Partial completion passes | 50% work gets 100% | Use multi-criterion scoring |
| Order matters | Steps done wrong order | Verify intermediate state |
| Timeout during task | Incomplete export | Increase timeout in task.json |

---

## Debugging Workflow

When a task isn't working:

1. **Check script permissions**
   ```bash
   ls -la tasks/<task>/*.sh
   ```

2. **Run setup manually**
   ```bash
   bash /workspace/tasks/<task>/setup_task.sh
   ```

3. **Check setup files**
   ```bash
   ls -la /tmp/initial_* /tmp/task_*
   cat /tmp/initial_count
   ```

4. **Run export manually**
   ```bash
   bash /workspace/tasks/<task>/export_result.sh
   cat /tmp/result.json
   ```

5. **Validate JSON**
   ```bash
   cat /tmp/result.json | python -m json.tool
   ```

6. **Check verifier locally**
   ```python
   # In Python — env.verify() does NOT exist, use step():
   # NOTE: env.step() returns a 4-tuple, NOT 5. There is no 'truncated' value.
   obs, reward, done, info = env.step([], mark_done=True)
   result = info.get("verifier", {})
   print(result)
   ```

---

### 38. Shell Commands That Trigger Real System Events Are Legitimate "Real Data"

**The Problem**: The "no synthetic data" rule (and Lesson 23) is well-understood for file-based data (fake CSVs, generated images). But task creators sometimes misclassify a different category of setup action: **running shell commands that cause the operating system or application to record real entries in its own event log or audit trail**. They worry that running `net use` or `net localgroup` in `setup_task.ps1` counts as "generating synthetic data" and therefore violates the rules.

It does not. This is a false positive.

**The Distinction**:

| Action | Category | Why |
|--------|----------|-----|
| `python3 -c "import random; writer.writerow(...)"` in setup | **Synthetic data** — FORBIDDEN | You fabricated the data yourself; it never passed through the real system |
| `net use \\localhost\IPC$ /user:baduser wrongpassword` in setup | **Real system event** — ALLOWED | The OS processed a real authentication attempt and recorded Event ID 4625 |
| `net localgroup Administrators jsmith /add` in setup | **Real system event** — ALLOWED | AD/SAM processed a real group modification and recorded Event ID 4732 |
| `python3 -c "open('C:\\AuditTestFolder\\secret.txt').read()"` in setup | **Real system event** — ALLOWED | NTFS processed a real file access and generated Event ID 4663 |

**The principle**: If the event entry is created by the operating system, application, or service itself in response to a genuine API call, it is real. You are not fabricating data — you are creating real conditions that cause the real system to record real events. The resulting entries in the Windows Security Event Log, syslog, application audit trail, or web server access log are as real as any event generated by a human user.

**Contrast with Lesson 23**: Lesson 23 is about data files you generate yourself (CSV rows, image pixels, fake records) when a download fails. That is synthetic because you fabricated the content. Triggering a real OS API call is the opposite: you invoked the real API, and the real system produced the entry.

**Examples by system**:
- **Windows Security Events**: `net use` → 4625 (failed logon); `net localgroup` → 4732 (group change); password reset → 4724
- **Linux syslog**: `logger -p auth.warning "pam_unix: authentication failure"` → real syslog entry
- **Web server access logs**: `curl http://localhost/admin` → real entry in nginx/Apache access log
- **Application audit trails**: Accessing a file via a file-open API call → real audit event in the application's own database

**Applies to**: Any `setup_task.sh` or `setup_task.ps1` that runs shell/system commands as part of creating a realistic starting state. This pattern is the primary mechanism for establishing realistic security incident scenarios in audit, SIEM, and log-analysis environments.

---

### 39. Signal-to-Noise Ratio for Very Hard Discovery Tasks

**The Problem**: A "very hard" discovery task asks the agent to identify the primary target from a mix of real data containing both signal and noise. For example: "Investigate failed logon activity and identify the account most at risk." If you seed events with counts like 10 (primary), 8 (secondary), 5 (noise), the agent cannot reliably determine the primary target. The difference between 10 and 8 is within normal variation, and the task becomes ambiguous — essentially testing luck rather than analysis quality.

**Why this matters for scoring**: Ambiguous signals produce non-deterministic scores: an agent doing the same quality of work might pass or fail depending on which slightly-higher count happened to be visible first. This is unfair and makes the benchmark result meaningless.

**The Rule**: The primary target should have **3–5× more signal** than the nearest secondary target. Noise events should be clearly smaller than both.

**Good signal design**:
```
bruteforce1:  25 failed logons  ← primary (3.1× more than secondary)
testattacker:  8 failed logons  ← secondary (clearly not primary)
wrongadmin:    5 failed logons  ← noise (well below both)
```

**Bad signal design** (ambiguous — avoid):
```
user_a:  12 events  ← primary? secondary?
user_b:  10 events  ← ambiguous
user_c:   8 events  ← barely distinguishable
```

**Designing noise deliberately**: Noise is not wasted — it forces the agent to apply judgment and prevents the task from being trivially easy. The key is making noise clearly distinguishable from the primary signal:
- Noise should be present but ≤20% of primary signal count
- "Normal" events (a legitimate user with a few failed logons due to a forgotten password) make realistic noise
- Label noise in `pre_task_events` documentation so verifiers and evidence docs are accurate

**How to choose the primary count**: The primary count should be:
1. Clearly above noise by 3–5×
2. Realistic for the occupation context (25 failed logons in a brute force scenario is plausible; 10,000 would be unrealistic for a single session)
3. Visible as dominant at a glance (an agent scanning a sorted table should immediately see 25 as the standout)

**Applies to**: Any very_hard task where the agent must discover the "most targeted", "highest risk", "most active", or "primary" entity from a list of candidates. Includes brute force detection, file access audits, group membership change investigations, and privilege escalation reviews.

---

### 40. Multi-Table-Fallback Query Pattern for Uncertain Schemas

**The Problem**: When writing `export_result.ps1` (or `export_result.sh`) for a new environment, you may not be able to inspect the live database schema during task creation. Documentation is often incomplete or out of date. The actual table names, column names, or capitalisation may differ from expectations. Queries against non-existent tables fail silently inside bash heredocs or PowerShell try/catch blocks — the result JSON is still written, but with fields missing or defaulted to "not found." This is the schema equivalent of a null pointer: no exception propagates, but all verification criteria fail.

**When this arises vs. Lesson 36**: Lesson 36 advises always booting a VM to inspect the live schema before writing queries — follow that advice whenever possible. Use the multi-table-fallback pattern only when you cannot inspect the live schema at task creation time (e.g., a Windows-hosted proprietary application that requires a running VM, a closed-source enterprise tool with no public schema documentation, or a task created in advance of environment availability).

**The Pattern**: Write queries with multiple table-name and column-name candidates. Try each variant; use the first that returns a non-empty result. Wrap each attempt in error handling to prevent a single failure from aborting the script.

**PowerShell example** (PostgreSQL via a helper function):
```powershell
function Invoke-SafeDBQuery {
    param([string]$Query)
    try { return Invoke-ADAuditDBQuery -Query $Query }
    catch { return $null }
}

$techResult = $null
$tableVariants = @(
    "SELECT username FROM TechnicianInfo WHERE username = 'myuser'",
    "SELECT username FROM technicianinfo WHERE username = 'myuser'",
    "SELECT login       FROM technician     WHERE login    = 'myuser'",
    "SELECT username FROM adap_technician  WHERE username = 'myuser'"
)
foreach ($q in $tableVariants) {
    $r = Invoke-SafeDBQuery -Query $q
    if ($r -ne $null -and $r.Trim() -ne "") { $techResult = $r; break }
}
$techExists = ($techResult -ne $null -and $techResult.Trim() -ne "")
```

**Bash/Python example** (PostgreSQL via psql):
```bash
# Try column name variants; first non-empty result wins
ROLE=$(psql -t -c "SELECT role     FROM TechnicianInfo WHERE username='myuser'" 2>/dev/null | tr -d ' ')
if [ -z "$ROLE" ]; then
    ROLE=$(psql -t -c "SELECT techRole FROM technician    WHERE login='myuser'"    2>/dev/null | tr -d ' ')
fi
```

**Document your expected variant**: In the evidence JSON file for the task, record which table name you expect to be correct. Future maintainers will thank you when adding a new schema variant if the application is upgraded.

**Failure mode to watch**: If all variants fail, the field defaults to "not found" and the criterion scores 0. Always include at minimum the table name you believe is correct as the first variant (fastest path), and add plausible alternatives as subsequent fallbacks. Do not add more than 4–5 variants — beyond that, you should just boot the VM and inspect the schema directly (Lesson 36).

**Applies to**: Any `export_result.ps1` or `export_result.sh` that queries a proprietary application's internal database (PostgreSQL, SQLite, MySQL) when the schema was not verified against a live instance during task creation. Common in Windows-hosted enterprise tools (ManageEngine products, monitoring platforms, ticketing systems).

---

## Performance Tips

1. **Minimize VM restarts**: Test multiple things in one session
2. **Cache heavy operations**: Large downloads at install time, not setup time
3. **Parallel development**: Write all task files, then test
4. **Reuse utilities**: Create shared task_utils.sh functions

---

## Task Diversity Within an Environment

### Each Task Must Have a Distinct Starting State

**Avoid having all tasks in an environment share the same base dataset.** If every task seeds the same 18 papers / 20 patients / 10 orders, the training data becomes homogeneous — an agent that has seen one task's environment has effectively already seen all the others.

**What to vary per task:**
- The *records present* (different items, different authors, different categories)
- The *initial configuration* (app settings, user preferences, filters already applied)
- The *organizational structure* (different collections, folders, tags pre-created)
- The *quantity and domain* of data (task A: 5 chemistry papers; task B: 12 history records)

**Bad pattern — all tasks share same seed:**
```
# post_start.sh seeds 18 fixed papers, always the same
setup_task_A.sh: uses papers 1–10
setup_task_B.sh: uses papers 1–18   ← agent sees exact same library
setup_task_C.sh: uses papers 1–18   ← no meaningful difference
```

**Good pattern — each task owns its starting state:**
```
setup_task_A.sh: seeds 8 biology papers, creates "Biology" collection
setup_task_B.sh: seeds 12 history papers, no collections (agent must create)
setup_task_C.sh: seeds 5 papers with corrupted metadata (agent must fix)
setup_task_D.sh: seeds 20 papers with no tags, 3 existing tags misapplied
```

**Minimum bar:** At least half of the tasks in an environment should have meaningfully different records/data from each other. Shared *schema* and *app version* is fine; shared *content* is not.

**REMINDER**: "Different data per task" means different *real* data. Do NOT achieve diversity by generating different synthetic datasets per task. Each task's data must come from real sources.

---

### App Startup Overwrites Externally-Inserted SQLite Records

When you directly manipulate an app's SQLite database in `setup_task.sh` and then **restart the app**, the app's initialization sequence overwrites your changes. Externally-inserted rows disappear silently.

```bash
# WRONG — app startup reverts the INSERT
sqlite3 /home/ga/Zotero/zotero.sqlite "INSERT INTO itemNotes ..."
pkill -f zotero && sleep 3
su - ga -c "DISPLAY=:1 zotero &"   # ← this overwrites the INSERT
```

**Fix:** Do NOT restart the app after DB manipulation. The verifier and `export_result.sh` should read the DB directly via `sqlite3` while the app remains stopped.

```bash
# CORRECT — stop app, modify DB, leave stopped; verifier reads DB directly
pkill -f zotero || true
sleep 2
sqlite3 /home/ga/Zotero/zotero.sqlite "INSERT INTO itemNotes ..."
# export_result.sh / verifier.py: sqlite3 ... "SELECT ..." — no app restart needed
```

**Affected apps:** Any desktop app that fully owns its SQLite DB (Zotero, Firefox, Thunderbird, Electron apps, etc.)

---

### `env.close()` Requires a Pause Before the Next `env.reset()`

When running multiple validation scenarios back-to-back in a single Python script, calling `env.reset()` immediately after `env.close()` causes the second VM to fail (`"VM did not respond after loadvm"`). KVM and OS resources need time to fully release.

```python
# WRONG — second reset fails
env.close()
env2 = from_config(task_dir, task_id="scenario_2")
env2.reset(seed=42, use_savevm=True)   # → "VM did not respond after loadvm"

# CORRECT — pause after close
def close_env(env, pause=20):
    try:
        env.close()
    except Exception as e:
        print(f"(close error ignored: {e})")
    time.sleep(pause)   # allow KVM/OS to fully release resources

close_env(env)
env2 = from_config(task_dir, task_id="scenario_2")
env2.reset(seed=42, use_savevm=True)   # succeeds
```

**Rule of thumb:** Always use a `close_env()` wrapper with `time.sleep(20)` in validation scripts that run multiple QEMU scenarios sequentially.

---

### REST API Clients: `curl -s` Exits 0 for HTTP 4xx/5xx

`curl -s` (silent mode) exits with code 0 regardless of the HTTP response status. When `setup_task.sh` discards REST API output with `>/dev/null`, write failures are completely invisible — the script happily prints "Inserted" while the database actually received nothing.

```bash
# WRONG — always prints "Inserted" even if OrientDB returns HTTP 500
curl -s -X POST ... -d '{"command":"INSERT INTO ..."}' \
  http://localhost:2480/command/db/sql >/dev/null \
  && echo "Inserted" || echo "WARNING"   # ← '||' branch never reached
```

**Why the `||` branch never fires:** `curl -s` exits 0 on HTTP 500. The `&&` branch runs. The "WARNING" is never printed.

**Diagnosis:** Temporarily capture and print the response body:
```bash
RESP=$(curl -s -X POST -u user:pass -H "Content-Type: application/json" \
  -d '{"command":"INSERT INTO Hotels SET Name=..."}' \
  http://localhost:2480/command/demodb/sql)
echo "Response: $RESP"   # Shows actual error: "UNIQUE constraint violated..."
```

Or use Python (which raises on HTTP 4xx/5xx by default):
```python
import urllib.request, urllib.error, json
req = urllib.request.Request(url, data=..., headers=..., method="POST")
try:
    with urllib.request.urlopen(req) as r:
        print(json.loads(r.read()))
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()[:300]}")  # shows the actual error body
```

**Rule:** Any `setup_task.sh` that uses `curl -s` to write to a REST API must validate with a count query *after* all inserts to confirm the expected number of records was created. If the count is wrong, the script must exit non-zero.

---

### UNIQUE Index Interference When Seeding Into Pre-Populated Databases

When an environment's base database already contains records with non-null values in a UNIQUE-indexed column, inserting records that omit that column (leaving it as null) causes a silent cascade failure: only the **first insert succeeds**, all subsequent ones fail with a UNIQUE constraint violation.

**How it happens:**
1. Pre-existing records occupy the UNIQUE index with non-null values (e.g., OSM IDs)
2. Your canonical seed inserts don't specify that column → null
3. INSERT #1 with null: succeeds (null slot was empty)
4. INSERT #2 with null: fails — null is already "taken" as a unique value
5. All remaining inserts fail silently (especially when output is discarded with `>/dev/null`)

```
# Example: OrientDB DemoDB has Hotels with UNIQUE index on Hotels.Id (non-null OSM IDs)
INSERT INTO Hotels SET Name='Hotel A', Country='Germany'   → HTTP 200 OK   (null Id #1)
INSERT INTO Hotels SET Name='Hotel B', Country='France'    → HTTP 500 ERROR (null Id #2, UNIQUE violation)
INSERT INTO Hotels SET Name='Hotel C', Country='UK'        → HTTP 500 ERROR (null Id #3, same)
```

**Prevention:** Before writing `setup_task.sh`, inspect the target schema for UNIQUE constraints:
```bash
# Generic: check schema/indexes before inserting
curl -s -u user:pass http://localhost:2480/database/demodb | python3 -c "
import json, sys
d = json.load(sys.stdin)
for cls in d.get('classes', []):
    for idx in cls.get('indexes', []):
        if idx.get('type') == 'UNIQUE':
            print(f\"UNIQUE index: {idx['name']} on {cls['name']}\")
"
```

**Fix options:**
```bash
# Option A: Drop the UNIQUE index before seeding (safest)
orientdb_sql "demodb" "DROP INDEX Hotels.Id" >/dev/null 2>&1 || true
# Now all inserts with null Id succeed

# Option B: Provide explicit unique values for the indexed column
orientdb_sql "demodb" "INSERT INTO Hotels SET Id=10001, Name='Hotel A', Country='Germany'"
orientdb_sql "demodb" "INSERT INTO Hotels SET Id=10002, Name='Hotel B', Country='France'"
```

**Applies to:** Any REST-based database (OrientDB, Elasticsearch, MongoDB, Couchbase) with pre-seeded "demo data" that defines UNIQUE constraints. Also applies to relational databases accessed via REST proxies. The pattern is especially treacherous because the first insert succeeds, making it look like the setup is working.

---

### Graph Databases: Use Vertex-Aware Delete, Not Plain DELETE FROM

In graph/property-graph databases (OrientDB, Neo4j, ArangoDB, TigerGraph, etc.), vertex records (nodes) typically have connected edges. Using a plain `DELETE FROM ClassName WHERE condition` command fails — often with HTTP 500 — when the target vertices have connected edges, because it would leave orphaned edges which the database rejects.

**Always use the database's vertex-aware delete operation**, which deletes both the vertex and all its edges:

| Database | Wrong | Right |
|----------|-------|-------|
| OrientDB | `DELETE FROM Hotels WHERE Country IS NULL` | `DELETE VERTEX Hotels WHERE Country IS NULL` |
| Neo4j (Cypher) | `MATCH (n:Hotel) WHERE n.Country IS NULL DELETE n` | `MATCH (n:Hotel) WHERE n.Country IS NULL DETACH DELETE n` |
| ArangoDB | `FOR v IN Hotels FILTER v.country == null REMOVE v IN Hotels` | Use `graph.vertexCollection().remove()` or remove edges first |

```bash
# OrientDB setup_task.sh pattern:
# WRONG — fails with HTTP 500 if hotels have HasStayed edges
orientdb_sql "demodb" "DELETE FROM Hotels WHERE Country IS NULL" >/dev/null 2>&1 || true

# RIGHT — cleans up connected edges automatically
orientdb_sql "demodb" "DELETE VERTEX Hotels WHERE Country IS NULL" >/dev/null 2>&1 || true
```

**Note:** This does NOT apply to edge classes (e.g., HasVisited, HasStayed). Edge records don't have their own edges, so `DELETE EDGE HasVisited` or `DELETE FROM HasVisited` both work for edges. Only vertex/node classes need the vertex-aware delete.

**Symptom of the problem:** `DELETE FROM` returns HTTP 500 with a message like "Cannot delete record because it is a vertex and has edges." The `|| true` in setup scripts masks this, leaving all the Italian/demo records in place and causing downstream count checks to fail.

---

### 13. Desktop / File-Based Environments Need Different Verification Strategies

**The Problem**: The patterns in this guide (and `03_verification_patterns.md`) are heavily oriented toward database-backed web applications — query counts, check record IDs, compare before/after DB state. Desktop application environments produce *files* as output, not database records. The standard baseline-recording and wrong-target patterns don't directly apply.

**Key differences for file-based tasks**:

| Web/DB Task | File-Based Task |
|---|---|
| Baseline = initial record count | Baseline = file doesn't exist yet |
| Wrong-target = wrong record ID | Wrong-target = N/A (agent creates the file) |
| Verify via SQL query | Verify via file parsing (XML, CSV, JSON, binary) |
| Export reads DB | Export reads output file |

**Patterns that transfer well**: Multi-criterion scoring, value range validation, do-nothing test (score=0).

**Patterns that need adaptation**: Baseline recording becomes "file doesn't exist before task starts." Wrong-target rejection is replaced by structural complexity gates (see `03_verification_patterns.md` Pattern 9) and cross-reference checks (Pattern 10).

**Rule**: When creating tasks for a desktop app, think "what files does the agent produce?" and verify those files structurally, not just by existence.

---

### 14. "Build From Scratch" vs "Modify Existing" Task Design

**The Problem**: Many task designs assume the agent modifies something that already exists (edit a record, update a config, fix a bug). "Build from scratch" tasks — where the agent creates an entire artifact from nothing — need different setup and verification.

**Setup differences**:
```bash
# "Modify" task: setup creates the artifact, agent changes it
setup_task.sh:
    generate_broken_file /home/ga/project_file.xml   # Agent fixes this

# "Build" task: setup ensures a clean slate, agent creates everything
setup_task.sh:
    rm -f /home/ga/project_file.xml    # Agent creates this
    rm -f /home/ga/data.csv            # Agent creates this too
```

**Verification differences**:
- "Modify" tasks can diff before/after states
- "Build" tasks need structural validation: minimum element counts, required sections, content patterns, file size floors (see `03_verification_patterns.md` Pattern 9)

**Mix both types** within an environment for diversity. A good environment has some "fix/modify" tasks and some "create from scratch" tasks.

---

### 15. Planted-Bug Debugging Tasks

**The Problem**: Creating realistic "fix the bug" tasks requires carefully planting bugs that are discoverable but non-trivial.

**Pattern**: Use `setup_task.sh` to programmatically generate a broken artifact with N intentional bugs. Each bug should be independently verifiable.

```bash
# setup_task.sh generates a broken config/project file with planted bugs
python3 << 'PYEOF'
import json

config = {
    "database": {
        "host": "localhsot",       # Bug 1: typo in hostname
        "port": "five-four-three", # Bug 2: port should be integer 543
        "timeout": 0,              # Bug 3: zero timeout = instant failure
    },
    "logging": {
        "level": "DEUBG",          # Bug 4: typo in log level
        "output": "/dev/null",     # Bug 5: logs go nowhere
    }
}

with open("/home/ga/app_config.json", "w") as f:
    json.dump(config, f, indent=2)
PYEOF
```

**Verification**: Check each bug independently:
```python
# verifier.py
bugs_fixed = 0
if config["database"]["host"] == "localhost":    bugs_fixed += 1  # Bug 1
if isinstance(config["database"]["port"], int):  bugs_fixed += 1  # Bug 2
if config["database"]["timeout"] > 0:            bugs_fixed += 1  # Bug 3
if config["logging"]["level"] in VALID_LEVELS:   bugs_fixed += 1  # Bug 4
if config["logging"]["output"] != "/dev/null":   bugs_fixed += 1  # Bug 5

score = (bugs_fixed / 5) * 70  # 70 programmatic points
```

**Design tips**:
- Each bug should require understanding different concepts (syntax, types, logic, domain knowledge)
- Bugs should be findable by running/inspecting the artifact — not hidden in non-functional dead code
- The agent should produce a *fixed copy* (not edit in place) so the original broken file serves as a reference
- Works for any structured file: XML configs, JSON project files, YAML pipelines, INI settings, scripts with logic errors
- **Note on data**: Planting bugs in a config/project file is NOT the same as generating synthetic data. The config file structure here is a task artifact (like a broken document to fix), not input data. The distinction: if the task is "fix this broken config," the config is the task — creating it with bugs is fine. But if the task is "analyze this astronomical image," the image must be a real observation, not synthetic noise generated with numpy.

---

### 16. Bash Booleans Break Inline Python in Export Scripts

**The Problem**: Lesson 12 recommends using `python3 -c "..."` for complex analysis in export scripts. Pattern 6 (`03_verification_patterns.md`) shows using bash variables like `FILE_EXISTS="true"` / `"false"` — which is valid inside JSON heredocs (JSON uses lowercase `true`/`false`). But when you combine these patterns and interpolate bash boolean variables into inline Python, the script fails silently:

```bash
FILE_EXISTS="false"
HAS_RESULT="true"

# BAD — bash 'false' and 'true' are NOT valid Python identifiers
python3 -c "
result = {
    'file_exists': $FILE_EXISTS,     # NameError: name 'false' is not defined
    'has_result': $HAS_RESULT,       # Works by accident: 'true' is also undefined
}
"
```

**Why it's insidious**: When `$FILE_EXISTS` is `"true"`, the script also fails (`true` is not a Python keyword), but in practice the do-nothing test path often only hits the `"false"` branch. The bug may not surface until the partial-completion test or a real agent run.

**The Fix**: Compare as strings instead of interpolating as bare identifiers:

```bash
# GOOD — string comparison produces Python True/False
python3 -c "
result = {
    'file_exists': '$FILE_EXISTS' == 'true',
    'has_result': '$HAS_RESULT' == 'true',
}
"
```

**Alternative**: Use a `python3 << 'PYEOF'` heredoc (which prevents all bash variable expansion) and pass values through files or environment variables:

```bash
echo "$FILE_EXISTS" > /tmp/_file_exists
python3 << 'PYEOF'
file_exists = open("/tmp/_file_exists").read().strip() == "true"
PYEOF
```

**Rule**: Any time you see bare `$BASH_VAR` in a `python3 -c` block where the variable holds `"true"` or `"false"`, wrap it in quotes: `'$BASH_VAR' == 'true'`. Alternatively, use integer 0/1 in bash (valid in both Python and JSON) instead of string booleans.

---

### 17. Verifier Fault Isolation: Wrap Each Criterion in try/except

**The Problem**: Pattern 3 (`03_verification_patterns.md`) shows multi-criterion scoring with independent criteria, but the example uses simple `if/else` checks on exported JSON fields. In practice — especially for desktop/file-based tasks — each criterion may involve `copy_from_env`, file parsing, or SQLite queries that can raise exceptions. If criterion 2 crashes, criteria 3–5 never execute and the agent gets 0 points even though it completed 80% of the task.

**What breaks**:
```python
# BAD: one failure kills everything
def verify_task(traj, env_info, task_info):
    score = 0
    copy_from_env = env_info['copy_from_env']

    copy_from_env(remote_bsp, local_bsp)      # works
    score += check_file_size(local_bsp)        # +20
    copy_from_env(remote_screenshot, local_ss) # FAILS — FileNotFoundError
    score += check_screenshot(local_ss)        # never reached
    score += check_measurements(local_bsp)     # never reached
    score += check_annotations(local_bsp)      # never reached
    # Agent did measurements + annotations but scores 20/100
```

**The Fix**: Wrap each criterion in its own try/except so failures are isolated:
```python
# GOOD: each criterion scores independently
def verify_task(traj, env_info, task_info):
    score = 0
    feedback = []
    copy_from_env = env_info['copy_from_env']

    # Criterion 1: Project file exists and is substantial (20 pts)
    try:
        copy_from_env(remote_bsp, local_bsp)
        if os.path.getsize(local_bsp) > 100_000:
            score += 20
            feedback.append("Project file OK")
        else:
            feedback.append("Project file too small")
    except Exception as e:
        feedback.append(f"Project file not found: {e}")

    # Criterion 2: Screenshot captured (15 pts)
    try:
        copy_from_env(remote_screenshot, local_ss)
        if os.path.getsize(local_ss) > 50_000:
            score += 15
            feedback.append("Screenshot OK")
    except Exception:
        feedback.append("Screenshot not found")

    # Criterion 3: Measurements in project file (25 pts)
    try:
        # Even if criterion 2 failed, this still runs
        conn = sqlite3.connect(local_bsp)
        rows = conn.execute("SELECT COUNT(*) FROM measurements").fetchone()[0]
        if rows >= 3:
            score += 25
    except Exception:
        feedback.append("No measurement data found")

    # ... remaining criteria ...
```

**Why this matters**: For any task where verification involves multiple independent file operations (copy, parse, query), a single missing file should not zero out the entire score. This pattern is especially critical for desktop applications where the agent may complete 4 of 5 subtasks but fail to save one output file.

**Rule**: If your verifier has N criteria and any of them involve I/O (file copy, file read, DB query), each criterion MUST be in its own try/except block. The total score should reflect what the agent actually accomplished, not what the verifier happened to check before crashing.

---

### 18. Many "Proprietary" Desktop File Formats Are Standard Formats Underneath

**The Problem**: Desktop applications often save projects in formats with custom extensions (`.bsp`, `.gnumeric`, `.ods`, `.kdbx`, `.zotero`, etc.) that appear opaque. Task creators assume they can only verify these files by checking existence and size (Pattern 6), missing an opportunity for deep structural validation.

**The Insight**: Many of these formats are actually well-known formats under the hood:

| Custom Extension | Actual Format | How to Inspect |
|---------|---------------|----------------|
| `.bsp` (Blue Sky Plan) | SQLite database | `sqlite3 file.bsp ".tables"` |
| `.ods` (LibreOffice) | ZIP containing XML | `unzip -p file.ods content.xml` |
| `.gnumeric` | Gzipped XML | `zcat file.gnumeric \| xmllint ...` |
| `.kdbx` (KeePass) | Custom binary with known header | Check magic bytes + structure |
| Firefox/Thunderbird profiles | SQLite databases | `sqlite3 places.sqlite "SELECT ..."` |
| `.sla` (Scribus) | Plain XML | Direct XML parsing |
| `.qgs` (QGIS) | Plain XML | Direct XML parsing |

**How to use in verifiers**:
```python
# Instead of just checking file size:
if os.path.getsize(output_file) > 100_000:
    score += 10  # weak: any large file passes

# Crack it open and validate structure:
try:
    conn = sqlite3.connect(output_file)
    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    if 'measurements' in tables:
        count = conn.execute("SELECT COUNT(*) FROM measurements").fetchone()[0]
        if count >= 3:
            score += 25  # strong: verified actual measurement data exists
    conn.close()
except sqlite3.DatabaseError:
    pass  # not a SQLite file, fall back to size check
```

**How to discover the format**: Before writing the verifier, create a sample output file in the app and then probe it:
```bash
file output.bsp                          # "SQLite 3.x database"
file output.ods                          # "OpenDocument Spreadsheet"
xxd output.mystery | head -5             # check magic bytes
sqlite3 output.bsp ".tables" 2>/dev/null # succeeds if SQLite
unzip -l output.ods 2>/dev/null          # succeeds if ZIP
```

**Rule**: When designing verifiers for desktop app output, always probe the file format first. If it's SQLite, ZIP, XML, or JSON underneath, your verifier can perform deep structural validation — checking specific tables, element counts, attribute values — rather than relying on superficial size/existence checks. This dramatically strengthens the verifier against gaming.

---

## Lesson 19: Calibrate Pass Thresholds Against Subtask Combinations

**Problem**: Multi-criterion verifiers assign points to independent subtasks (e.g., 5 criteria × 20 points each = 100 total). If the pass threshold is set carelessly, an agent can "pass" by completing only prerequisite or intermediate steps without ever producing the final deliverable.

**Example**: A task requires steps A → B → C (prerequisites, 20 pts each = 60) and then D + E (final deliverables, 25 + 15 = 40). If `passed = score >= 60`, an agent that does all prerequisites but never produces the actual output still passes.

**How to calibrate**:
1. **Enumerate meaningful subtask combinations** — list which subsets of criteria an agent might satisfy without completing the task's primary goal
2. **Compute the maximum "should not pass" score** — the highest score achievable by completing only prerequisite/intermediate work
3. **Set the threshold above that score** — typically 5–10 points above the maximum "should not pass" combination

```python
# BAD: threshold equals the sum of prerequisite criteria
# Prerequisites alone (60 pts) exactly meet the threshold
passed = score >= 60

# GOOD: threshold requires at least some final deliverable work
# Prerequisites alone (60 pts) don't pass; need >= 70
passed = score >= 70
```

**Validation method**: During partial completion testing (Phase 5), construct mock result data that satisfies only the prerequisite criteria and verify `passed=False`. Then add one final-deliverable criterion and verify `passed=True`. If the prerequisite-only mock passes, raise the threshold.

**Rule**: Before finalizing any verifier, explicitly check: "Can an agent reach the pass threshold by completing only setup/intermediate steps without the primary deliverable?" If yes, raise the threshold or redistribute point weights so the final deliverable is required to pass.

---

### 20. Mock-Based Verifier Testing Without a Running VM

**The Problem**: Phase 5 of the checklist requires partial completion tests — inject partial results and verify the score is 20–60% with `passed=False`. The obvious approach is to run the VM, manually complete part of the task, and then call the verifier. This is slow (minutes per test), fragile (requires UI interaction), and doesn't scale to 5+ tasks.

**The Fix**: Test verifiers entirely on the host by mocking `copy_from_env` and injecting result JSONs:

```python
import json, tempfile, os, importlib.util

# 1. Write a partial result JSON to the VM via SFTP
partial_result = {
    "file_exists": True,
    "valid_format": True,
    "element_count": 3,       # Below threshold of 10
    "has_required_section": False,
}
sftp.file("/tmp/task_result.json", "w").write(json.dumps(partial_result))

# 2. Create a copy_from_env that reads from the VM via SFTP
def mock_copy_from_env(remote_path, local_path):
    sftp.get(remote_path, local_path)

# 3. Load and call the verifier directly
spec = importlib.util.spec_from_file_location("v", "path/to/verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

result = mod.verify_task_name(
    traj=[],
    env_info={"copy_from_env": mock_copy_from_env},
    task_info={"metadata": {...}},
)

assert not result["passed"]
assert 20 <= result["score"] <= 60
```

**Why this is powerful**:
- Tests run in seconds, not minutes — no VM boot needed (just an SSH connection to a running VM)
- You can test many partial-completion scenarios rapidly (one criterion missing, two missing, wrong values, etc.)
- The verifier code runs exactly as it would in production — no special test mode
- If the verifier also does independent file re-analysis (Pattern 8), those checks naturally fail/skip since the real file doesn't exist, exercising the fallback path

**Design your verifiers to support this**: If a verifier's independent analysis (Pattern 8) fails, it should fall back to the export JSON rather than crashing. This makes mock testing straightforward — inject a JSON that says "file exists, here are the parsed values" and the verifier uses those values without needing the actual file.

**Fully offline variant (no VM at all)**: If your verifier only reads the export JSON (no Pattern 8 independent re-analysis), you don't even need SFTP. Mock `copy_from_env` as a local file copy:

```python
import shutil

# Write result JSON to a local temp file
tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
json.dump(partial_result, tmp); tmp.close()

def mock_copy_from_env(remote_path, local_path):
    shutil.copy2(tmp.name, local_path)  # No VM, no SSH — just a local copy

result = mod.verify_task_name([], {"copy_from_env": mock_copy_from_env}, task_info)
os.unlink(tmp.name)
```

This runs in milliseconds and is ideal for testing all three scenarios (do-nothing, partial, full) across many tasks in a single script.

**Rule**: Before writing a single setup script, write the verifier and test it with 3 mock result JSONs: do-nothing (all false), partial (some true), and ideal (all true). This catches scoring bugs before you ever touch the VM.

---

### 23. Task Diversity in Single-Dataset Environments

**The Problem**: The diversity principle (see "Task Diversity Within an Environment" above) says each task should start from meaningfully different data. This works well for database-backed applications where you can seed different records per task. But some environments are inherently single-dataset: medical imaging (one CT scan), audio editors (one audio file), 3D modeling (one mesh), scientific instruments (one dataset). You cannot create "different patients" when there is only one DICOM series.

**The Workaround**: When the input data is fixed, achieve diversity by varying the **task type** rather than the data:

```
# BAD: all tasks do the same category of work on the same data
task_1: segment bones from CT scan
task_2: segment soft tissue from CT scan
task_3: segment airways from CT scan
# Agent sees identical starting state for all three

# GOOD: tasks span different application feature areas
task_1: segment + export 3D mesh (Export workflow)
task_2: create two different tissue masks + save project (Segmentation workflow)
task_3: place measurements + save project (Measurement workflow)
task_4: export OBJ model + capture 3D screenshot (Multi-output workflow)
task_5: adjust window/level + create soft tissue mask (Configuration + segmentation)
```

**Why this still produces diversity**: Even though the underlying dataset is the same, each task exercises a different part of the application — different menus, different tools, different output formats. An agent that has seen one task's solution has NOT effectively seen the others, because the UI workflows and verification criteria are completely different.

**When this is acceptable**: Single-dataset environments are common in imaging, scientific computing, and media editing. The fixed-data limitation is inherent to the domain (a radiologist works on one patient's scan at a time). As long as tasks span different *features* of the application, the benchmark still tests meaningful capabilities.

**When it is NOT acceptable**: If the environment is database-backed or can load different files, you should still vary the data. A web app with 50 patients should NOT have all tasks operate on patient #1. Only use the single-dataset workaround when the environment genuinely has one fixed dataset.

**CRITICAL**: Even in single-dataset environments, the data itself must be REAL. Use real DICOM scans, real audio files, real FITS observations, real CSV datasets — from public repositories, sample data bundled with the software, or standard benchmark datasets. Do NOT generate synthetic data with scripts as a workaround for not having enough real data. If you cannot find real data, find a different task design that works with the real data you do have.

---

### 24. Gate Verifiers Against "Always-True" Criteria

**The Problem**: Desktop app tasks typically have `setup_task.sh` launch the application so the agent sees the right starting state. If your verifier includes a criterion like "application is running" (5–10 points), that criterion is *unconditionally true* after setup — even in the do-nothing test. The do-nothing test then returns a non-zero score, violating the Phase 5 requirement that do-nothing = score 0.

This is distinct from Lesson 19 (threshold calibration). Even if the threshold is correctly calibrated, a non-zero do-nothing score indicates a verifier bug — the verifier is rewarding the *setup script's* work, not the *agent's* work.

**Common always-true criteria**:
- "Application is running" (setup always launches it)
- "Correct project loaded" (setup always loads it)
- "Expected files are present" (setup always copies them)
- "Environment is configured" (post_start always does this)

**The Fix — Output-Existence Gate**: At the top of the verifier, before evaluating *any* criteria, check whether the agent's primary output artifacts exist. If none do, return score=0 immediately:

```python
def verify_task(traj, env_info, task_info):
    # ... copy and parse result JSON ...

    output_file = result.get('output_file', {})
    report_file = result.get('report_file', {})

    # GATE: if no primary output exists, no work was done
    if not output_file.get('exists') and not report_file.get('exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files found"
        }

    # Now safe to evaluate all criteria, including always-true ones
    score = 0
    # ... criterion 1: output file quality (25 pts) ...
    # ... criterion 2: report content (25 pts) ...
    # ... criterion N: application running (10 pts) ...  ← only reached if gate passed
```

**Why not just remove the always-true criterion?** Because it provides useful diagnostic signal when the agent *partially* completes the task. If an agent creates output files but the app crashed mid-task, the missing "app running" points tell you something went wrong. The gate ensures these points are only awarded when there's evidence of real work.

**Rule**: After writing any verifier, mentally run through the do-nothing scenario: "What criteria would be true if the agent did absolutely nothing after setup?" If any criterion is unconditionally true, add an output-existence gate before all criteria. Then re-run the do-nothing test to confirm score=0.

---

### 235. Use the Application's Own CLI/Scripting Engine for Setup and Export

**The Problem**: Desktop application tasks produce native-format output files (`.blend`, `.xcf`, `.ods`, `.qgs`, `.sla`, etc.). Lesson 18 explains that many of these are standard formats underneath (SQLite, XML, ZIP), so you can parse them with generic tools. But some native formats are truly opaque binary (e.g., Blender `.blend` files, Photoshop `.psd`, proprietary project files) — and even for the ones that *are* parseable, the application's own understanding of its file format is always more reliable than your hand-rolled parser.

**The Insight**: Many desktop applications have a **headless or batch mode** that lets you run the application itself — without a GUI — to analyze or manipulate its native files. This is far more robust than parsing the file format yourself, because the application uses the same code paths it uses during normal operation.

**Common applications with headless/scripting modes:**

| Application | Headless Command | Use Case |
|---|---|---|
| Blender | `blender --background file.blend --python-expr "..."` | Parse scenes, count objects, check materials, modify state |
| GIMP | `gimp -i -b '(script-fu-console-eval ...)'` | Image analysis, layer inspection |
| LibreOffice | `libreoffice --headless --convert-to csv file.ods` | Spreadsheet/document conversion and inspection |
| Inkscape | `inkscape --actions="..." file.svg` | SVG manipulation and export |
| QGIS | `qgis_process run algorithm ...` | Geospatial analysis without GUI |
| FFprobe/FFmpeg | `ffprobe -v quiet -print_format json file.mp4` | Audio/video metadata and validation |
| ImageMagick | `identify -verbose file.png` | Image format, dimensions, color stats |
| R / Rscript | `Rscript -e "..."` | Statistical output validation |
| Gnuplot | `gnuplot -e "..."` | Plot data inspection |

**Using it in setup_task.sh** (create or modify the starting state):
```bash
# Use Blender's own Python API to programmatically modify a .blend file
blender --background /home/ga/project.blend --python-expr "
import bpy
# Remove all lights to create the task starting state
for obj in [o for o in bpy.data.objects if o.type == 'LIGHT']:
    bpy.data.objects.remove(obj)
bpy.ops.wm.save_mainfile()
" 2>/dev/null
```

**Using it in export_result.sh** (analyze the agent's output):
```bash
# Use Blender headlessly to inspect the agent's output file
blender --background /home/ga/output.blend --python-expr "
import bpy, json
scene = bpy.context.scene
result = {
    'light_count': len([o for o in bpy.data.objects if o.type == 'LIGHT']),
    'mesh_count': len([o for o in bpy.data.objects if o.type == 'MESH']),
    'materials': {m.name: list(m.diffuse_color) for m in bpy.data.materials},
    'render_engine': scene.render.engine,
    'resolution_x': scene.render.resolution_x,
}
with open('/tmp/scene_analysis.json', 'w') as f:
    json.dump(result, f, indent=2)
" 2>/dev/null
```

**Why this is better than manual parsing:**
- The application understands its own format completely — no edge cases missed
- Works for opaque binary formats that have no standard parser
- Uses the same code the application uses to load files, so if the app can open it, your analysis is accurate
- Many apps expose a rich scripting API (Blender's `bpy`, GIMP's Script-Fu, LibreOffice's UNO) that lets you query arbitrarily detailed properties

**When to fall back to Lesson 18 (manual parsing):** If the application does not have a headless mode, or if installing/running the full application adds too much overhead to the export step. In those cases, use the format knowledge from Lesson 18 (SQLite, XML, ZIP) instead.

**Rule**: Before writing any export script for a desktop application task, check if the application has a headless/batch/scripting mode. If it does, use the application itself to analyze the agent's output files — it's always more accurate and robust than parsing the format yourself.

---

## Lesson 24: PowerShell `Out-File` writes UTF-8 BOM that breaks Python `json.load()`

On Windows environments, PowerShell's `Out-File -Encoding utf8` (and `ConvertTo-Json | Out-File`) prepend a UTF-8 Byte Order Mark (BOM: `\xef\xbb\xbf`) to the output. When the verifier reads this JSON on the host with Python's `json.load()`, it fails:

```
json.decoder.JSONDecodeError: Unexpected UTF-8 BOM (decode using utf-8-sig)
```

**Fix in verifier.py**: Always open files from Windows VMs with `encoding='utf-8-sig'`:
```python
with open(temp_path, 'r', encoding='utf-8-sig') as f:
    result = json.load(f)
```

`utf-8-sig` transparently strips the BOM if present and works correctly if it's absent — so it's safe to use unconditionally for any file that might originate from a Windows environment.

**When this applies**: Any task where `export_result.ps1` (PowerShell) writes JSON that the Python verifier later reads. This is every Windows QEMU task with a post_task export script.

---

## Lesson 25: Regex false positives in structured data (XML, JSON, config files)

When using regex to detect keywords in structured files (XML, JSON, YAML, config), short patterns can match inside unrelated tokens. A real example: the pattern `(?i)RSI` (searching for the RSI indicator) matches `"veRSIon"` in the standard XML declaration `<?xml version="1.0"?>`.

**Fix**: Use word boundaries (`\b`) for short identifiers:
```powershell
# BAD: matches "veRSIon", "curSOR", etc.
if ($content -match "(?i)RSI") { ... }

# GOOD: only matches standalone "RSI"
if ($content -match "(?i)\bRSI\b") { ... }
```

**Common traps by file format**:
- **XML**: `<?xml version=...>` contains "rsi" in "version"
- **JSON**: Key names like `"description"` contain common substrings
- **HTML**: Tag attributes like `class="..."` can contain anything
- **Config files**: Comments may contain coincidental matches

**Rule**: For any keyword shorter than 5 characters that you search for in structured file content, use word boundaries (`\b`) or anchor the match to the application's specific data format (e.g., match `<IndicatorName>RSI</IndicatorName>` instead of just `RSI`).

---

## Lesson 26: Distinguish index/metadata files from content files

Complex desktop applications often store multiple files in a single directory — some are **indexes** (listing what exists) and others are **content** (the actual data). If your verification logic scans the wrong type, you'll get false positives or miss real work.

**Example**: NinjaTrader 8 stores `_Workspaces.xml` as a 200-byte index listing workspace names. The actual workspace content (charts, indicators, configurations) is stored in separate, larger XML files that only appear when the user explicitly saves. Scanning `_Workspaces.xml` for indicator keywords finds nothing meaningful, and counting it as "workspace modified" produces a false positive since it's auto-created on app launch.

**Pattern**: Many applications create small metadata/index files automatically on startup:
- Git: `.git/index`, `.git/HEAD`
- IDEs: `.idea/workspace.xml`, `.vscode/settings.json`
- Trading platforms: workspace index files, session files
- Media editors: thumbnail caches, undo history files
- Office suites: lock files, autosave metadata

**Fix in export scripts**: Explicitly exclude known metadata files when scanning directories:
```powershell
# Exclude the index file, only scan content files
Get-ChildItem $dir -Filter "*.xml" | Where-Object {
    $_.Name -ne "_Workspaces.xml"
} | ForEach-Object { ... }
```

**Fix in setup scripts**: Record baseline **after** the application has launched and auto-created its metadata files, not before. Otherwise every run shows the metadata file as "new work."

**Rule**: Before writing an export script that scans a directory for evidence of agent work, launch the application once with no agent actions, list what files it auto-creates, and exclude those from your scan. Only files that appear as a result of explicit user action count as evidence.

---

## Lesson 27: Unit-test verifiers with mock `copy_from_env` before VM testing

Booting a VM, running setup, and invoking `env.step(mark_done=True)` takes minutes per verifier iteration. For wrong-target and partial-completion tests you may need 10+ runs. Testing verifier logic in isolation cuts this to seconds.

**The pattern**: Create synthetic result files locally, mock `copy_from_env` to return them, and call the verifier function directly.

```python
import shutil, importlib.util

def _load_verifier(task_dir, func_name):
    """Load a verifier function from a task directory without import collisions."""
    path = os.path.join(task_dir, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{func_name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, func_name)

def make_mock_copy_from_env(local_file_path):
    """Return a copy_from_env that serves a local file instead of SCP-ing from a VM."""
    def copy_from_env(vm_path, dest_path):
        shutil.copy2(local_file_path, dest_path)
    return copy_from_env

# Build a synthetic result (JSON, ZIP, CSV — whatever the verifier expects)
create_synthetic_result("/tmp/fake_result.json", wrong_target=True)

# Call verifier directly
verify = _load_verifier("benchmarks/cua_world/environments/myenv/tasks/mytask", "verify_mytask")
result = verify(
    [],  # empty trajectory
    {"copy_from_env": make_mock_copy_from_env("/tmp/fake_result.json")},
    {"metadata": {}}
)

assert result["score"] == 0 and result["passed"] is False
```

**Why `importlib.util` instead of `from verifier import ...`**: Every task has a file named `verifier.py`. If you `sys.path.insert` for each task directory and `import verifier`, Python caches the first one. `importlib.util.spec_from_file_location` avoids this by loading each file under a unique module name.

**When to use**: Always, for Phase 5 validation (do-nothing, wrong-target, partial). Only fall back to full VM testing for Phase 4 setup/export verification and for checking screenshots.

---

## Lesson 28: Independent criteria can silently almost-pass wrong-target submissions

If a verifier has 5 independently-scored criteria and only Criterion 1 checks the target identity, a wrong-target submission can still score high on Criteria 2-5. This is not theoretical — we observed a verifier score 65/70 for a completely wrong dependent variable because the secondary criteria (covariates present, diagnostic plots enabled, collinearity checks on) were all satisfied.

**The concrete danger**:
```
Criterion 1 (DV correct):     5/25  — partial credit for "regression found but wrong DV"
Criterion 2 (covariates):    25/25  — same covariates used, just wrong DV
Criterion 3 (residual plots): 20/20  — plots were enabled
Criterion 4 (VIF):           15/15  — VIF was enabled
Criterion 5 (file size):      0/15  — too small
TOTAL: 65/100 — pass threshold is 70!
```

One more covariate or a slightly larger file and this wrong-target submission would have **passed**.

**The fix**: Add a wrong-target gate that returns `score=0` immediately, **before** any criteria are evaluated. This is different from giving 0 points on Criterion 1 — it short-circuits all scoring.

```python
# WRONG-TARGET GATE — must come before any criteria scoring
if not target_matches_expected(result, metadata):
    return {
        "passed": False,
        "score": 0,
        "feedback": "Wrong target: [specific reason]. Analysis is fundamentally wrong."
    }

# Only reach here if target is correct
# Criterion 1 (25 pts): ...
# Criterion 2 (25 pts): ...
```

**Rule**: If your verifier has any criterion that checks "is this the right target?", that check must be a **gate** (early return with score=0), not a **criterion** (0/N points while other criteria continue scoring). The checklist calls this "FIRST CHECK" for a reason — it must execute first and block all subsequent scoring on failure.

---

## Lesson 29: Prefer Application APIs Over Raw SQL for Web App Exports

**The Problem**: Modern web applications store data in internal formats that differ from what you'd expect by reading the schema. When your export script queries the database directly with raw SQL, it can produce broken output even though the query looks correct.

**Real example**: Odoo 17 stores translatable text fields (e.g., `crm_stage.name`) as JSONB internally: `{"en_US": "New"}` instead of the plain string `"New"`. A raw SQL export that does `SELECT name FROM crm_stage` returns JSONB objects. When these are interpolated into a JSON heredoc, the nested braces produce invalid JSON:

```json
{
    "stage_name": "{"en_US": "New"}"   ← invalid JSON, unescaped inner braces
}
```

This pattern is **not specific to Odoo**. Many modern web frameworks use non-obvious internal storage:

| Framework | Field Type | Internal Storage | What You Expect |
|-----------|-----------|-----------------|-----------------|
| Odoo 17 | Translated Char | JSONB `{"en_US": "value"}` | Plain string `"value"` |
| Django | JSONField | JSONB | Depends on serializer |
| WordPress | Options | Serialized PHP arrays | Flat values |
| Rails (Globalize) | Translated attrs | Separate `_translations` table | Single string |
| Drupal | Field API | `field_data_*` tables with deltas | Simple values |

**The Fix**: Always use the application's own API (REST, XML-RPC, GraphQL) for export scripts instead of raw SQL. The API layer handles field resolution, translation, computed fields, and access control — returning clean values the way the application intends them to be read.

```bash
# BAD: Raw SQL — breaks on JSONB/translated/computed fields
STAGE_NAME=$(odoo_db_query "SELECT name FROM crm_stage WHERE id=1")
# Returns: {"en_US": "New"}

# GOOD: XML-RPC API — returns resolved values
python3 << 'PYEOF'
stage = models.execute_kw(DB, uid, PASS, 'crm.stage', 'read', [[1]], {'fields': ['name']})
# Returns: [{"id": 1, "name": "New"}]  ← clean string
PYEOF
```

**When raw SQL is acceptable**: Simple count queries (`SELECT COUNT(*)`), boolean checks (`SELECT EXISTS(...)`), or numeric aggregations where the column type is unambiguous (integers, floats, timestamps). Even then, prefer the API for consistency.

**Rule**: For any web application with an API, export scripts should query through the API, not the database. Raw SQL is a maintenance trap — it works during development, then silently breaks when the app upgrades its internal storage format.

---

## Lesson 30: Module-Dependent Fields in Modular Web Applications

**The Problem**: Many web applications have modular architectures where installing different modules/plugins adds or removes fields from the database. Setup scripts that reference a field from an uninstalled module crash with errors like `Invalid field 'X' on model 'Y'` or `column "X" does not exist`.

**Real example**: In Odoo 17, the `customer_rank` field on `res.partner` only exists when the `sale` module is installed. A CRM-only installation (with `crm`, `contacts`, `mail` modules) does not have this field. An XML-RPC `create` call that includes `customer_rank` in the data dict raises a `ValueError`:

```
ValueError: Invalid field 'customer_rank' on model 'res.partner'
```

This crashes the entire setup script's Python heredoc, which bash then silently ignores (see Lesson 1), leaving the task with no seed data.

**This pattern is widespread**:

| Application | Module System | Example |
|-------------|---------------|---------|
| Odoo | Apps/Modules | `customer_rank` (sale), `employee_id` (hr), `website_published` (website) |
| WordPress | Plugins | `_yoast_wpseo_*` meta (Yoast SEO), `_wc_*` meta (WooCommerce) |
| Moodle | Plugins | `mdl_assign_*` tables (mod_assign), `mdl_quiz_*` (mod_quiz) |
| Jira | Apps | Custom fields from marketplace apps |
| Drupal | Modules | `field_*` tables from contrib modules |

**The Fix**:

1. **Check which modules are actually installed** before writing setup scripts. For Odoo:
   ```python
   installed = models.execute_kw(DB, uid, PASS, 'ir.module.module', 'search_read',
       [[['state', '=', 'installed']]], {'fields': ['name']})
   installed_names = {m['name'] for m in installed}
   ```

2. **Only use fields from modules listed in env.json** (or the app's init/install configuration). If your `docker-compose.yml` installs `crm,contacts,mail`, only use fields from those modules.

3. **Test with a minimal install**, not a full/demo install. Development machines often have all modules installed, masking field availability issues.

**Rule**: Before referencing any field in a setup or export script, verify it belongs to a module that is explicitly installed in your environment's configuration. Never assume a field exists just because the app's documentation mentions it — documentation covers the full product, not your minimal install.

---

## Lesson 31: Score the Agent's Choices, Not the Setup's Choices

**The Problem**: Setup scripts create the exact records the agent is supposed to configure (assignments, policies, modules, etc.). If your verifier awards points simply for those records *existing*, a do-nothing agent (one that makes zero changes) will earn those points immediately after `reset()`. The task becomes trivially solvable by doing nothing.

**Example**: A task asks an agent to assign a 40 % weight to the "Projects" assignment group. The setup script calls `ag = AssignmentGroup.create!(name: 'Projects', group_weight: 0)`. A naive verifier checks `ag.name == 'Projects'` (5 pts) and `ag.group_weight == 40` (20 pts). The first check always passes because setup created the record — so the do-nothing baseline already scores 5/25.

**Why this is subtle**: The broken criterion is not "always true" in the obvious sense (like checking "is the app running?"). It *feels* meaningful — you are checking that the right record exists. But the setup guarantee makes it a free gift every time.

**Distinguish three categories of criteria**:

| Category | Scored? | Rationale |
|----------|---------|-----------|
| Existence of setup-created records | **No** — use as unscored gate only | Setup guarantees it; not the agent's work |
| Attribute value the agent must set | **Yes** | Agent chose this; it changes if agent acts |
| Count of agent-created sub-records | **Yes** | Agent must create them; do-nothing = 0 |

**The Fix**: Make record-existence an *unscored sanity gate* that returns `score=0` with a clear message if the record is missing, but awards **0 points** for its presence:

```python
# UNSCORED GATE — confirm setup worked, but award nothing
ag = query_assignment_group(exec_capture, name="Projects")
if ag is None:
    return {"passed": False, "score": 0, "feedback": "Setup error: Projects group not found"}

# NOW score only what the agent changed
score += 20 if abs(ag.group_weight - 40.0) < 0.5 else 0   # agent-set value
score += 15 if ag.rules_count >= 1 else 0                  # agent-created sub-records
```

**Rule**: Every criterion that awards non-zero points must be something the agent can fail to do. If your setup script guarantees the criterion is satisfied before the agent acts, it must not contribute to the score. Run the mental check: "Would a do-nothing agent satisfy this criterion?" If yes, remove the points.

---

## Lesson 32: Tiered Partial Credit for N-of-M Entity Tasks

**The Problem**: A task requires the same action on N similar entities (e.g., configure a late policy for each of 3 courses, reorder 5 modules, add rubrics to 4 assignments). Binary scoring — "all N correct = full points, otherwise 0" — is too harsh for an RL agent learning from sparse rewards. The agent gets zero signal from completing 2 out of 3.

Conversely, awarding `(k/N) * full_points` for each correctly handled entity can be implemented as a flat loop but requires every sub-entity to be scored independently. If the verifier checks only the final aggregate count, partial completions are invisible.

**The Fix**: Score each entity independently in a loop, accumulating a per-entity point value. Do NOT check the aggregate count as a single all-or-nothing criterion.

```python
# BAD — binary all-or-nothing
correctly_configured = sum(1 for c in courses if check_late_policy(c))
score += 30 if correctly_configured == 3 else 0

# GOOD — per-entity scoring with partial credit
PTS_PER_COURSE = 10   # 3 courses × 10 pts = 30 pts total
for course_id, course_name in COURSES:
    policy = get_late_policy(exec_capture, course_id)
    if policy and abs(policy["late_submission_deduction_percent"] - expected_pct) < 0.5:
        score += PTS_PER_COURSE
        subscores[course_name] = PTS_PER_COURSE
    else:
        subscores[course_name] = 0
```

**Threshold calibration**: With tiered scoring, recalibrate the pass threshold. If 3 entities × 10 pts = 30 pts is the whole task, a threshold of 21+ (≥2 correct) signals "mostly done". Use the threshold to reward meaningful partial completion, not just binary pass/fail.

**Rule**: Whenever a task requires the same action on N ≥ 2 similar entities, score each entity independently with equal weight. Use the pass threshold (not the scoring) to define what "done enough" means.

---

## Lesson 33: ORM Soft-Delete for Setup Cleanup in Web App Environments

**The Problem**: Setup scripts often need to clean up previously seeded data before re-seeding (e.g., during reset). For web applications built on MVC frameworks (Rails, Django, Laravel, etc.), using raw SQL `DELETE FROM` or calling the ORM's `destroy` method on records with foreign-key–linked children raises constraint errors that silently abort the entire script.

**Real example**: A Canvas LMS setup script tries to `ag.destroy` on an `AssignmentGroup` that has child `Assignment` records. Rails raises `ActiveRecord::InvalidForeignKey`. The `rescue nil` swallows it — the group is NOT deleted — and the script continues with stale data.

**Root cause**: Modern ORM frameworks enforce referential integrity both at the DB level (FK constraints) and at the ORM level (dependent callbacks). Calling `destroy` triggers callbacks that may themselves raise. Raw `DELETE FROM` bypasses ORM callbacks but fails at the DB FK constraint. Neither approach handles the full dependency tree reliably.

**The Fix**: Use the application's own soft-delete mechanism instead of hard-deleting:

| Framework | Soft-delete pattern | Example |
|-----------|--------------------|----|
| Rails / Canvas | `record.workflow_state = 'deleted'; record.save!` | `ag.workflow_state = 'deleted'; ag.save! rescue nil` |
| Django | `record.is_deleted = True; record.save()` | (if using soft-delete mixin) |
| Laravel | `record->delete()` with `SoftDeletes` trait | Auto-sets `deleted_at` |
| Moodle | `$DB->set_field('table', 'deleted', 1, ['id' => $id])` | |

Soft-delete leaves the DB row intact (so FK references remain valid) but marks it as invisible to the application. The app's queries filter out soft-deleted records, so the agent sees a clean state without FK constraint errors.

**When soft-delete is unavailable**: Delete children before parents, walking the FK dependency tree explicitly. For simple cases (no grandchildren), this is reliable:

```ruby
# Delete children first, then parent
Assignment.where(assignment_group_id: ag.id).each { |a| a.workflow_state = 'deleted'; a.save! rescue nil }
ag.workflow_state = 'deleted'; ag.save! rescue nil
```

**Rule**: In any web-app environment, never use raw SQL `DELETE` or unconditional ORM `destroy` for setup cleanup. Check whether the framework has a soft-delete pattern and use it. Reserve hard-deletes only for leaf records with no FK-referencing children, and always wrap them in explicit error handling.

---

## Lesson 34: Running Application-Level Commands Inside Docker Containers

**The Problem**: Many task environments run the main application inside a Docker container (Canvas, Redmine, Moodle, GitLab, etc.). Setup scripts need to execute application-level commands (Rails runners, Django management commands, Artisan commands) inside that container. A naive `docker exec container rails runner script.rb` fails with "command not found" or wrong-environment errors because:

1. **No shell profile**: `docker exec` by default does not source `/etc/profile`, `~/.bashrc`, etc. The `PATH` is minimal and does not include the application's language runtime or package manager.
2. **Wrong environment variables**: Rails apps need `RAILS_ENV=development`; Django needs `DJANGO_SETTINGS_MODULE`; PHP apps need `APP_ENV`. Without these, the command uses production settings or raises configuration errors.
3. **Non-standard gem/package home**: Some Docker images install dependencies to a custom directory (e.g., `/opt/canvas/.gems`) instead of the system gem path. The runtime cannot find gems unless `GEM_HOME` / `BUNDLE_PATH` is set.
4. **Wrong working directory**: Framework CLIs typically assume they are run from the application root. A `docker exec` without an explicit `--workdir` starts in `/`.

**The correct invocation pattern**:

```bash
docker exec CONTAINER_NAME bash -lc "
    cd /path/to/app &&
    RAILS_ENV=development \
    GEM_HOME=/custom/gem/path \
    /custom/gem/path/bin/bundle exec rails runner /tmp/script.rb
"
```

Key elements:
- `bash -lc` — login shell (`-l`) sources `/etc/profile` and profile.d scripts, giving correct PATH; `-c` runs the command string
- `cd /path/to/app` — move to application root before running the CLI
- Framework env var (`RAILS_ENV`, `DJANGO_SETTINGS_MODULE`, `APP_ENV`) — use the correct environment
- Explicit gem/package home if non-standard — prevents "could not find gem X" errors
- Full path to the package manager binary — avoids PATH ambiguity

**How to discover the correct invocation**: Read the container's own startup scripts. In the image's `ENTRYPOINT`, `CMD`, or `docker-compose.yml` `command` field, you will find exactly how the application is launched in that environment. Copy that pattern for your `docker exec` calls.

**Rule**: Never use bare `docker exec container <framework-cli> <command>`. Always wrap in `bash -lc`, `cd` to the app root, and explicitly set any environment variables and non-standard paths that the app's own startup scripts use. The container's startup script is the canonical source for the correct invocation.

---

## Lesson 31: Sentinel Values in Configuration Fields (0=unlimited, -1=unset, etc.)

**The Problem**: Many applications use "magic" values to represent special states like "unlimited," "not configured," or "default." When your export script reads these values and passes them to the verifier, the verifier may misinterpret them as real numeric values, causing do-nothing tests to fail or wrong scores.

**Common sentinel value patterns across environments**:

| Application Type | Field | Sentinel Value | Meaning |
|-----------------|-------|----------------|---------|
| Web hosting panels | disk quota | `0` | Unlimited (not zero bytes) |
| Web hosting panels | bandwidth limit | `NONE` / empty | Unlimited |
| Database configs | max_connections | `0` or `-1` | No limit |
| Application settings | timeout_sec | `0` or `-1` | No timeout |
| Scheduling systems | retention_count | `0` | Keep all (not delete all) |
| User management | max_users | `UNLIMITED` / `0` | No cap |

**What breaks**:
```bash
# export_result.sh reads quota from config
QUOTA=$(grep 'quota=' /etc/app/domain.conf | cut -d= -f2)
# QUOTA is "0" — which means unlimited, not zero!

# verifier.py misinterprets:
quota_mb = result.get('quota_parsed', 0)
if abs(quota_mb - 500) / 500 <= 0.10:  # fails: 0 is not close to 500
    score += 25  # never awarded
```

The do-nothing test correctly scores 0, but if you're debugging why a "correct" result also scores 0, this is usually the cause.

**The Fix**: Handle sentinel values explicitly in the export script, converting them to a canonical representation before the verifier sees them:

```bash
# In export_result.sh: convert sentinel to null
QUOTA_RAW=$(grep 'quota=' "$DOMAIN_CONF" | cut -d= -f2)
if [ "$QUOTA_RAW" = "0" ] || [ -z "$QUOTA_RAW" ]; then
    QUOTA_PARSED="null"  # JSON null = "not set"
else
    QUOTA_PARSED="$QUOTA_RAW"
fi
```

```python
# In verifier.py: treat null/None as "not configured"
quota_val = result.get('quota_parsed')
if quota_val is None:
    feedback_parts.append("Disk quota not set (still unlimited)")
elif abs(quota_val - expected) / expected <= 0.10:
    score += 25
```

**How to discover sentinel values**: Before writing any export script, run the CLI/API query on a fresh environment where the setting has NOT been configured, and note what value is returned. Compare it with what's returned after setting the value to a known amount. Common discoveries:
- `quota=0` before setting → `quota=512000` after setting 500MB
- `bw_limit=` (empty) before → `bw_limit=5368709120` after setting 5GB
- `max_count=UNLIMITED` before → `max_count=10` after setting a cap

**Rule**: For any numeric configuration field, always test what value the application returns when the setting is at its default/unconfigured state. Document this in the README's Edge Cases section. Never assume that 0 means zero or that an empty string means an error.

---

## Lesson 32: Wrong-Target Gates for Multi-Entity Tasks

**The Problem**: Lessons 28 and Pattern 2 (`03_verification_patterns.md`) describe wrong-target gates that compare a single entity ID — "expected patient_pid=3, got patient_pid=7 → score=0." But some tasks target **multiple entities** (e.g., "back up all 3 domains," "configure settings for all users," "apply security policy to all servers"). There is no single "wrong entity ID" to compare against.

Without a multi-entity gate, a wrong-target submission can score high on secondary criteria while targeting completely wrong entities:

```
# Task: "Back up all 3 domains: A, B, C"
# Agent created a backup for domains X, Y, Z (completely wrong)
# Without gate:
Criterion 1 (domains): 0/25 — none of A, B, C present
Criterion 2 (destination): 20/20 — correct path
Criterion 3 (schedule): 15/15 — daily
Criterion 4 (features): 25/25 — all 4 features
Criterion 5 (retention): 15/15 — correct count
TOTAL: 75/100 — PASSES at threshold 70!
```

**The Fix**: Add a prerequisite gate that checks whether *at least one* of the required entities is present. If zero required entities are found, return score=0 immediately:

```python
# MULTI-ENTITY WRONG-TARGET GATE
required_entities = metadata.get('target_domains', [])
found_entities = [d for d in required_entities if result.get(f'has_{d.replace(".", "_")}')]

if len(found_entities) == 0:
    return {
        "passed": False,
        "score": 0,
        "feedback": f"CRITICAL: None of the required entities found: {required_entities}"
    }

# After the gate, award partial credit for each entity found
entity_score = int(25 * len(found_entities) / len(required_entities))
score += entity_score
```

**When to use**: Any task where the target is a SET of entities (domains, users, servers, records, files) rather than a single entity. The gate ensures that doing the right *type* of work on the wrong *targets* scores zero.

**The threshold for the gate**: Use "at least one required entity present" (not "all required entities"). This is because:
- If 2 of 3 domains are present, the agent clearly understood the task — partial credit on the domain criterion is appropriate
- If 0 of 3 domains are present, the agent either didn't understand the task or targeted something completely different — that's a wrong-target failure

**Rule**: When designing a verifier for a multi-entity task, the wrong-target gate should check `len(found_required_entities) == 0`, not `len(found_required_entities) < len(all_required_entities)`. Zero is the threshold for "fundamentally wrong"; partial is the threshold for "incomplete but on track."

---

## Lesson 33: Verifying Desktop Apps That Save Structured Document Formats

**The Problem**: Many desktop applications (Jamovi, LibreOffice, GIMP, Blender, etc.) save output as structured file formats — ZIP archives containing XML/HTML/JSON/binary data. Examples: `.omv` (Jamovi), `.xlsx`/`.ods` (spreadsheets), `.docx` (Word), `.ora` (image editors), `.blend` (Blender). Pattern 6 ("File Existence and Content Verification") covers simple text files but not these compound formats.

**The approach**: These files are usually ZIP archives. Extract them and parse the internal structure:

```python
import zipfile, tempfile, os

def parse_document_output(file_path, copy_from_env=None):
    """Extract and parse a ZIP-based document format."""
    temp_dir = tempfile.mkdtemp()
    local_path = os.path.join(temp_dir, "output.file")

    # Step 1: Get file from VM via copy_from_env
    if copy_from_env:
        try:
            copy_from_env(file_path, local_path)
        except Exception:
            local_path = file_path  # fallback to local
    else:
        local_path = file_path

    if not os.path.isfile(local_path):
        raise FileNotFoundError(f"Output not found: {file_path}")

    # Step 2: Extract ZIP and find the content file
    extract_dir = os.path.join(temp_dir, "extracted")
    with zipfile.ZipFile(local_path, "r") as zf:
        zf.extractall(extract_dir)

    # Step 3: Parse the relevant internal file
    # Common internal files by format:
    #   .omv  → index.html (rendered analysis output)
    #   .xlsx → xl/sharedStrings.xml + xl/worksheets/sheet1.xml
    #   .docx → word/document.xml
    #   .ods  → content.xml
    content_path = os.path.join(extract_dir, "index.html")  # adapt per format
    with open(content_path, "r", encoding="utf-8-sig") as f:
        return f.read()
```

**Two verification architectures** — Choose one based on format complexity:

1. **Direct parsing in verifier.py**: The verifier uses `copy_from_env` to retrieve the file, extracts it, and parses the content directly. Best when the file format is well-understood and parsing is straightforward (HTML keyword matching, XML xpath).

2. **Export-mediated via export_result.sh**: The export script runs *inside the VM* (where the application's own tools are available), does the heavy parsing, and writes a simple JSON. The verifier just reads the JSON. Best when parsing requires application-specific tools, complex binary formats, or when the format varies across versions.

| Factor | Direct Parsing | Export-Mediated |
|--------|---------------|-----------------|
| Reliability | Higher (no intermediate step) | Lower (extra failure point in shell script) |
| Complexity | Verifier must understand file format | Shell script handles format, verifier stays simple |
| Debugging | Easier (single Python file) | Harder (bugs can be in shell or verifier) |
| Best for | HTML/XML/JSON inside ZIPs | Binary formats, app-specific tools needed |

**Key gotcha**: When using `copy_from_env`, always use a temp directory — the verifier runs on the host, not inside the VM, so VM paths like `/home/ga/...` don't exist locally.

---

## Lesson 34: QEMU Checkpoint Staleness After Modifying Hook Scripts

**The Problem**: QEMU checkpoint hashes are computed from `env.json` content — NOT from the contents of scripts referenced by env.json (like `install_jamovi.sh` or `setup_jamovi.sh`). If you modify a pre_start or post_start script (e.g., adding new datasets, changing installation steps), but env.json remains unchanged, the checkpoint hash stays the same. The old checkpoint will be used, and it won't contain your script changes.

**Symptoms**:
- Files you added in the install script don't exist in the VM
- New datasets are missing even though install_jamovi.sh downloads them
- Setup scripts fail because expected files aren't present
- Everything works with `use_cache=False` but breaks with `use_cache=True`

**The Fix**: Delete the stale checkpoint file before testing:

```bash
# Find and delete the checkpoint
ls ~/.cache/gym-anything/checkpoints/  # find the hash
rm ~/.cache/gym-anything/checkpoints/checkpoint_<hash>_post_start.qcow2
```

Then boot with `use_cache=True` (no existing checkpoint → fresh boot + checkpoint save):
```python
obs = env.reset(seed=42, use_cache=True, cache_level="post_start", use_savevm=True)
```

**Important nuance about `use_cache=False`**: Booting with `use_cache=False` runs all hooks from scratch (good for testing), but it does **NOT** save a new checkpoint. Checkpoint creation only happens when `use_cache=True` and no matching checkpoint exists. So if you want to both test and create a fresh checkpoint, you must:
1. Delete the old checkpoint
2. Boot with `use_cache=True`

**Prevention**: Whenever you modify any hook script (pre_start, post_start), always delete existing checkpoints for that environment before testing.

---

## Lesson 35: Efficient Phase 5 Injection Testing Without Booting VMs

**The Problem**: Phase 5 validation requires wrong-target and partial-completion tests. Booting a full QEMU VM for each test is slow (3-5 minutes per boot). Since these tests only need to verify that the *verifier logic* correctly handles edge cases, you can call verifier functions directly with crafted mock data.

**The approach**: Import the verifier function, construct mock inputs, and call it directly:

```python
import importlib.util, tempfile, zipfile, json

# Dynamically import the verifier
spec = importlib.util.spec_from_file_location("v", "benchmarks/cua_world/environments/my_env/tasks/my_task/verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# For verifiers that use copy_from_env to get files:
def mock_copy(src, dst):
    shutil.copy2(my_crafted_file, dst)
result = mod.verify_my_task([], {"copy_from_env": mock_copy}, {})

# For verifiers that read JSON from a fixed path (monkey-patch the path):
mod.RESULT_JSON_PATH = "/tmp/my_crafted_result.json"
result = mod.verify_my_task([], {}, {})
```

**For file-based verifiers** (Pattern from Lesson 33), create minimal fake documents:
```python
# Create a minimal .omv/.xlsx/.docx (ZIP with crafted internal content)
with zipfile.ZipFile(path, "w") as zf:
    zf.writestr("index.html", "<html>wrong-target content here</html>")
    zf.writestr("meta", "archive metadata")
```

**For JSON-based verifiers**, write crafted JSON directly:
```python
# Wrong-target: all analysis flags = False
json.dump({"file_exists": True, "has_analysis_x": False, ...}, open(path, "w"))
# Partial: some flags True, some False
json.dump({"file_exists": True, "has_analysis_x": True, "has_analysis_y": False, ...}, open(path, "w"))
```

**Validation criteria**:
- Wrong-target: `passed=False` (score will include file-exists points, typically 15-25, which is fine)
- Partial: `0 < score < threshold` and `passed=False`

**When VM testing IS still needed**: The do-nothing test (Phase 5.1) must run in the actual VM because it validates the full pipeline: setup script → export script → verifier. Injection tests (Phase 5.2-5.3) can be done without a VM since they only test verifier logic.

---

## Lesson 36: Verify Base Data Project Buildability Before Creating Tasks

**The Problem**: When creating tasks for IDE or build-system environments (Android Studio, VS Code, IntelliJ, Xcode, Eclipse, etc.), the data projects shipped in `data/` must actually compile, build, or load successfully. If the base project has infrastructure issues — missing resources, incorrect build file syntax, stale dependency declarations — every task that includes a "project compiles" criterion will fail on infrastructure rather than on the intended challenge. This is invisible until Phase 4 testing.

**Real examples that broke silently**:

| Issue | Symptom | Root Cause |
|-------|---------|------------|
| `dependencyResolution` instead of `dependencyResolutionManagement` in `settings.gradle.kts` | Gradle fails at settings parsing (line 14) | Incorrect Gradle DSL method name in template project |
| Missing `mipmap/ic_launcher.png` resources | AAPT resource linking error during `processDebugResources` | AndroidManifest.xml references icons that don't exist |
| Missing `local.properties` with SDK path | Gradle can't find Android SDK | Project template doesn't include per-machine config |
| Wrong Kotlin/AGP version compatibility | Mysterious compilation errors | `kotlin-android` plugin version incompatible with AGP version |

**Why this is insidious**: These are NOT bugs the agent is supposed to fix — they're broken test infrastructure. But since they manifest as build failures, they silently corrupt the "build success" scoring criterion across all tasks. The do-nothing test still returns score=0 (correct), so Phase 5 passes. The bug only surfaces when a capable agent correctly completes the task but still fails the build criterion.

**The Fix — Test the base project BEFORE writing any task files**:

```bash
# Boot the environment without any task
env = from_config("benchmarks/cua_world/environments/<env_name>")
obs = env.reset(seed=42, use_cache=True, cache_level="post_start", use_savevm=True)

# Copy the data project and attempt to build it
env._runner.exec_capture("""
    cp -r /workspace/data/<ProjectName> /home/ga/TestBuild
    chown -R ga:ga /home/ga/TestBuild
    chmod +x /home/ga/TestBuild/gradlew
    cd /home/ga/TestBuild && \\
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \\
    ./gradlew assembleDebug --no-daemon 2>&1
""")
# ^^^ This MUST end with "BUILD SUCCESSFUL" before you proceed
```

**What to check by platform**:

| Platform | Build Command | Common Missing Pieces |
|----------|--------------|----------------------|
| Android (Gradle) | `./gradlew assembleDebug` | mipmap icons, `local.properties`, correct `settings.gradle.kts` DSL |
| iOS (Xcode) | `xcodebuild -scheme X` | signing certificates, provisioning profiles |
| Node.js | `npm run build` | `node_modules` (run `npm install` first), missing type definitions |
| Python | `python -m py_compile *.py` | missing `__init__.py`, import errors |
| Rust | `cargo build` | missing `Cargo.lock`, edition mismatches |
| CMake/C++ | `cmake --build .` | missing system libraries, wrong compiler version |

**Rule**: Before creating any task for a build-system environment, compile/build the unmodified data project inside the VM. Fix all infrastructure issues in the data files before writing task scripts. If your task includes a "build success" criterion worth N points, those N points must be achievable with a correctly-completed task — not blocked by pre-existing project issues.

---

## Lesson 37: Write Source-Code Modifications as Temp Python Scripts

**The Problem**: Lesson 15 describes planted-bug tasks using inline Python heredocs for JSON/config files. But when `setup_task.sh` needs to modify *source code* in a compiled language (Kotlin, Java, Swift, C++, TypeScript), three escaping systems collide: bash quoting, Python string literals, and the target language's syntax (backslashes, quotes, regex patterns, generics). Inline `sed` fails on multi-line replacements, and inline `python3 << 'EOF'` breaks when the target code contains characters that conflict with Python string delimiters.

**Example that breaks** — planting a bug in Kotlin code that uses regex:
```bash
# BAD: sed can't reliably do multi-line replacement
sed -i 's/return true/return isNoteComplete(note)/' "$FILE"
# Only works if the pattern is unique on one line — fails if context needed

# BAD: inline Python with conflicting escapes
python3 << 'PYEOF'
old = '    fun charCount(): Int {\n        return content.replace("\\s".toRegex(), "").length\n    }'
# ^^^ The \\s is ambiguous: is it a Python escape or Kotlin source?
PYEOF
```

**The Fix — Write Python to a temp file, then execute it**:
```bash
cat > /tmp/plant_bug.py << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# The old/new strings are EXACTLY as they appear in the source file.
# No bash expansion, no Python escape conflicts.
old = '    fun isNoteComplete(note: Note): Boolean {\n        if (!isValidTitle(note.title)) return false\n        if (!isValidContent(note.content)) return false\n        if (note.content.isBlank()) return false\n        return true\n    }'

new = '    fun isNoteComplete(note: Note): Boolean {\n        if (!isValidTitle(note.title)) return false\n        if (!isValidContent(note.content)) return false\n        if (note.content.isBlank()) return false\n        return isNoteComplete(note)\n    }'

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Bug planted successfully')
else:
    print('ERROR: Pattern not found')
    sys.exit(1)
PYEOF

python3 /tmp/plant_bug.py "$SRC_DIR/NoteValidator.kt"
```

**Why this works**:
- The `<< 'PYEOF'` (quoted heredoc) prevents bash from expanding `$` or `\` inside the script
- The Python script uses standard string operations — no regex needed for exact replacements
- The `sys.exit(1)` on pattern mismatch makes setup_task.sh fail loudly instead of silently producing an unmodified file
- Each bug gets its own temp script, keeping modifications isolated and debuggable

**When to use `sed` vs temp Python scripts**:

| Modification Type | Use | Example |
|-------------------|-----|---------|
| Single-line, unique pattern | `sed -i 's/old/new/'` | Changing a variable name |
| Multi-line exact replacement | Temp Python script | Replacing a function body |
| Regex-based transformation | Temp Python script | Modifying patterns that contain regex metacharacters |
| Target code contains `\`, `$`, `"`, `'` | Temp Python script | Any language with escape sequences or string interpolation |

**For runtime-only bug tasks**: After planting all bugs, verify the project still compiles (see Lesson 36). If a "runtime bug" accidentally prevents compilation, your debugging task has become a syntax-fix task — a much easier problem that doesn't match the intended difficulty.

```bash
# At the end of setup_task.sh, after planting all bugs:
echo "Verifying project still compiles with planted bugs..."
cd "$PROJECT_DIR"
./gradlew compileDebugKotlin --no-daemon > /tmp/compile_check.log 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Planted bugs caused compile failure — bugs are too aggressive"
    tail -20 /tmp/compile_check.log
    # Don't exit 1 here (setup should still complete), but this warning
    # tells the task creator to fix the bug-planting logic
fi
```

**Rule**: When `setup_task.sh` modifies source code files, always write the modification logic as a standalone Python script in `/tmp/`, execute it, and check its exit code. Never rely on `sed` for multi-line source-code modifications, and never use inline Python heredocs when the target source code contains escape characters or string delimiters.

---

## Lesson 38: Silent DB Errors Masked by `2>/dev/null` + Bash Fallbacks

**The Problem**: Task scripts often suppress DB query stderr with `2>/dev/null` and use bash fallbacks (`${VAR:-default}`) to handle empty results. This creates a dangerous combination: if a query fails due to a wrong column name, wrong table, or syntax error, the error is silently discarded, the variable is empty, the fallback kicks in with a plausible-looking value, and the script appears to succeed.

The do-nothing Phase 5 test still passes (the agent did nothing, so the result is still the fallback default, which is what we expect for an un-completed task). But during actual agent runs, the export script never reflects the real post-agent DB state — it always returns the fallback default regardless of what the agent did, making every agent run score 0 for that criterion.

**Example failure pattern**:
```bash
# BAD: "creditlimit" column doesn't exist — psql error is silenced
CURRENT_CREDIT=$(docker exec db psql -U user -d mydb -t -A \
    -c "SELECT creditlimit FROM c_bpartner WHERE id=200000" 2>/dev/null)
CURRENT_CREDIT=${CURRENT_CREDIT:-0}   # fallback silently kicks in
echo "Credit: $CURRENT_CREDIT"        # always prints "Credit: 0"
```
The correct column was `so_creditlimit`, not `creditlimit`. The script ran without error, the do-nothing test showed score=0 for the credit criterion (expected), but every agent run also scored 0 — the export was broken.

**The Fix**:
1. **Verify column names before writing task scripts** — query the schema interactively:
   ```bash
   docker exec db psql -U user -d mydb -c "\d tablename"
   # or
   docker exec db psql -U user -d mydb -c "SELECT column_name FROM information_schema.columns WHERE table_name='tablename'"
   ```
2. **Test your export query directly** in the live environment before embedding it in a script:
   ```bash
   docker exec db psql -U user -d mydb -t -A -c "SELECT so_creditlimit FROM c_bpartner WHERE c_bpartner_id=200000"
   ```
3. **Remove `2>/dev/null` during development** — let errors print so you catch them. Only restore it once queries are confirmed working.
4. **Add a sanity check**: after the fallback, verify the value is plausible for a real export:
   ```bash
   CURRENT_CREDIT=${CURRENT_CREDIT:-QUERY_FAILED}
   if [ "$CURRENT_CREDIT" = "QUERY_FAILED" ]; then
       echo "ERROR: DB query failed — check column name or connection" >&2
   fi
   ```

**Rule**: Never combine `2>/dev/null` with `${VAR:-fallback}` on DB queries until you have confirmed the query succeeds interactively. During task development, always run each DB query directly in the VM shell first, then embed it in the script.

---

## Lesson 39: Prevent Unintended Passing Paths by Designing Scoring Arithmetic Upfront

**The Problem**: After defining N criteria and a pass threshold T, it's easy to inadvertently create a scenario where an incomplete agent (one that skips the essential step) can still reach T points by completing all other criteria. This "unintended passing path" means partial completion is rewarded as full success.

**Example failure pattern**:

| Criterion | Points | Agent A (did everything) | Agent B (no SO, just settings) |
|---|---|---|---|
| Credit limit updated | 25 | ✓ 25 | ✓ 25 |
| Payment terms updated | 25 | ✓ 25 | ✓ 25 |
| SO created (standalone) | 20 | ✓ 20 | ✗ 0 |
| Azalea Bush in SO | 15 | ✓ 15 | ✗ 0 |
| Holly Bush in SO | 15 | ✓ 15 | ✗ 0 |
| **Total** | 100 | **100** | **50** |

Threshold = 70. Agent B fails correctly at 50. But now add a small scoring tweak — raise each SO criterion by 5 pts — and suddenly Agent B can score 75 with just settings (25+25+25=75, passes).

**The Fix — enumerate partial completion scenarios before finalizing weights**:

For every task, before writing the verifier, write out a table like:

| Partial Scenario | Expected Outcome | Score Must Be |
|---|---|---|
| Agent does nothing | Fail | < 70 |
| Agent updates settings only (no SO) | Fail | < 70 |
| Agent creates SO only (no settings changes) | Fail | < 70 |
| Agent updates settings + creates SO (no products) | Fail | < 70 |
| Agent does everything correctly | Pass | ≥ 70 |

Then verify the arithmetic: for each "must Fail" row, calculate the maximum achievable score and confirm it stays below the threshold.

**The essential criterion rule**: If criterion X is the essential completion step (posting a document, creating an output, completing a workflow), design weights so that:
```
sum_of_all_other_criteria_points < pass_threshold
```
This guarantees that an agent who skips criterion X can never pass, regardless of how well they perform on everything else.

**Rule**: Before writing a single line of verifier code, draw the partial completion table and verify the arithmetic. If any "must Fail" scenario can reach the pass threshold, adjust the point weights — not by trial and error, but by explicitly ensuring `sum_of_all_criteria_except_essential < pass_threshold`.

---

## Lesson 40: Exclude Seeded Context Documents from Keyword Scans (EXCLUDE_IDS Pattern)

**The Problem**: `setup_task.sh` often seeds realistic context documents (patient records, visit summaries, issue tickets, work orders, etc.) with domain-specific keywords in narrative fields — for example, a patient visit record with `"reasonForVisit": "patient presents with migraine headache"` or an IT ticket with `"description": "CRITICAL: disk failure suspected"`. When the verifier scans all documents for those keywords, the seeded context documents match immediately — even with no agent action. The do-nothing test then scores points it should not, masking the real verification logic.

**Real example**: A hospitalrun_env task had a CouchDB visit document seeded with `"reasonForVisit": "Migraine – follow-up"`. The verifier's diagnosis check scanned all documents for `["migraine", "headache"]` keywords, found the visit document, and awarded 33 points even with zero agent work. The do-nothing test incorrectly returned `score=33, passed=False` (not `score=0`).

**Why type filtering doesn't catch this**: Seeded documents often have no explicit `type` field (or `type=""`). A check like `if doc_type in ["patient", "visit"]: continue` silently skips documents that have an explicit type, but passes through those with `type=""` — which is exactly what many CouchDB/MongoDB documents look like when created via setup scripts.

**The Fix — EXCLUDE_IDS set**: Explicitly collect the IDs of all documents your setup script seeds as context, and skip them in every scan loop:

```python
# At the top of verifier.py, alongside other constants
# Exclude base patient/visit documents — their narrative fields contain clinical keywords
# (e.g., "migraine" in reasonForVisit) that must not count as completed subtasks.
EXCLUDE_IDS = {"patient_p1_000013", "visit_p1_000013"}

# In every scan loop:
for row in rows:
    doc_id = row.get("id", "")
    if doc_id.startswith("_design"):
        continue
    if doc_id in EXCLUDE_IDS:      # ← add this
        continue
    ...
```

**Applies to**: Any environment where the verifier queries a document store (CouchDB, MongoDB, Elasticsearch, Firebase, DynamoDB) and checks all documents for keyword or field-based evidence. The pattern is not specific to medical records — it applies whenever setup scripts seed realistic context data that could trigger any verifier criterion.

**How to discover ambient credit**: After writing the verifier, run a do-nothing test (step with empty action list). If `score > 0`, check which criterion triggered by inspecting `subscores` or adding `feedback_parts` logging. The culprit is almost always a seeded document matching a keyword.

**Rule**: After writing any keyword-scan verifier, run the do-nothing test before anything else. If it scores >0, identify which seeded document IDs are triggering the match and add them to `EXCLUDE_IDS`. Never rely solely on type filtering — always use explicit ID exclusion for documents you know are seeded as background context.

---

## Lesson 41: Verify Partial Test Injection Scores Stay Strictly Below the Pass Threshold

**The Problem**: When testing partial completion (Phase 5.3), the goal is to inject enough data to trigger *some but not all* criteria, resulting in `passed=False` with `0 < score < threshold`. Two failure modes are easy to miss:

1. **Threshold collision**: Injecting exactly the right number of subtasks such that their combined score equals the pass threshold. `score == threshold` means `passed=True` — the partial test silently becomes a full-pass test.

2. **Value mismatch in value-based checks**: Some verifiers check whether specific expected values (e.g., `bp_systolic=132`, `weight=74`) appear in the document. If you inject values that are plausible but don't exactly match what the verifier expects from `task_info["metadata"]`, the criterion awards 0 points — making your "partial" test a "nothing was found" test.

**Threshold collision example**:
```
Task: emergency_triage_workup — 4 subtasks × 25 pts each; threshold was 50
Partial test injects: vitals (25 pts) + diagnosis (25 pts) = 50 pts
Result: score=50, passed=True ← WRONG, this is not a partial test!
Fix: Raise threshold to 75 (requires 3 of 4 subtasks)
```

**Value mismatch example**:
```
Task: inpatient_discharge — verifier checks metadata["bp_systolic"]="132" in doc_str
Partial test injects: vitals doc with systolic=120 (plausible but wrong)
Verifier finds vitals doc, counts matching values: 0 of 5 match → vitals_score=0
Result: score=0, not partial at 25 pts ← WRONG, value was injected but not recognized
Fix: Read verifier metadata defaults; inject EXACT values (systolic=132, weight=74, etc.)
```

**How to avoid both**:

1. **Before writing the partial test**, calculate: `injected_criteria_count × points_per_criterion`. Confirm this is strictly less than the threshold.
   ```
   # If threshold=66 and each criterion = 33 pts:
   # Injecting 1 criterion → 33 < 66 ✓ (partial passes)
   # Injecting 2 criteria → 66 = 66 ✗ (threshold collision!)
   # Fix: Inject only 1 criterion for a partial test
   ```

2. **For value-based checks**, read the verifier source to find every `metadata.get("field_name", "default_value")` call. Your injected document must contain exactly those values (as strings) in its JSON representation.
   ```python
   # In verifier.py:
   bp_sys = metadata.get("bp_systolic", "132")  # ← inject systolic=132, not 120
   vals_found = sum(1 for v in [bp_sys, ...] if str(v) in doc_str)
   ```

**Rule**: Before running Phase 5.3, calculate the expected score of your partial injection and confirm it is in the range `(0, threshold)` exclusive. If `score == threshold`, either reduce the injection (fewer subtasks) or raise the threshold. For value-based verifiers, always inject the EXACT metadata default values — not plausible alternatives.

---

## Lesson 42: Use PUT with Explicit IDs When Injecting into Format-Validated Databases

**The Problem**: Many databases enforce document/record ID format constraints through validation hooks, triggers, or schema rules. When test scripts inject data using HTTP POST (or equivalent insert-with-auto-ID operations), the database generates a random ID (UUID, snowflake ID, etc.) that fails the format validation, returning a `forbidden` or `validation failed` error. This is especially subtle because the injection command itself may succeed at the HTTP level (returning 201 or 200) but the document is silently rejected by application-level validation.

**Real example**: CouchDB 1.7.1 used by HospitalRun enforces that document IDs match the pattern `<allowedType>_<x>_<y>` (e.g., `vital_p1_000015_init`, `diagnosis_p1_000013_new`) via a `validate_doc_update` design document. An injection using POST generates a UUID like `f3a2c891b4d07e56` which fails this check:

```bash
# BAD: POST generates UUID "f3a2c891b4d07e56" → validate_doc_update rejects it
curl -s -X POST 'http://couchadmin:test@localhost:5984/main' \
    -H 'Content-Type: application/json' \
    -d '{"data": {"patient": "patient_p1_000015", "type": "vitals", ...}}'
# → {"error":"forbidden","reason":"Invalid document ID format"}

# GOOD: PUT with explicit format-compliant ID → accepted
curl -s -X PUT 'http://couchadmin:test@localhost:5984/main/vital_p1_000015_init' \
    -H 'Content-Type: application/json' \
    -d '{"data": {"patient": "patient_p1_000015", "type": "vitals", ...}}'
# → {"ok":true,"id":"vital_p1_000015_init","rev":"1-..."}
```

**This pattern generalizes beyond CouchDB**:

| Database | Validation Mechanism | Common Failure Mode |
|----------|---------------------|---------------------|
| CouchDB | `validate_doc_update` in design docs | Auto-generated UUID fails regex check |
| Firestore | Security rules on document paths | Random ID fails path-pattern rules |
| DynamoDB | Stream triggers / Lambda validators | Auto-ID doesn't match partition key schema |
| MongoDB | Schema validation (`$jsonSchema`) | Auto-ObjectId may fail custom `_id` validators |
| Cassandra | Partition key constraints | UUID primary key violates clustering rules |

**How to diagnose**: Run the injection and check the response body — don't just check the HTTP status code. CouchDB returns 201 with `{"error":"forbidden"}` in the body when validation fails. If your test script silently ignores the response body (`> /dev/null`), you'll never see the rejection.

**How to discover the format**: Before writing any injection, look at existing documents in the database to understand the ID pattern:
```bash
# List all CouchDB document IDs to find the naming pattern
curl -s 'http://user:pass@localhost:5984/dbname/_all_docs' | python3 -c "
import json, sys
rows = json.load(sys.stdin)['rows']
for r in rows[:20]: print(r['id'])
"
# Output: patient_p1_000013, visit_p1_000013, vital_p1_000013_001, ...
# Pattern: <type>_<namespace>_<number>[_<suffix>]
```

**Rule**: When writing Phase 5 injection scripts for any web application that uses a document database, always use PUT/PATCH (with explicit ID) rather than POST (auto-ID). Choose an ID that matches the format of existing documents for that document type. After each injection, inspect the full response body — not just the HTTP status code — to confirm the document was accepted.

---

## Lesson 43: Pass Condition Must Encode Completeness, Not Just Score

**The Problem**: A numeric score threshold alone does not prevent partial completions from passing when the task requires multiple distinct entities and each entity's partial credit accumulates.

Lessons 32 and 28 address *wrong-target* submissions (agent acts on a completely different entity → score=0). This lesson addresses a different failure mode: *right-target, partial-entity* work, where the agent acts correctly on a subset of the required entities and the per-entity partial credit scores sum above the pass threshold.

**Concrete example**:

Task: export trades for both AAPL and MSFT to a CSV. Scoring:
- CSV exists: 25 pts
- Created after task start: 15 pts
- ≥4 data rows (3 rows for AAPL only): `int(25 × 3/4) = 18 pts`
- Contains AAPL (yes): 25 pts × 0.5 = 12 pts (partial, MSFT missing)
- Proper CSV structure: 10 pts
- **Total for AAPL-only submission: 80 pts > 60 pt threshold → incorrectly passes**

The agent completed only half the task, yet the sum of partial credits from each independent criterion crossed the threshold.

**The Fix: Entity-presence guards in the pass condition**

```python
# WRONG: score threshold alone is not enough
passed = score >= 60

# CORRECT: require presence of each required entity in addition to score
passed = (score >= 60
          and result.get('has_aapl')
          and result.get('has_msft'))

# For N-of-M entity tasks:
found_required = [e for e in required_entities if result.get(f'has_{e}')]
passed = score >= threshold and len(found_required) >= min_required_count
```

**How this differs from existing patterns**:

| Pattern | When agent acts on... | Trigger | Effect |
|---------|----------------------|---------|--------|
| Lesson 32 (wrong-target gate) | Completely wrong entity | `len(found_required) == 0` | `score = 0` immediately |
| Lesson 28 (almost-pass) | Wrong entity, high partial | Many non-entity criteria pass | Near-pass without target |
| Lesson 41 (threshold collision) | Right entity, exact threshold | Score equals threshold | Partial test is really a pass |
| **This lesson** | Right entities, partial subset | Partial credit accumulates | Incorrect pass with missing entities |

**When to apply**: Any task that requires work on 2+ distinct required entities (securities, patients, documents, users, etc.) where each entity independently contributes points. If removing one entity from the submission would still yield a passing score, add that entity's presence to the pass condition.

---

## Lesson 44: First-Run Dialogs in Commercial Desktop Software Must Be Automated in `post_start`

**The Problem**: Many commercial and proprietary desktop applications show one or more blocking dialogs on first launch — EULA/license acceptance, registration prompts, welcome wizards, and profile/layout selection screens. These dialogs prevent the application from reaching its main window, which means any agent task that assumes the app is ready will fail.

**The critical sub-problem**: Several apps (including whiteboard software, creative tools, and CAD packages) **exit and relaunch themselves** after the first-run wizard completes in order to apply the selected profile. A `post_start` script that only handles the wizard once and then returns will leave the environment without a running app — the relaunched process is orphaned.

**Pattern for `post_start` / `setup_activinspire.sh`-style scripts**:

```bash
# Step 1: Launch the app in the background
su - ga -c "DISPLAY=:1 /path/to/app &"
sleep 10   # Allow time for slow Qt/Electron startup

# Step 2: Handle license dialog by window title
if DISPLAY=:1 wmctrl -l | grep -qi "license\|eula\|agreement"; then
    DISPLAY=:1 xdotool search --name "license" windowactivate
    DISPLAY=:1 xdotool mousemove <accept_x> <accept_y> click 1   # check "I accept"
    sleep 1
    DISPLAY=:1 xdotool mousemove <ok_x> <ok_y> click 1           # click OK/Continue
    sleep 3
fi

# Step 3: Handle welcome/profile wizard (same pattern)
if DISPLAY=:1 wmctrl -l | grep -qi "welcome\|setup wizard"; then
    DISPLAY=:1 xdotool mousemove <continue_x> <continue_y> click 1
    sleep 5   # App may exit here to apply profile settings
fi

# Step 4: Re-launch if app exited after wizard (common!)
if ! pgrep -f "app_binary" > /dev/null; then
    echo "App exited after wizard — relaunching..."
    su - ga -c "DISPLAY=:1 /path/to/app &"
    sleep 15
fi
```

**Coordinate discovery**: Use the `visual_grounding` MCP tool on a VNC screenshot to find the pixel coordinates of checkboxes and buttons. Remember to scale from the tool's 1280×720 output to the actual VM resolution (multiply by `actual_width / 1280`).

**Key rules**:
1. Always detect dialogs by **window title** (via `wmctrl -l | grep`), never by fixed timing alone.
2. Account for the app potentially **exiting** after a wizard step and needing a second launch.
3. Do NOT launch with `setsid` for X11 GUI apps from SSH — `setsid` creates a new session that may not properly inherit D-Bus / XAuthority, causing the process to start but immediately exit. Use a plain `... &` or `nohup ... &` instead.
4. Set license/first-run flags in the app's config directory **before** launching if the format is known (avoids the need to interact with dialogs entirely).

---

## Lesson 45: `pgrep` Alone Is Insufficient to Verify a GUI App Is Ready

**The Problem**: A process detected by `pgrep` may be:
- Still loading (no window yet after 20+ seconds for heavy Qt/Electron apps)
- Completing one-time initialization and about to **exit cleanly** (exit code 0)
- Crashed but still listed as a zombie
- Running a background/helper process while the main UI process has already exited

All of these return results from `pgrep`, yet the app is not usable.

**Concrete example**: An interactive whiteboard app starts its main process, loads dozens of shared libraries, initializes a license check, runs a first-run wizard, saves the profile, then cleanly exits (code 0) — all within 20 seconds. `pgrep` reports the process as running throughout; `wmctrl -l` would reveal no window ever appeared (or only the wizard window, then nothing).

**The Fix — Use window presence as the readiness signal**:

```bash
# WEAK: only checks if any process matching the name exists
wait_for_app() {
    pgrep -f "MyApp" > /dev/null
}

# STRONG: verify the main window is actually visible
wait_for_app_window() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l | grep -qi "MyApp\|My App Title"; then
            echo "App window is visible"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: App window not detected within ${timeout}s"
    return 1
}
```

**In verifiers**, use the window check as a supporting signal (not the primary one — file output is primary):

```python
# Check for window presence via SSH as a secondary signal
_, stdout, _ = ssh.exec_command('DISPLAY=:1 wmctrl -l 2>/dev/null')
window_visible = 'MyApp' in stdout.read().decode()
```

**Rule**: Use `pgrep` only to kill/restart a process. Use `wmctrl -l` (or an equivalent window-list tool) to verify the app is actually ready for user interaction. For export scripts that run after agent work, ensure the app window is still present before attempting file-based extraction.

---

## Lesson 46: Desktop Apps With Embedded Browsers (Electron / Qt WebEngine / CEF) Are Fragile in QEMU

**The Problem**: Many modern desktop applications embed a full Chromium-based browser renderer to display parts of their UI as HTML/JavaScript — this includes Electron apps (VS Code, Slack, Discord), Qt WebEngine apps (ActivInspire, Qt Creator's help), and CEF-based apps. In QEMU virtual machines, the GPU command buffer used by the Chromium renderer often fails because the virtual GPU does not properly support hardware-accelerated 3D:

```
[ERROR:command_buffer_proxy_impl.cc] ContextResult::kTransientFailure:
  Failed to send GpuChannelMsg_CreateCommandBuffer.
```

This failure can cascade: the embedded browser may fail to initialize its JavaScript bridge to the host application, causing the app to exit cleanly (exit code 0) even though no UI was ever shown.

**Symptom pattern**:
- App process starts, runs for 10–20 seconds, exits with code 0
- Log shows Qt/Chromium property-binding warnings, then SSL errors, then GPU error, then nothing
- JS errors like `Uncaught ReferenceError: appStarted is not defined` — the C++/JS bridge never registered
- `wmctrl -l` shows no application window, only the desktop

**Mitigation attempts** (in rough order of effectiveness):

```bash
# Option 1: Disable Chromium GPU (works for some apps, breaks JS bridge in others)
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --no-sandbox --disable-dev-shm-usage"

# Option 2: Force software rendering for Qt (use with caution — may cause immediate exit)
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=softpipe

# Option 3: Use swiftshader (software Vulkan/GL) — most compatible with QEMU
export QTWEBENGINE_CHROMIUM_FLAGS="--use-gl=swiftshader --disable-gpu-compositing"
```

**Important**: `--disable-gpu` disables hardware acceleration but does NOT prevent the Chromium process from launching. Some apps rely on the GPU-accelerated path for their C++↔JS bridge; disabling the GPU can silence the crash but simultaneously break the JS communication, leaving the app in a partially-initialized state that still exits.

**Design implications for task creation**:
1. **Check `env.json` status before writing tasks** — if `"status": "blocked"` with a GPU/OpenSSL reason, the app's embedded-browser features will not function and any task requiring those features cannot be fully tested in the current base image.
2. **Tasks CAN still be created** for blocked environments — they serve as correct documentation of expected behavior for when the base image is fixed (e.g., Ubuntu 20.04 vs 22.04). Validate task logic via mock verifier tests (Lesson 27) and do-nothing tests on the actual VM.
3. **Pure Qt-Widgets dialogs often work even when Qt WebEngine fails** — an app may show its license/welcome dialog (which uses native widgets) but crash when it tries to open its home page (which uses WebEngine). Do not conclude the app is fully functional based on early dialogs alone.
4. **Prefer base images that match the app's supported OS** — the `required_base` field in `env.json` documents which base image is needed. Changing the base image resolves these issues more cleanly than any `QTWEBENGINE_CHROMIUM_FLAGS` workaround.

**Rule**: After writing your verifier, manually compute the score for a submission that correctly handles only N-1 of N required entities. If that score ≥ threshold, add entity-presence guards to the `passed` expression. The pass condition should encode both *how much work was done* (score) and *which work was done* (entity presence).

---

## Lesson 47: Official Release Downloads as Real Data (with Cross-Task Caching)

**Context**: Lesson 14 covers software's *in-VM* sample data — datasets accessible via `File > Open Samples` or similar menus, which are already bundled in the VM image. This lesson covers a complementary pattern: applications that distribute real sample data as **external downloads** (GitHub release assets, official dataset pages). These downloads fully satisfy the real-data requirement (Principle 2) and are often the only authentic sample data available for the environment.

**Examples**:
- InVesalius 3: official DICOM samples at `https://github.com/invesalius/invesalius3/releases/download/v3.0/0051.zip`, `0437.zip`, `0801.zip`, etc.
- Scientific tools with sample datasets linked from their documentation
- Medical software bundling de-identified patient case archives

**The cross-task caching pattern**: When multiple tasks in the same environment need the same large downloaded dataset, caching at a shared OS path avoids repeated downloads and handles network failures gracefully:

```bash
# Shared cache location (persists across task runs)
CACHE_DIR="/opt/<app_name>/sample_data/<dataset_name>"
DATASET_URL="https://github.com/<repo>/releases/download/<tag>/<file>.zip"

# Per-task symlink path (what the task's setup uses)
TASK_SERIES_DIR="/home/ga/DICOM/<dataset_name>"

# Download only if not already cached
if [ ! -d "$CACHE_DIR" ]; then
    echo "Downloading dataset (first run)..."
    TMPZIP=$(mktemp --suffix=.zip)
    if curl -fsSL -o "$TMPZIP" "$DATASET_URL" 2>/dev/null; then
        mkdir -p "$CACHE_DIR"
        unzip -q "$TMPZIP" -d "$CACHE_DIR" 2>/dev/null || true
        rm -f "$TMPZIP"
        echo "Dataset cached to $CACHE_DIR"
    else
        rm -f "$TMPZIP"
        echo "Download failed — falling back to default dataset"
        # Fall back to built-in data already present in the VM
        CACHE_DIR="/home/ga/DICOM/default_dataset"
    fi
fi

# Create per-task symlink pointing to the cache
ln -sfn "$CACHE_DIR" "$TASK_SERIES_DIR" 2>/dev/null || true
```

**Key design points**:

1. **Verify the URL is accessible before writing tasks**: Download URLs on release pages can return 302 redirects. Always confirm the URL is reachable (`curl -I <url>`) and that the file size is plausible before building tasks around it.

2. **Cache at `/opt/` or another persistent OS path**: The `/opt/` path is preserved across task boots (it's baked into the environment's install image via `install_*.sh`). If you add the download to `install_*.sh`, it runs once during cache creation. If you add it to `setup_task.sh`, it runs each time but still benefits from the cache check.

3. **Use symlinks for per-task isolation**: `ln -sfn` creates a symbolic link from the task-specific path to the shared cache. This gives each task its own apparent path without copying gigabytes of data.

4. **Always include a fallback**: If the download fails (network issue, URL change), fall back to a dataset already present in the VM. Never let a download failure make a task completely broken.

5. **Update `assets/SOURCES.txt`**: Document every downloaded dataset with its URL, license, and which tasks use it. Future maintainers need to know where data came from to understand the real-data provenance.

**Discovering available release assets**: For open-source applications hosted on GitHub, the releases page (`https://github.com/<org>/<repo>/releases`) lists all official downloads. Check the project's documentation for "sample data," "example files," or "demo datasets" links.

**Rule**: Before generating synthetic data for any environment, check whether the application distributes real sample datasets via its GitHub releases page, official download site, or documentation. These downloads are always preferable — they're real, authoritative, and often cover multiple scenarios (different anatomy, different modalities, different configurations). Cache them at the OS level so multiple tasks can share the same download.

---

## Lesson 48: Domain-Specific File Formats Often Lack Standard Extensions

**The Problem**: Files in domain-specific formats — particularly in medical, scientific, and industrial software — often have no conventional extension or use non-standard naming conventions that violate the pattern `filename.extension`. Common examples:

| Domain | Format | Typical Naming | Extension? |
|--------|--------|----------------|------------|
| Medical imaging | DICOM | `IM000000`, `IM000001`, `I.001` | None or `.dcm` |
| Astronomy | FITS | `image.fits`, but also `data.fts`, `image` | Varies |
| Medical records | HL7 | `ADT^A01`, exported as plain text | None |
| Industrial sensors | Raw acquisition | `CH_001`, `TRACE_A` | None |
| Older DICOM scanners | DICOM | `DICOMDIR`, `0001.ima` | Non-standard |

**Why this matters for task creation**:

1. **Setup scripts that use extension-based file detection will silently fail**:
   ```bash
   # BAD: finds nothing if DICOM files are named IM000000 etc.
   DICOM_FILES=$(find "$DATA_DIR" -name "*.dcm" | head -5)

   # GOOD: use the application's own import path (directory, not files)
   # Most domain apps (InVesalius, OsiriX, Fiji, etc.) detect format from file content
   IMPORT_DIR="$DATA_DIR"   # pass the directory; let the app figure out the files
   ```

2. **Verifiers that check file extensions will produce false negatives**:
   ```python
   # BAD: misses valid DICOM files without .dcm extension
   dicom_files = [f for f in os.listdir(data_dir) if f.endswith('.dcm')]

   # GOOD: check file content or use domain tools
   import subprocess
   dicom_files = []
   for f in os.listdir(data_dir):
       # dcmdump exits 0 for valid DICOM regardless of extension
       result = subprocess.run(['dcmdump', '+rd', os.path.join(data_dir, f)],
                               capture_output=True)
       if result.returncode == 0:
           dicom_files.append(f)

   # Or: check magic bytes (DICOM files have "DICM" at offset 128)
   def is_dicom(path):
       try:
           with open(path, 'rb') as f:
               f.seek(128)
               return f.read(4) == b'DICM'
       except Exception:
           return False
   ```

3. **Task descriptions must not assume file extensions**: When describing where data is located, say "the DICOM files in `~/DICOM/series/`" rather than "the `.dcm` files in `~/DICOM/series/`." An agent that searches for `.dcm` files will fail even if valid DICOM is present.

4. **Test with the actual files before finalizing tasks**: After setting up a task with domain data, verify that the application's own file detection finds all files. For QEMU VM environments, check the application's import dialog or the output of its import process to confirm files were recognized.

**How to discover whether an application uses content-based or extension-based detection**:
```bash
# Use the file command — reports actual format based on magic bytes, not extension
file IM000000    # → "DICOM medical imaging data"
file unknown_data  # → "FITS image data, 16-bit"

# Or probe with the domain tool directly
dcmdump +rd IM000000 2>/dev/null | head -5   # DICOM
fitsinfo unknown_data 2>/dev/null            # FITS
```

**Rule**: Whenever you work with a domain-specific environment (medical, scientific, industrial, geospatial), check whether the software's sample data files follow standard extension conventions *before* writing any file detection logic. If they don't, use content-based detection (magic bytes, domain CLI tools, the application's native import) instead of extension filters. Document any non-standard naming in the task README so future maintainers don't accidentally "fix" the missing extension and break the format.

---

## Lesson 49: Version-Specific API Field/Model Renames Break Setup Silently

**The Problem**: When an application upgrades between major versions, internal model names and field names can be renamed. Setup scripts that use the old name fail with an unhandled exception inside a Python heredoc embedded in bash. Because bash's `python3 << 'PYEOF'` blocks do not propagate the Python exit code by default (see Lesson 1 / Lesson 8), the script continues as if setup succeeded — but the seed data JSON is never written. The export script then immediately exits with "FATAL: Cannot load seed IDs," scoring 0 in a confusing way that looks like an agent failure rather than a task creation bug.

**Real example**: Odoo changed the lost-reason model name between versions:
- Odoo 15: `crm.lead.lost.reason`
- Odoo 16/17: `crm.lost.reason`

A setup script that called `search_count` on `crm.lead.lost.reason` in an Odoo 17 environment crashed immediately, leaving `/tmp/lost_deal_analysis_ids.json` unwritten. All subsequent export and verification steps failed with an error that appeared to be an agent problem.

Similarly, `mail.message` changed a field name between versions:
- Odoo 15/16: `res_model` (the linked model name)
- Odoo 17: `model`

Export scripts filtering on `['res_model', '=', 'crm.lead']` silently returned empty results in Odoo 17.

**Why it's insidious**: These renames are not documented errors — the query simply returns zero results or raises a field-not-found exception. The task *appears* to set up correctly (no obvious crash in the bash output), but every do-nothing test and real agent run produces 0 score. The bug looks exactly like an agent that did nothing, not a broken task.

**The Fix**: Wrap any model/field query that might be version-dependent in a try/except with fallback to the alternative name. Save the resolved name to the seed data JSON so all subsequent scripts use the version-correct name:

```python
# In setup_task.sh — discover which model name is valid at runtime
try:
    count = models.execute_kw(DB, uid, PASS, 'crm.lead.lost.reason', 'search_count', [[]])
    LOST_REASON_MODEL = 'crm.lead.lost.reason'
except Exception:
    try:
        count = models.execute_kw(DB, uid, PASS, 'crm.lost.reason', 'search_count', [[]])
        LOST_REASON_MODEL = 'crm.lost.reason'
    except Exception:
        count = 0
        LOST_REASON_MODEL = None

# Save the resolved name — export_result.sh must use the same one
seed_data['lost_reason_model'] = LOST_REASON_MODEL
```

```python
# In export_result.sh — use the saved resolved name, not a hardcoded one
LOST_REASON_MODEL = seed_data.get('lost_reason_model')
if LOST_REASON_MODEL:
    try:
        final_count = models.execute_kw(DB, uid, PASS, LOST_REASON_MODEL, 'search_count', [[]])
    except Exception:
        final_count = None
```

**For field renames** (e.g., `mail.message.res_model` → `model`): use try/except on the read call, or check the field list of the model at runtime:

```python
# Discover field names at runtime rather than assuming version
fields_info = models.execute_kw(DB, uid, PASS, 'mail.message', 'fields_get',
    [], {'attributes': ['string']})
model_field = 'model' if 'model' in fields_info else 'res_model'

messages = models.execute_kw(DB, uid, PASS, 'mail.message', 'search_read',
    [[[model_field, '=', 'crm.lead'], ['res_id', '=', opp_id], ...]],
    {'fields': ['body', 'date']})
```

**Checklist before finalizing any web app task**:
1. Pin the exact application version in `docker-compose.yml` or the environment configuration.
2. Consult the application's changelog for the version range your environment spans.
3. For any model or field you reference in setup/export, check whether it was renamed in recent major releases.
4. Wrap uncertain model/field names in try/except with a fallback; save the resolved name to the seed data file.
5. Run the Phase 4 do-nothing test first — if score=0 because "FATAL: Cannot load seed IDs," the cause is almost always a version rename, not an agent failure.

**Rule**: Never hardcode a model or field name that was introduced or renamed in a major application version without also providing the alternative name in a try/except. The environment's installed version is the ground truth — your script must discover it at runtime.

---

## Lesson 50: Pre-Seeded "Reference" Records Inflate the Do-Nothing Baseline

**The Problem**: A common task design pattern is to seed one "already-correct" record alongside several "broken" records. The intent is to give the agent a visual reference (e.g., "here is one correctly configured opportunity — fix the others to match"). However, if the verifier awards points for *any* record in the correct state — without distinguishing which records the agent was supposed to fix — the do-nothing test returns a non-zero score. This violates the Phase 5 requirement that score=0 when the agent takes no action.

**Real examples from this project**:

*`renewal_pipeline_prep`*: Setup seeded `Vector Analytics Platform` with the correct quarter-end close date as a reference, alongside 4 broken opportunities. Criterion 1 originally checked all 5 for a correct close date at 4 pts each. Do-nothing score = 4 (the pre-seeded reference satisfied the criterion without any agent action).

*`account_consolidation`*: Setup placed `Meridian Annual License` on Company B as a pre-existing record, alongside 2 opportunities that needed to be moved there. Criterion 4 originally awarded points for any opportunity found on Company B. Do-nothing score = 6 (the pre-existing `Meridian Annual License` was already there).

**Why this is easy to miss**: When you write the verifier, the reference record is not in your mind as a "giveaway" — it's conceptually part of the task description ("look, this one is already correct"). But the verifier doesn't know the difference between "already correct at setup" and "fixed by the agent."

**The Fix — Explicit Exclusion**: Identify every record seeded in the correct state. Then:

1. **Exclude from scoring criteria**: Change the verifier criterion to only check the specific records the agent is supposed to fix. Do not score records that are already correct at setup.

2. **Report them in feedback (informational only)**: Still include the pre-seeded record's status in the feedback string — this helps with debugging and shows the agent the expected state — but tag it clearly as `[pre-existing]` and award 0 points.

```python
# BAD: scores all records including pre-seeded correct ones
for name in ALL_OPP_NAMES:   # includes Vector Analytics Platform
    if get_opp(name).get('close_date_ok'):
        score += 4   # Vector already has this → 4 free do-nothing pts

# GOOD: only score the records the agent was asked to fix
PROBLEM_OPP_NAMES = ['TerraSync Annual Renewal', 'BluePeak License Renewal',
                     'Nexus Pro Subscription', 'Cascade DataBridge Renewal']
for name in PROBLEM_OPP_NAMES:
    if get_opp(name).get('close_date_ok'):
        score += 5   # 0 pts in do-nothing because all 4 are broken at setup

# Report pre-seeded reference in feedback, but no pts
vector = get_opp('Vector Analytics Platform')
if vector.get('close_date_ok'):
    feedback_parts.append(
        f"'Vector Analytics Platform' close date OK ({vector.get('date_deadline')}) [pre-existing]"
    )
```

**Checklist when any setup record is seeded in an already-correct state**:
1. List every record that starts the task in a "passing" condition.
2. For each such record, search the verifier for any criterion that checks a property it already satisfies.
3. Either exclude it from the criterion's record list, or add an explicit `!= reference_record_name` guard.
4. Re-run the do-nothing test and confirm score=0.

**Rule**: After finalizing a verifier, mentally step through the do-nothing scenario *per record*: "Which records, if any, already satisfy this criterion at setup?" If any do, the verifier will award free points. Fix this by restricting the scoring loop to only the records the agent is responsible for changing.

---

## Lesson 51: `exec_capture()` Output Contains Terminal Escape Codes on Modern VMs

**The Problem**: On any VM that uses a modern terminal emulator (Windows ConPTY, Linux with `$TERM=xterm-256color`, etc.), `env._runner.exec_capture()` output includes ANSI/VT100 escape sequences mixed with the actual content:

```
"\u001b[?9001h\u001b[?1004h\u001b[?25l\u001b[2J\u001b[m\u001b[H\r\n...\r\nName Length\u001b[?25l\r\n---- ------\r\n"
```

Any Python code that does `"PASS" in output` or `output.strip()` or `"True" in output` against this raw string will silently fail or give wrong results even when the command succeeded.

**What breaks**:
```python
# Evidence test script checking if a file exists:
check = env._runner.exec_capture(
    'powershell -Command "Test-Path C:\\Users\\Docker\\task_baseline.json"'
)
if "True" in check:      # FAILS: "True" is buried in escape codes
    print("baseline found")

# Alternatively:
result = env._runner.exec_capture('bash -c "echo OK"')
assert result.strip() == "OK"   # FAILS: result is "\u001b[?...\u001b[H\r\nOK\r\n..."
```

**The Fix — Use structured output from the command itself**:

Instead of checking human-readable terminal output, have the command write a structured result to a file that you copy separately:

```powershell
# In the command: write result to a temp file
$result = if (Test-Path $path) { "found" } else { "missing" }
$result | Out-File "C:\Windows\Temp\check_result.txt" -Encoding ASCII
```

```python
# In Python: copy the file and read it cleanly
env._runner.copy_from(r"C:\Windows\Temp\check_result.txt", "/tmp/check.txt")
with open("/tmp/check.txt") as f:
    result = f.read().strip()
assert result == "found"
```

**Alternative: Strip escape codes in Python**:
```python
import re

def strip_ansi(text):
    """Remove ANSI/VT100 escape sequences from terminal output."""
    return re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\r', '', text)

raw = env._runner.exec_capture('powershell -Command "Test-Path $path"')
clean = strip_ansi(raw).strip()   # now "True" or "False"
```

**When to apply**: Any `exec_capture()` call whose output you intend to parse — do-nothing test scripts, evidence collection scripts, setup verification. Applies equally to Windows and Linux VMs with modern terminal settings.

**Why it doesn't affect production task files**: `setup_task.sh`/`setup_task.ps1` and `export_result.ps1` write their outputs to structured JSON files (not stdout) and `copy_from_env` retrieves those files directly. Escape codes only appear in stdout, which production task files don't parse.

---

## Lesson 52: Interactive Desktop vs Non-Interactive SSH: Windows App Visibility Gap

**The Problem**: On Windows VMs, GUI applications launched in the interactive desktop session (via `schtasks /IT` or `Launch-VitalRecorderInteractive`) are invisible to subsequent `exec_capture()` queries run through the non-interactive SSH channel.

```python
# In setup_task.ps1: app launches in interactive session
# Launch-VitalRecorderInteractive uses schtasks /IT — interactive desktop session

# In evidence collection test script: check via SSH
check = env._runner.exec_capture(
    'powershell -Command "Get-Process -Name MyApp -ErrorAction SilentlyContinue"'
)
# check is EMPTY — the app IS running, just not in this session
print("App running:", "MyApp" in check)   # → False, even though app is running
```

**Why**: Windows isolates session 0 (services/SSH) from session 1 (interactive desktop). `schtasks /IT` explicitly launches in the interactive session so the GUI is visible to the user. `Get-Process` via non-interactive SSH runs in session 0 and only sees processes in that session.

This is EXPECTED BEHAVIOR, not a bug. The same pattern applies on Linux: `su - ga -c "app &"` may not be visible to the root SSH process listing depending on the process group.

**The Fix — Verify via output files, not process presence**:

```python
# BAD: checking if process exists via SSH
vr_running = "Vital" in env._runner.exec_capture("powershell Get-Process -Name Vital")

# GOOD: checking if application created an expected state file
baseline_exists = "True" in strip_ansi(env._runner.exec_capture(
    'powershell -ExecutionPolicy Bypass -Command "$null = Test-Path C:\\baseline.json; Test-Path C:\\baseline.json"'
))

# ALSO GOOD: checking if application's output directory exists and has content
dir_check = env._runner.exec_capture(
    'powershell -Command "(Get-ChildItem C:\\AppData).Count"'
)
```

**Rule for evidence collection scripts**: Do not use `Get-Process` (Windows) or `pgrep` (Linux) through SSH to confirm a GUI application is running. Instead verify indirectly:
1. Check that the setup script's baseline file was created (proves setup ran)
2. Check that the export script produces correct output when no work was done
3. Check that the verifier returns score=0 (the reliable source of truth)

**Note for task files themselves**: `setup_task.ps1` using `Test-VitalRecorderRunning` or equivalent is fine — it just prints a warning and doesn't fail the setup. The issue only matters when *test scripts* try to verify app state.

---



## Lesson 53: Mobile/Android AVD Environments Have Different Tooling and Verification Constraints

**Context**: Some benchmark environments run inside Android Virtual Devices (AVDs) — typically accessed via `AVDApptainerRunner` — rather than QEMU VMs or Docker containers. These environments have several constraints that differ from Linux QEMU or Windows environments. All four points below are general principles that apply to any mobile app environment (Android or iOS-style), not just the specific application that surfaced them.

---

### 53a. Shell Scripts Must Use `#!/system/bin/sh`, Not `#!/bin/bash`

Android's userspace does not include bash. The only guaranteed shell is `/system/bin/sh` (a limited POSIX sh). A script beginning with `#!/bin/bash` will fail with "No such file or directory" and the error is often silent — the script appears to run (exit code 0) but none of its commands execute.

```bash
# BAD: bash is not available on Android AVD
#!/bin/bash
am force-stop com.example.app

# GOOD: use the standard Android shell
#!/system/bin/sh
am force-stop com.example.app
```

**What to avoid**: Bash-specific syntax that is not valid POSIX sh — `[[ ]]` double brackets, `$'...'` ANSI-C quoting, `local` in some contexts, arrays (`arr=(...)`), and `{a..z}` brace expansion. Use `[ ]` for tests, `$(...)` for command substitution, and plain variable arrays if you need collections.

**Rule**: For any script (`setup_task.sh`, `export_result.sh`) that runs inside an Android AVD, always use `#!/system/bin/sh` and restrict syntax to POSIX sh. Test every script by checking its exit code AND by verifying that the expected side-effects (files created, commands run) actually occurred.

---

### 53b. Force-Stop the App Before Reading Its Preference/Config Files

Android apps store their settings in a `SharedPreferences` XML file at `/data/data/<package>/shared_prefs/<name>.xml`. However, the running app caches preferences in memory and only flushes changes to disk asynchronously or when the process exits. If you copy the XML file while the app is running, you may read a stale version that doesn't reflect recent changes the agent made.

**The Fix**: Force-stop the app before copying its preference file to the export staging area.

```bash
# export_result.sh — flush preferences to disk before reading
am force-stop com.example.app
sleep 1   # allow the OS to complete the flush

# Now copy to a world-readable location for ADB pull
cp /data/data/com.example.app/shared_prefs/MyPrefs.xml /sdcard/my_prefs.xml 2>/dev/null || echo "" > /sdcard/my_prefs.xml
```

**Applies to**: Any mobile app that uses on-disk preference/config storage with in-memory caching — Android `SharedPreferences`, iOS `UserDefaults`, React Native `AsyncStorage`, etc. The pattern is the same: terminate the process before reading the file.

**Rule**: In any `export_result.sh` for a mobile app environment, always force-stop (or gracefully quit) the application as the first step before reading any preference or configuration files. Never rely on reading preference files from a running process.

---

### 53c. An Absent Preference Key Means "App Factory Default" — Not Zero, Not False

Lesson 31 covers *sentinel values* — fields that are present in a config file but carry a special meaning (e.g., `quota=0` means unlimited). Android's `SharedPreferences` introduces a related but distinct case: a **key that has never been written**. When a user has never changed a setting, the app simply has no entry for it in the XML file.

The critical distinction:
- **Sentinel value (Lesson 31)**: key IS present, value means something special
- **Absent key (this lesson)**: key is NOT present at all — the app uses its hardcoded default

These require different treatment in verifiers. For a criterion that checks "is chart type X?", the logic must be:

```python
import re

def _check_chart_type(prefs_xml: str, expected_type: str) -> bool:
    """
    Returns True if the chart preference is set to expected_type,
    OR if no chart preference has been written (app defaults to expected_type).
    """
    # Search for any key whose name contains "chart" (case-insensitive)
    match = re.search(r'name="[^"]*chart[^"]*"[^>]*>([^<]+)<', prefs_xml, re.IGNORECASE)
    if match is None:
        # Key absent → factory default applies; caller decides whether default matches
        return expected_type == APP_DEFAULT_CHART_TYPE
    return expected_type.lower() in match.group(1).lower()
```

**The threshold calibration trap**: When an absent key counts as "criterion satisfied" (because the default matches), that criterion effectively awards points even in the do-nothing test — IF the app is in its default state at task setup. This is identical to an always-true criterion (see Lesson 22). If the task does NOT require changing this setting, the always-awarded points must be accounted for when calibrating the pass threshold.

Concretely: if the default chart type is Sectional and the task requires "save a VFR plan using Sectional chart" (i.e., the agent must leave the chart as Sectional), the Sectional criterion will always be awarded whether or not the agent saved a plan. The GATE (plan file must exist) prevents the do-nothing test from scoring, but in a partial-injection test (plan injected, no chart change), the Sectional points are still awarded. If `sectional_pts + injected_plan_pts == threshold`, the partial test silently becomes a pass. **Raise the threshold by 1 to prevent this.**

**Rule**: Before writing verifier logic for any mobile app preference, boot the environment fresh and inspect the preference file with no agent actions. For every absent key, determine what the app's factory default is, and decide explicitly whether "absent = criterion satisfied" or "absent = criterion failed." Document this in the README's Edge Cases section.

---

### 53d. Phase 5 Injection Tests for Android AVDs Use `copy_to()`, Not Mock `copy_from_env`

Lessons 27 and 35 describe Phase 5 partial-completion injection tests for QEMU and Docker environments. Those lessons use mock `copy_from_env` functions: you craft a fake result file locally and patch the verifier to receive it without touching the actual VM.

Android AVD environments invert this pattern. The `export_result.sh` script runs **on the device** (not on the host), reads device-side files (CSV plans, preference XMLs), and writes a result to `/sdcard/`. The host-side verifier then pulls from `/sdcard/` using `copy_from_env`. Because the script runs on-device and reads real device paths, you cannot mock it away at the verifier level. Instead, inject the test artifacts **directly onto the device** before running export:

```python
import tempfile, os

# Create a minimal fake plan file locally
with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
    f.write("KSFO,KSFO,,,,,,,,,,,,,,,,,,,\nKLAS,KLAS,,,,,,,,,,,,,,,,,,,\n")
    local_csv = f.name

# Push it onto the Android device using ADB (copy_to wraps adb push)
env._runner.copy_to(local_csv, "/sdcard/avare/Plans/MYPLAN.csv")
os.unlink(local_csv)

# Now trigger export and verify
obs, score, done, info = env.step([], mark_done=True)
result = info.get('result', {})
assert 0 < result['score'] < THRESHOLD, f"Partial test failed: {result}"
```

The `copy_to(local_path, remote_path)` method on `AVDApptainerRunner` wraps `adb push`. Use it any time you need to stage test files on the device for partial-completion or wrong-target injection tests.

**When mock `copy_from_env` still applies**: If a verifier directly calls `copy_from_env` to retrieve a structured JSON result that was written by `export_result.sh`, you can also mock `copy_from_env` for the verifier-only tests described in Lesson 27. Prefer the `copy_to` injection approach for full-pipeline tests (setup → export → verifier), and use mock `copy_from_env` only for isolated verifier unit tests.

**Rule**: For Android AVD environments, Phase 5 injection tests inject test artifacts onto the device via `copy_to()` before running export, rather than mocking `copy_from_env` after. Always confirm the injected file path matches exactly what `export_result.sh` reads (check file name case, directory path, and encoding).

---

### 53e. The UI Dump Captures Whatever Is Foregrounded — Verify the Task App Is Active

`uiautomator dump` captures the **current foreground application's** accessibility tree. If the task app is not in the foreground when `export_result.sh` runs the dump, the captured XML will reflect a different app (a system calculator, the home launcher, an ad dialog) rather than the task app. Numbers and text from the unrelated foreground app then pollute the verifier's parsed set.

**How this happens**: A common setup_task.sh pattern launches the app and then presses `BACK` to dismiss an ad. If the app was launched from another app (e.g., a system calculator was open), pressing BACK may navigate back to that previous app rather than staying in the task app. The task app moves to the background, and `uiautomator dump` captures the system calculator instead.

**Symptoms**: The do-nothing verifier score is non-zero because:
- Numeric digits from calculator buttons (0–9) are parsed as numbers and match discrete target values
- System app UI elements (status bar, notification shade) contain text that matches verifier keywords
- The task app's main menu is NOT visible, yet navigation-menu keywords still appear (from e.g., task app notifications)

**Detection**: Add a foreground-app check to `export_result.sh`:

```sh
#!/system/bin/sh
# Verify task app is foregrounded before dumping
CURRENT_APP=$(dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | grep "com.example.taskapp")
if [ -z "$CURRENT_APP" ]; then
    echo "WARNING: Task app not in foreground, relaunching..."
    monkey -p com.example.taskapp -c android.intent.category.LAUNCHER 1
    sleep 5
fi

uiautomator dump /sdcard/ui_dump_task.xml
```

**Or in the verifier**: Parse the `package` attribute from the XML root nodes and confirm the expected package name is present before running any scoring logic:

```python
def _verify_foreground_app(xml_content, expected_package):
    """Return True if the expected app is visible in the UI dump."""
    return expected_package in xml_content

if not _verify_foreground_app(xml_content, 'com.example.taskapp'):
    return {
        "passed": False,
        "score": 0,
        "feedback": "Task app not in foreground — UI dump shows wrong app"
    }
```

**Rule**: For Android AVD tasks that use `uiautomator dump` for verification, always check that the task app's package name appears in the XML before scoring. If it does not, either relaunch the app in `export_result.sh` or return score=0 from the verifier with a clear message. Never silently score a dump that belongs to a different application.

---

## Lesson 54: Programmatic Construction of Office Document Starting Artifacts in `setup_task.sh`

**Context**: Tasks for document-centric environments (OpenOffice Writer, LibreOffice, Microsoft Word, Excel, PowerPoint) often require a pre-existing document as input — either a "draft to improve," a "broken document to fix," or a "template to fill in." Unlike database or web environments where `setup_task.sh` can insert records via SQL or HTTP, most office applications do not expose a headless document-creation API usable from a bash script. Attempting to open the app in a background process and use key-press macros to create the file is fragile and race-prone.

**The Solution**: All major office document formats are ZIP archives containing XML files. Create them directly using Python's `zipfile` module in a heredoc inside `setup_task.sh`. This requires zero app interaction and produces a fully valid file that the app will open normally.

**Format anatomy** (minimum viable files per format):

| Format | Container | Key content files |
|--------|-----------|------------------|
| ODT (OpenOffice/LibreOffice Writer) | ZIP | `content.xml`, `styles.xml`, `META-INF/manifest.xml`, `meta.xml` |
| DOCX (Microsoft Word) | ZIP | `word/document.xml`, `[Content_Types].xml`, `_rels/.rels`, `word/_rels/document.xml.rels` |
| XLSX (Microsoft Excel) | ZIP | `xl/workbook.xml`, `xl/worksheets/sheet1.xml`, `[Content_Types].xml`, `_rels/.rels` |
| PPTX (Microsoft PowerPoint) | ZIP | `ppt/presentation.xml`, `ppt/slides/slide1.xml`, `[Content_Types].xml`, `_rels/.rels` |

**Pattern for `setup_task.sh`** (ODT example — creating a document with planted formatting bugs):

```bash
python3 << 'PYEOF'
import zipfile, os

# --- Build ODT XML strings ---
content_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    office:version="1.2">
  <office:body>
    <office:text>
      <!-- BUG: paragraph with manual bold instead of Heading 2 style -->
      <text:p text:style-name="BoldFake">1. Introduction</text:p>
      <text:p text:style-name="Standard">Body content here.</text:p>
    </office:text>
  </office:body>
</office:document-content>"""

manifest_xml = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""

output_path = "/home/ga/Documents/draft_document.odt"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr("content.xml", content_xml)
    zf.writestr("styles.xml", "<office:document-styles .../>")  # minimal styles
    zf.writestr("META-INF/manifest.xml", manifest_xml)
    zf.writestr("meta.xml", '<office:document-meta office:version="1.2"/>')

print(f"Created {output_path} ({os.path.getsize(output_path)} bytes)")
PYEOF
```

**Key design rules**:

1. **Use the quoted heredoc (`<< 'PYEOF'`)**: Unquoted `PYEOF` causes bash to expand `$variable` inside the Python block, which corrupts any XML string containing `$` (e.g., namespace declarations like `$name`). See Lesson 12.

2. **Same module, different operation**: The `zipfile` module used here for *writing* is the same one used in `export_result.sh` for *reading* (Lesson 33). The XML structure written by `setup_task.sh` is exactly what `export_result.sh` parses — validate both end-to-end.

3. **Planted bugs must be exploitable**: When using this pattern for fix-task inputs, ensure the bugs are structural (e.g., paragraphs using manual bold instead of heading styles, fake TOC as plain text) rather than visual-only. Structural bugs are what verifiers can reliably detect.

4. **Remove the output file before writing**: Add `os.remove(output_path) if os.path.exists(output_path) else None` before writing, so reruns don't fail because the ZIP already exists and is locked.

5. **Check file size after creation**: Print the byte size. A valid ODT with a few paragraphs should be 1–5 KB. If it's 0 or 200 bytes, the zipfile construction failed silently (check for Python exceptions).

**Connection to existing lessons**: Lesson 15 describes planted-bug tasks conceptually; this lesson provides the mechanical implementation for document formats. Lesson 33 describes ZIP-format verification; this lesson covers ZIP-format creation. Lesson 12 covers Python heredocs in export scripts; the same technique applies to setup scripts.

**Applies to**: Any environment whose target application uses a ZIP-based document format — OpenOffice Writer, LibreOffice, Microsoft Word (docx), Excel (xlsx), PowerPoint (pptx), ODS, and other Open Document formats.

**Rule**: For document-centric environments where the task requires a pre-existing input file, construct the file programmatically as a ZIP of XML strings in `setup_task.sh` using a Python heredoc. Do not attempt to launch the application headlessly to create starting documents. Validate the created file by checking its byte size and by confirming that `export_result.sh` can parse its XML successfully before finalizing the task.

---

## Lesson 55: KVM Resource Release Pause Between Sequential Task Tests

**The Problem**: When writing an evidence collection script that tests multiple tasks in the same QEMU/KVM environment one after another, calling `env.reset()` immediately after `env.close()` on the previous task frequently causes the new VM to fail to start. The symptom is a KVM lock error or a timeout during the `env.reset()` call, even though the environment configuration is correct.

**Why it happens**: QEMU VMs backed by KVM hold a kernel-level file lock on the disk image and a reference to the `/dev/kvm` device. Calling `env.close()` initiates a graceful shutdown, but the lock release is asynchronous — the Python call returns before the OS kernel has fully freed the device handles. A `env.reset()` call that arrives within 10–15 seconds will find the device still locked.

**The Fix — 20-second pause after `env.close()`**:

```python
def close_env_safely(env, pause=20):
    """Close environment with a pause for KVM resource release."""
    try:
        env.close()
    except Exception as e:
        print(f"  (close error ignored: {e})")
    print(f"  Pausing {pause}s for KVM resource release...")
    time.sleep(pause)

# Usage in a sequential test loop:
for task in tasks_to_test:
    env = from_config(TASK_DIR, task_id=task)
    obs = env.reset(seed=42, use_cache=True, cache_level="pre_start", use_savevm=True)
    # ... run tests ...
    close_env_safely(env, pause=20)   # always use this, never env.close() directly
```

**Why `except Exception` on `env.close()`**: The close call itself can fail (e.g., if the VM crashed during a test), but that should not prevent the 20-second pause or the subsequent test run. Swallowing close errors and still pausing is the correct behavior.

**Recommended pause durations**:

| Scenario | Recommended pause |
|----------|-------------------|
| Sequential tests on same host, same env type | 20 seconds |
| Sequential tests with different env types (different disk images) | 15 seconds |
| Final test, no subsequent env.reset() needed | Skip or 5 seconds |

**Applies to**: Any test or evidence-collection script (like `test_<env>_tasks.py`) that iterates over multiple tasks in a QEMU/KVM environment. Does NOT apply to Docker-based environments, which do not use KVM and release resources synchronously.

**Rule**: In sequential QEMU task test scripts, always wrap `env.close()` in a helper function that includes a 20-second `time.sleep()` after the close call. Never call `env.reset()` on a new task immediately after `env.close()` without this pause. Ignore close exceptions (log them) — the pause must happen regardless of whether close succeeded.

---

## Lesson 56: Read Utility Helper Function Source Before Calling It

**The Problem**: `task_utils.sh` and similar shared utilities wrap raw API/CLI calls to reduce boilerplate. These wrappers often silently transform their arguments — prepending base URL segments, adding authentication, setting content-type headers, or renaming request fields. Writing setup scripts without reading the wrapper source produces subtly broken calls that fail silently.

**Concrete patterns that bite**:

| What you write | What the helper actually does | Resulting URL/call |
|---|---|---|
| `arkcase_api POST "/api/v1/plugin/complaint"` | prepends `/api/v1/` | `POST /api/v1/api/v1/plugin/complaint` (404) |
| `openemr_api GET "/api/patient/1"` | prepends `/apis/default/api/` | `GET /apis/default/api/api/patient/1` (404) |
| `odoo_call 'create' {"customer_rank": 1}` | strips unknown fields | `customer_rank` silently dropped |

In each case the wrapper returns HTTP 200 (or the script exits 0) and no error is logged — the failure is completely invisible unless you inspect the actual database records.

**The fix — read the wrapper before writing calls**:
```bash
# BEFORE writing any arkcase_api / openemr_api / moodle_api calls:
grep -A 20 "arkcase_api()" /workspace/scripts/task_utils.sh
# Look for: what does it prepend to the first argument?
#           what HTTP headers does it set?
#           which JSON fields does it require vs. ignore?
```

**Also check field names against a working example**. Wrapper functions often enforce a specific request schema. Before writing `{"complaintDetails": "...", "complaintPriority": "High"}` in a JSON body, find an existing working call (in another task's setup script or the app's own docs) and copy the field names exactly. Do not guess from the display name in the UI.

**Rule**: Before calling any shared utility function in a setup or export script, read its source to understand (1) what it prepends to endpoint/path arguments, (2) what JSON fields it accepts, and (3) what it does with errors. This takes 2 minutes and prevents hours of debugging silent failures.

---

## Lesson 57: HTTP Connectivity Check ≠ REST API Operational Readiness

**The Problem**: `wait_for_arkcase`, `wait_for_openemr`, and similar readiness helpers typically check that the application's HTTP port returns 200 or 302. This only confirms that the web server process is alive — it does not mean the application's REST API endpoints are ready to accept write operations.

**What happens**: After a VM boot, a web application goes through multiple initialization phases:
1. Web server starts → returns 200 on the root URL (this is what the readiness check detects)
2. Application framework initializes → database pools, session stores, caches
3. REST API layer becomes fully ready → write endpoints start returning meaningful responses (not 503)

The gap between phase 1 and phase 3 is typically 15–40 seconds. Any `create`/`POST` call made during this gap silently returns an error body (or 503) while curl still exits 0 (see Lesson 11).

**Symptom**: Setup script logs show "API response: null" or `complaintId: 0` for every case — all creates failed — even though the health check passed and the script ran to completion.

**The fix — add a grace sleep after the readiness wait**:
```bash
wait_for_arkcase        # or wait_for_openemr, wait_for_app, etc.
sleep 20               # give REST API layer time to finish initializing

# Now the API is ready to accept writes
create_complaint "..."
```

**How to calibrate the sleep**: After the app first starts, query a simple count endpoint in a tight loop and note how long it takes before the first successful response. Use that as your sleep duration. 20 seconds is a safe default for most JVM/Spring Boot/Django applications; some startup-heavy apps (ArkCase, Odoo, Moodle) need 30–45 seconds.

**Why not just retry the create call?** Retrying a failed POST can create duplicate records if the server partially processed the request before returning an error. A sleep before the first call is simpler and safer than retry logic with idempotency guarantees.

**Rule**: In any `setup_task.sh` that calls a REST API immediately after a readiness wait, add `sleep 20` (or the calibrated duration) between `wait_for_<app>` and the first write call. This is required for any web application that does not expose a separate "API ready" health endpoint.

---

## Lesson 58: GUI Browser Automation Utilities May Assume Browser Is Already Running

**The Problem**: `task_utils.sh` in web app environments often provides login and navigation helpers (e.g., `auto_login_arkcase`, `navigate_to`, `openemr_login`) that use `xdotool` to interact with an already-open browser window. If called when no browser is running, these functions silently do nothing — there is no window to type into, no error is raised, and the setup script exits 0 as if everything worked.

**Symptom**: The setup script completes, `task_start.png` is captured, but when the agent starts it sees a blank desktop with no browser, or the browser is still on the login page with no credentials entered.

**What the helpers typically do (check the source)**:
```bash
auto_login_arkcase() {
    # ASSUMES Firefox is already open on the login page
    DISPLAY=:1 xdotool search --name "Firefox" windowfocus
    DISPLAY=:1 xdotool type --clearmodifiers 'arkcase-admin@dev.arkcase.com'
    # ...
}
```

If Firefox is not running, `xdotool search --name "Firefox"` returns no window — subsequent `type` and `click` calls silently target no window.

**The fix — always launch the browser explicitly before calling login/navigation helpers**:
```bash
# 1. Kill any stale Firefox process and profile locks
pkill -9 -f firefox 2>/dev/null || true
sleep 3
find /home/ga -name ".parentlock" -delete 2>/dev/null || true

# 2. Launch Firefox explicitly (with or without a saved profile)
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/app/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/app/login' &>/dev/null &" &
fi
sleep 20   # wait for browser and login page to fully render

# 3. NOW it is safe to call focus/login/navigation helpers
focus_firefox
maximize_firefox
auto_login_arkcase    # or type credentials manually with xdotool
navigate_to "/dashboard"
```

**Why `sleep 20` after launching Firefox**: The browser must render the login page completely before any `xdotool type` or `mousemove click` commands can find the correct input fields. Shorter waits result in keystrokes sent to the wrong element or to an empty window.

**Applies to**: Any web application environment where `setup_task.sh` needs to open a browser and navigate to a specific page as part of the starting state. If your task starts with the agent already logged in and viewing a specific module, you must ensure the browser is launched, logged in, and navigated to that page during setup.

**Rule**: Never call browser automation helpers (`auto_login_*`, `navigate_to`, `focus_firefox`) without first explicitly launching the browser and waiting for the target page to load. Treat these helpers as "interact with an existing open window," not "open a browser and log in."

---

## Lesson 59: CLI Database Tool Output Format Must Be Verified Empirically in the Actual VM

**The Problem**: Export scripts that use CLI database clients (Firebird `isql`, PostgreSQL `psql`, SQLite `sqlite3`, Oracle `sqlplus`, etc.) must parse the tool's text output to extract query results. The exact output format — what lines appear, in what order, with what padding — depends on the specific tool version, flags, and platform. Assuming a format without testing it leads to the wrong line being parsed as the result.

A typical CLI tool output for `SELECT COUNT(*) FROM employees WHERE dept_id = 5;` might include any combination of:
- A **startup banner** (version string, copyright, database path) — often contains digits
- A **column header** line (e.g., `          COUNT`)
- A **separator** line (e.g., `===================`)
- The **actual data value** (e.g., `                  7`) — with alignment padding
- A **summary line** (e.g., `1 records fetched` or `(1 row)`)
- An **exit confirmation** (e.g., `SQL> EXIT;` echoed back)

Filtering for "lines that are purely digits after trimming" seems correct in theory, but in practice the startup banner or summary line may also produce a digit-only line — giving you the wrong value.

**What specifically breaks**: A filter of `Where-Object { $_ -match '^\d+$' }` in PowerShell (or equivalent in bash) applied to `isql` output on Firebird 5.0 returned the banner digit rather than the actual `COUNT(*)` result, because:
- `$lines[0]` (first digit-only line): captured a spurious startup digit, not the count
- `$lines[-1]` (last digit-only line): also wrong, because the output format changed with `SET HEADING OFF`

The same class of bug affects any language+tool combination where you guess which line contains the result without testing.

**The Fix — Inspect raw output during development**:

Before finalizing any export script that parses CLI tool output, add a temporary debug block that prints every line with its index:

```powershell
# PowerShell debug block — add temporarily, remove before finalizing
$out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmpSql 2>&1
$allLines = ($out | Out-String) -split "`n"
for ($i = 0; $i -lt $allLines.Length; $i++) {
    $trimmed = $allLines[$i].Trim()
    $isDigit = $trimmed -match '^\d+$'
    Write-Host "LINE[$i] isDigit=$isDigit raw=>>$($allLines[$i])<< trimmed=>>$trimmed<<"
}
```

```bash
# Bash equivalent — add temporarily
out=$(isql -user SYSDBA -password masterkey "$DB" -q -i "$tmpSql" 2>&1)
i=0
while IFS= read -r line; do
    printf "LINE[%d] raw=>>%s<<\n" "$i" "$line"
    i=$((i+1))
done <<< "$out"
```

Run this with the actual database in the actual VM, then look at the output to identify exactly which line contains your result.

**Preferred alternative — use file-based output instead of stdout parsing**:

Most CLI database tools support writing results to a file (`-o outputfile` for Firebird isql, `\o file` for psql, `.output file` for sqlite3, `SPOOL file` for sqlplus). File output contains only the data rows (no banners, no prompts, no row counts), making parsing trivial:

```powershell
# Firebird isql with -o flag: result file contains only the data row
$resultFile = "C:\Windows\Temp\count_result_$(Get-Random).txt"
$tmpSql     = "C:\Windows\Temp\count_query_$(Get-Random).sql"
Set-Content -Path $tmpSql -Value "SET HEADING OFF;`nSELECT COUNT(*) FROM employees WHERE dept_id = 5;`nEXIT;" -Encoding ASCII
& $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmpSql -o $resultFile 2>&1 | Out-Null
$count = [int]((Get-Content $resultFile -Raw).Trim())
Remove-Item $tmpSql, $resultFile -Force -ErrorAction SilentlyContinue
```

**Applies to**: Any export script (PowerShell or bash) that shells out to a CLI database client and parses stdout. Particularly relevant for: Firebird `isql`, PostgreSQL `psql`, SQLite3 `sqlite3`, Oracle `sqlplus`, IBM Db2 `db2`, Sybase `isql`, MS SQL Server `sqlcmd`.

**Rule**: Never assume which line in CLI tool output contains your result. Either use the tool's file-output flag (`-o`, `SPOOL`, `\o`), or add a debug loop during development to print all lines with indices and identify the correct one empirically.

---

## Lesson 60: Do-Nothing Score=0 Does Not Validate That the Export Script Is Correct

**The Problem**: The standard do-nothing test (run the full setup→export→verifier pipeline with no agent actions, confirm score=0) is necessary but not sufficient. A verifier gate that uses a loose threshold check — such as `if count >= N: return score=0` — can fire correctly even when the export script is returning completely wrong values.

**Concrete example**: A task seeds 5 employees with wrong designations and uses this gate:
```python
if it_remaining >= 5 and acc_remaining >= 3 and mkt_remaining >= 3:
    return {"passed": False, "score": 0, "feedback": "No changes detected"}
```

If the export script has a parsing bug and returns `it_remaining=53` instead of `5`, the gate still fires: `53 >= 5` is True. The do-nothing test passes (score=0), but the export is broken. Every other test scenario — partial completion, full completion — will also get wrong scores, and the bug will only surface when you manually inspect the exported JSON or run a full completion test.

**Why this is insidious**: The do-nothing test is designed as a quick sanity check. If it passes, it's tempting to assume the export is working. In reality, a passing do-nothing test only means the gate logic is sound for that specific input — it says nothing about whether the individual field values are correct.

**The Fix — Inspect exported JSON values after the do-nothing test**:

After confirming score=0, print the full result JSON and verify each field against its expected value for the seeded initial state:

```python
# After confirming score=0 from verifier:
result_json = json.loads(Path("exported_result.json").read_text())

# For a seeded task with 5 IT mismatches, 3 Accounts mismatches, etc.:
expected_initial_state = {
    "it_mismatch_remaining":   5,   # exactly the seeded count
    "acc_mismatch_remaining":  3,
    "mkt_mismatch_remaining":  3,
    "emp_117_pos_id":        "108", # the seeded wrong POS_ID
    "emp_127_pos_id":        "108",
}

for key, expected in expected_initial_state.items():
    actual = result_json.get(key)
    status = "OK" if str(actual) == str(expected) else f"WRONG (got {actual!r})"
    print(f"  {key}: {status}")
```

If any field shows `WRONG`, the export parsing is broken even though score=0. Fix the parsing bug before proceeding to partial completion testing — otherwise partial and full completion tests will give wrong scores.

**Design implication**: Where possible, design do-nothing gates using **exact equality** rather than threshold comparisons, so that parsing bugs immediately manifest as a failing do-nothing test:

```python
# Weaker gate (threshold) — may pass with broken export values:
if it_remaining >= 5: return score=0

# Stronger gate (exact equality to seeded count) — immediately reveals parsing bugs:
if it_remaining == SEEDED_IT_MISMATCH_COUNT: return score=0
```

The exact-equality approach only works if the seeded count is a constant known at design time. When it is, prefer it.

**Rule**: After every do-nothing test returns score=0, manually inspect the exported result JSON and verify each field value matches the known expected state of the freshly-seeded environment. A passing gate is not a substitute for correct export values.

---

## Lesson 61: Discover Exact Schema from the Live Database Before Writing Any SQL

**The Problem**: When creating tasks for a database-backed environment, it is tempting to write SQL (`SELECT`, `UPDATE`, `INSERT`) based on column names guessed from documentation, the application UI, or intuition. This almost always produces wrong column names, wrong table names, or wrong data types — and the failure is silent: isql/psql/sqlite3 returns an empty result or an error that is discarded, and the export script quietly reports wrong values.

Common mistakes seen in practice:
- Writing `EMP_POSITION_ID` when the actual column is `EMP_POS_ID`
- Writing `DEPARTMENT_ID` when it's `EMP_AFD_ID` (an internal foreign key)
- Writing `SELECT * FROM employees` when the table is named `EMP_EMP`
- Assuming a column exists that was removed in a newer version of the software

These bugs are especially hard to debug because the export script still runs to completion, writes a JSON with all-wrong values, and the verifier may give an accidentally correct do-nothing score (see Lesson 60).

**The Fix — Query the schema from the live database before writing a single line of SQL**:

For every environment, run schema discovery queries before creating any task files:

```bash
# Firebird — list all user tables
echo "SELECT RDB\$RELATION_NAME FROM RDB\$RELATIONS WHERE RDB\$SYSTEM_FLAG = 0;" \
    | isql -user SYSDBA -password masterkey /path/to/db.fdb -q

# Firebird — describe a specific table (column names and types)
echo "SELECT RDB\$FIELD_NAME, RDB\$NULL_FLAG FROM RDB\$RELATION_FIELDS WHERE RDB\$RELATION_NAME = 'EMP_EMP';" \
    | isql -user SYSDBA -password masterkey /path/to/db.fdb -q

# MySQL / MariaDB
mysql -u user -ppass db -N -e "SHOW TABLES;"
mysql -u user -ppass db -N -e "DESCRIBE employees;"

# PostgreSQL
psql -U user -d db -c "\dt"
psql -U user -d db -c "\d employees"

# SQLite
sqlite3 /path/to/db.sqlite ".tables"
sqlite3 /path/to/db.sqlite ".schema employees"
```

Also sample actual rows to understand real data formats and ranges:

```sql
SELECT * FROM EMP_EMP LIMIT 5;          -- see actual column values
SELECT DISTINCT EMP_AFD_ID FROM EMP_EMP; -- understand FK range
SELECT MIN(EMP_ID), MAX(EMP_ID), COUNT(*) FROM EMP_EMP; -- understand ID space
```

**Check FK constraints before seeding invalid values**: If your task requires seeding "broken" data (e.g., an employee with an invalid branch ID), check whether the FK constraint is enforced:

```sql
-- Firebird: check FK constraints on EMP_EMP
SELECT RC.RDB$CONSTRAINT_NAME, RFKS.RDB$DEPENDED_ON_NAME
FROM RDB$RELATION_CONSTRAINTS RC
JOIN RDB$REF_CONSTRAINTS RFKS ON RC.RDB$CONSTRAINT_NAME = RFKS.RDB$CONSTRAINT_NAME
WHERE RC.RDB$RELATION_NAME = 'EMP_EMP' AND RC.RDB$CONSTRAINT_TYPE = 'FOREIGN KEY';
```

If a FK is enforced, inserting an invalid value will fail (possibly silently if stderr is discarded). Either disable the constraint for testing or choose a valid value that is semantically "wrong" for the task purpose.

**Rule**: Before writing the first SQL statement in any setup or export script, run schema discovery queries against the live database in the actual VM to confirm exact table names, column names, data types, and FK constraints. Document the schema in a comment at the top of each script. This eliminates an entire class of silent failures.

---

## Lesson 62: SSH Runner Command Timeout Is the Hard Ceiling for Any Blocking Wait in `setup_task.sh`

**The Problem**: The gym_anything SSH runner enforces a per-command timeout (approximately 600 seconds). When `setup_task.sh` contains a service-readiness polling loop (e.g., `wait_for_bahmni 900`, `wait_for_openmrs 900`), the loop will be killed by the SSH runner before it reaches its own timeout, leaving setup incomplete and all setup files (`/tmp/task_*`) unwritten. This is silent from bash's perspective — the script simply stops.

**What happens**:
```
SSH command timed out: sudo -E bash -lc /workspace/tasks/my_task/setup_task.sh (timeout=600.78s)
```
The setup exits with a timeout error. All `/tmp/` files the script would have written don't exist. The export script then crashes trying to read them, producing an error result JSON with score=0. This looks like an agent failure, not a task creation bug.

**Why it matters**: 900 seconds is a common wait time chosen to "be safe" — but it exceeds the runner's 600-second budget, guaranteeing every run is killed.

**The Fix**: Keep every service-readiness polling loop strictly under the SSH timeout, with a buffer:
```bash
# BAD: exceeds the SSH runner's ~600s timeout
wait_for_bahmni 900

# GOOD: stays within budget (600s timeout - 60s buffer = 540s)
wait_for_bahmni 540
```

**How to determine the SSH timeout budget**: Look for the runner's timeout configuration in the environment's `env.json` or source code. If unknown, use 540 seconds as a safe default (assumes a ~600s runner timeout with a 60s buffer).

**Applies to**: Any `setup_task.sh` or `post_start.sh` that polls for a service to become ready before seeding data. The wait loop must fit within the SSH command timeout, not the other way around.

**Rule**: When writing any polling loop in `setup_task.sh` (e.g., `wait_for_<service> N`), ensure `N` is at least 60 seconds less than the SSH runner's command timeout. If the service takes longer than this budget to start, reconsider whether the service startup should be moved to a hook that runs outside the SSH command budget (e.g., `post_start.sh` via a longer-timeout path).

---

## Lesson 63: Export Script Must Guard Against Missing Setup Files

**The Problem**: When `setup_task.sh` fails or is killed (e.g., due to SSH timeout, service startup failure, or a script error), the `/tmp/` files it was supposed to write don't exist. An export script that reads these files directly — `cat /tmp/task_patient_uuid` or `open('/tmp/task_ids.json')` in a Python heredoc — will crash with a shell error or Python `FileNotFoundError`. The crash causes the export to exit without writing a result JSON, making the verifier fail with "cannot find result file" instead of returning a graceful score=0.

This is different from Lesson 8 (empty DB query results) — here the file was **never created**, not just empty. It is also different from Lesson 10 (missing utility functions).

**Symptom**:
```
cat: /tmp/task_patient_uuid: No such file or directory
# OR (inside Python PYEOF block):
FileNotFoundError: [Errno 2] No such file or directory: '/tmp/task_patient_uuid'
```

**The Fix — Two-layer defense**:

**Layer 1 (bash guard)**: At the top of `export_result.sh`, detect missing critical setup files and write a graceful error JSON, then exit:
```bash
PATIENT_UUID=$(cat /tmp/task_patient_uuid 2>/dev/null || echo "")

if [ -z "$PATIENT_UUID" ]; then
    cat > /tmp/my_task_result.json << 'EOF'
{"error": "Setup files not found — setup_task.sh may not have completed", "score": 0}
EOF
    echo "[EXPORT] Warning: Setup files missing, writing error result"
    echo "=== Export Complete ==="
    exit 0
fi
```

**Layer 2 (Python safe reader)**: If a Python PYEOF block reads setup files, replace direct `open()` calls with a safe helper that returns a default on failure:
```python
# BAD: crashes if file is missing
patient_uuid = open('/tmp/task_patient_uuid').read().strip()

# GOOD: returns empty string on any error
def read_file(path, default=''):
    try:
        return open(path).read().strip()
    except Exception:
        return default

patient_uuid = read_file('/tmp/task_patient_uuid')
```

**What the verifier should do**: If the export JSON contains `"error": "..."` or `patient_identifier` is `"UNKNOWN"` / empty, the wrong-target gate (Pattern 2) will correctly fire, returning score=0 with a clear message.

**Rule**: Every `export_result.sh` that reads setup files written by `setup_task.sh` must include a bash guard at the top that detects missing files and exits gracefully with a minimal error JSON. Every Python PYEOF block inside export scripts must use a safe file-reader helper rather than direct `open()` calls. Never let a missing setup file cause an uncaught exception in the export script.

---

## Lesson 64: `env.step()` Returns `None` After `done=True` — Order Wrong-Target Tests Before `mark_done`

**The Problem**: In Phase 4/5 validation scripts, it is natural to first test the do-nothing scenario (`env.step([], mark_done=True)` → verify score=0), and then, in the same `env` instance, test the wrong-target scenario by calling `env.step()` again. This does not work: once `env.step([], mark_done=True)` has returned `done=True`, the episode is finished. Any subsequent `env.step()` call on the same instance returns `None` for `info`. Calling `info.get("verifier", {})` on `None` raises:

```
AttributeError: 'NoneType' object has no attribute 'get'
```

The wrong-target test result is recorded as `null` in the test summary, silently masking whether the gate actually works.

**What breaks**:
```python
# WRONG: do-nothing test marks done, then wrong-target test tries to use the same env
obs, reward, done, info = env.step([], mark_done=True)   # done=True
result = info.get("verifier", {})                        # score=0 ✓
assert result["score"] == 0  # passes

# Trying to test wrong-target in same episode:
obs2, reward2, done2, info2 = env.step([], mark_done=True)  # info2 is None!
result2 = info2.get("verifier", {})                         # AttributeError ✗
```

**The Fix — Two options**:

**Option A (preferred): Test wrong-target BEFORE calling `mark_done`**
Set up the wrong-target scenario by modifying verifier inputs before marking done. For web apps where the export result always captures the correct patient identifier from the DB (regardless of agent actions), the wrong-target gate fires when the DB has no data for the correct patient — which is exactly the do-nothing state. So in the do-nothing test, check both score=0 AND confirm the feedback contains the expected "wrong patient" or "no data" message.

**Option B: Use a separate `env.reset()` for each test scenario**
```python
# Test 1: do-nothing
env.reset(seed=42, use_cache=True)
obs, reward, done, info = env.step([], mark_done=True)
assert info["verifier"]["score"] == 0

# Test 2: wrong-target (fresh reset — fresh episode)
env.reset(seed=42, use_cache=True)
# ... inject wrong-target state here ...
obs, reward, done, info = env.step([], mark_done=True)
assert info["verifier"]["score"] == 0
```

Option B is cleaner for complex wrong-target injection tests (e.g., ones that modify DB state or the agent's browsing history). It requires an additional `env.reset()` call (~5 minutes for QEMU), which is acceptable during Phase 5 validation.

**Rule**: In any Phase 4/5 validation script, never call `env.step()` after a prior call has already returned `done=True` on the same `env` instance. Either perform all test scenarios before calling `mark_done=True`, or call `env.reset()` to start a fresh episode between scenarios. Check for `info is None` defensively and log a warning rather than crashing.

---

## Lesson 65: `pre_start` Idempotency Must Check Service Liveness, Not File Existence

**The Problem**: Server-class applications (web servers, databases, DevOps platforms, ERPs, etc.) typically install in two distinct phases: (1) extract/copy binaries, and (2) configure/initialize the server. If the `pre_start` hook is interrupted between phases (SSH disconnect, timeout, OOM kill), the binaries will be present on disk but the server will not be configured. On the next `env.reset()`, a naive idempotency check — `if Test-Path $binaryPath` or `if [ -f /usr/bin/appname ]` — sees the binary and exits early, permanently skipping Phase 2.

```powershell
# BAD: exits early if binary exists, even if server is not configured
if (Test-Path "C:\Program Files\MyApp\myapp.exe") {
    Write-Host "Already installed."
    exit 0
}
```

**The Fix**: Check that the *service is running*, not that the binary is present:

```powershell
# GOOD: only skips if the service is actually running
$svc = Get-Service -Name "MyAppService" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host "Already installed and running."
    exit 0
}

# If binary exists but service is not running, skip download/extract but still configure
if (Test-Path "C:\Program Files\MyApp\myapp.exe") {
    Write-Host "Binaries present but not configured. Skipping to Phase 2 (configure)..."
    # fall through to configuration step
}
```

For Linux/Docker-based apps:
```bash
# GOOD: check service is responding, not just that the binary is installed
if systemctl is-active --quiet myapp && curl -sf http://localhost:8080/health; then
    echo "Already installed and healthy."
    exit 0
fi
```

**General Rule**: For server applications, the idempotency guard in `pre_start` (and in `install_*.sh`) must verify that the application is *operational* (service running, health endpoint responding, or a reliable readiness signal), not merely that its files were extracted. Use the liveness signal appropriate to the application:
- Windows service: `Get-Service -Name X | Where-Object Status -eq Running`
- Linux systemd: `systemctl is-active X`
- Web application: `curl -sf http://localhost/health` or equivalent
- Database: `pg_isready`, `mysqladmin ping`, `sqlcmd -Q "SELECT 1"`

---

## Lesson 66: Windows Service Configuration May Require SYSTEM Privileges, Not Just Administrator

**The Problem**: On Windows, running a script via SSH (even as a member of the `Administrators` group) does not grant the same privileges as running as `SYSTEM`. Certain Windows operations — performance counter registration, service account configuration, COM object access, registry ACL setup — require `SYSTEM`-level privileges and silently fail or throw cryptic errors when run as a non-SYSTEM admin user.

A real example: `tfsconfig configure` (Azure DevOps Server setup) fails with an error at the "UnloadLegacyPerfCounters" step when run as an SSH admin user, but succeeds when run as SYSTEM.

**Symptom**: Setup commands that work fine when run manually from the Windows desktop (where the user has full interactive session tokens) fail when run via `exec_capture()` / SSH with access-denied or "handle is invalid" errors.

**The Fix — Use Task Scheduler to run as SYSTEM**:

```powershell
# Write the command to a temp script file
$script = "C:\Windows\Temp\run_as_system.ps1"
"& 'C:\Path\To\configure.exe' /args | Out-File 'C:\Windows\Temp\configure.log'" | Set-Content $script -Encoding UTF8

# Create and immediately run a scheduled task as SYSTEM
$taskName = "RunAsSystemTask"
schtasks /create /tn $taskName /tr "powershell.exe -ExecutionPolicy Bypass -File $script" /sc ONCE /st 00:00 /ru SYSTEM /f | Out-Null
schtasks /run /tn $taskName | Out-Null

# Poll for completion by monitoring the log file
$maxWait = 300
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 5
    $state = (schtasks /query /tn $taskName /fo LIST 2>&1 | Select-String "Status").ToString()
    if ($state -match "Ready|Disabled") { break }
}
schtasks /delete /tn $taskName /f | Out-Null
```

**When to apply**: Any `pre_start` or `post_start` script that:
- Registers Windows services or performance counters
- Modifies HKLM registry keys with strict ACLs
- Runs installers or configuration tools for server-class applications (IIS, SQL Server, Active Directory, etc.)
- Reports "Access is denied" or "handle is invalid" when run through SSH despite the user being in Administrators

**Note**: `schtasks /IT` runs as the interactive desktop user (Lesson 52). For privileged *configuration* work (not GUI interaction), `/ru SYSTEM` is the correct flag.

---

## Lesson 67: PowerShell Script Gotchas Unique to Windows Task Scripts

Several PowerShell-specific bugs surface regularly when writing `setup_task.ps1` and `export_result.ps1` for Windows environments. They are each subtle and produce no obvious error message until strict mode or a specific PS version is hit.

### 67a. `Set-StrictMode` Crashes on Missing Properties of PSCustomObjects

PowerShell's `Set-StrictMode -Version Latest` (a recommended defensive measure) throws a `PropertyNotFoundException` when you access a property that doesn't exist on a `PSCustomObject` — including objects returned by `ConvertFrom-Json`. This is different from Python (`None`), JavaScript (`undefined`), or even PowerShell without strict mode (silently returns `$null`).

```powershell
# BAD: throws "The property 'field' cannot be found" with Set-StrictMode
$val = $item.fields."System.AssignedTo"

# GOOD: check existence first using PSObject.Properties
$val = if ($item.fields.PSObject.Properties["System.AssignedTo"]) {
    $item.fields."System.AssignedTo"
} else { $null }
```

This applies to any field on an API response object that might be absent (e.g., unset work item fields, optional user profile fields, nullable config values).

### 67b. `ConvertTo-Json -AsArray` Requires PowerShell 7+

Windows ships with PowerShell 5.x as the system default. The `-AsArray` flag for `ConvertTo-Json` was added in PS 7 and does not exist in PS 5.x, causing a silent parameter-binding error where the array is converted as a single object instead.

```powershell
# BAD: -AsArray only exists in PS 7+; on PS 5.x this silently omits the flag
$json = $myArray | ConvertTo-Json -AsArray

# GOOD: works in PS 5.x and PS 7+
$json = ConvertTo-Json -InputObject @($myArray) -Depth 10
```

Always check `$PSVersionTable.PSVersion.Major` if you're unsure. Default Windows 11 and Windows Server 2019/2022 VMs use PS 5.x unless PowerShell 7 was explicitly installed.

### 67c. Variable Name Followed by a Colon Is Parsed as a PSDrive Reference

In PowerShell, `$name:` is the syntax for PSDrive variables (e.g., `$env:PATH`, `$function:MyFunc`). If a variable name appears immediately before a colon in a string, PowerShell silently substitutes an empty string (or throws in strict mode) instead of the variable's value.

```powershell
# BAD: $bugId: is interpreted as a PSDrive — prints nothing or throws
Write-Host "Bug #$bugId: unassigned"

# GOOD: use braces to delimit the variable name
Write-Host "Bug #${bugId}: unassigned"
```

This applies to any interpolated string where a variable is immediately followed by a colon — common in log messages ("ID: $id:", "Error: $code:"), API paths, and structured text.

### 67d. Double-Quoted Here-Strings Interpret Backticks as Escape Characters

In PowerShell `@"..."@` here-strings, the backtick `` ` `` is the escape character (like `\` in most languages). Code snippets, Markdown, or JSON strings containing backticks will be silently mangled.

```powershell
# BAD: backtick in description is consumed as escape char; em-dashes may cause JSON errors
$body = @"
{
  "description": "Uses `jwt` library"
}
"@

# GOOD: single-quoted here-string — no escape processing at all
$body = @'
{
  "description": "Uses `jwt` library"
}
'@
```

Use `@'...'@` whenever the string contains backticks, em-dashes, special Unicode, or any content that should be entirely literal. If you need variable interpolation AND literal backticks, escape the backtick as ` `` ` (double backtick) in a double-quoted here-string.

---

## Lesson 68: REST API Depth/Limit Parameters Often Have Undocumented Maximums

**The Problem**: Many REST APIs accept a depth, level, or limit parameter with no documented ceiling. When you exceed the maximum, the API silently returns a truncated or partial result with no error — the response is `200 OK` and looks structurally correct, but data is missing.

A real example: the Azure DevOps `$depth` parameter for the queries API accepts `1`, `2`, but silently ignores `3+`, returning only the top 2 levels of a nested query tree. A script querying `$depth=3` receives a valid JSON object with missing child nodes and no indication that truncation occurred.

**Detection**: If a tree or list query returns fewer items than expected and no error was thrown, suspect a silent truncation. Test with incrementing values (`$depth=1`, then `2`, then `3`) and compare results.

**The Fix — Use the lowest depth that gives sufficient data, and verify empirically**:

```powershell
# BAD: assuming depth=3 returns full tree (API silently caps at 2)
$queries = Invoke-Api "/wit/queries/Shared%20Queries?`$depth=3"

# GOOD: use depth=2 (empirically verified maximum for this endpoint)
$queries = Invoke-Api "/wit/queries/Shared%20Queries?`$depth=2"
```

**General Rule**: When an API call returns fewer results than you expect and no HTTP error is raised, the first thing to check is whether a depth, level, limit, or page-size parameter has a silent maximum. Always test export scripts against a populated environment to verify the full expected data is returned, not just that the script runs without error. Document empirically-discovered maximums in a comment next to the API call.

---

## Lesson 69: `reward_type: "sparse"` Is Required for `info["verifier"]` to Be Populated

**The Problem**: Every `task.json` must set `"reward_type": "sparse"`. If you use `"dense"` (or omit the field and inherit a default that becomes dense), `env.step()` never populates `info["verifier"]`. Every test that inspects `info.get("verifier", {})` will receive an empty dict, and the do-nothing test will report `score=None` / `passed=None` instead of `score=0` / `passed=False`. This failure is completely silent — the environment boots, the step runs, the episode ends — nothing indicates that verification was skipped.

**Why it happens**: `env.py` contains code equivalent to:
```python
if self.reward_type == "sparse":
    info["verifier"] = summary.get("verifier")
```
Dense reward mode calculates a continuous reward signal differently and bypasses the verifier summary entirely.

**Symptoms**:
- `info.get("verifier")` returns `None` or `{}`
- Do-nothing test shows `score=None, passed=None` instead of `score=0, passed=False`
- No error or warning is raised
- The verifier function itself is never called

**The Fix**: In every `task.json` you create, set:
```json
"init": {
    "reward_type": "sparse"
}
```

**Verification**: After writing `task.json`, grep for `reward_type` before running any test:
```bash
grep reward_type benchmarks/cua_world/environments/<env>/tasks/<task>/task.json
# Must output: "reward_type": "sparse"
```

**Rule**: Always explicitly set `"reward_type": "sparse"` in every `task.json`. Never rely on a default. If you see `score=None` or `passed=None` in a test result that you expect to give `score=0`, the first thing to check is `reward_type`.

---

## Lesson 70: Discover Config Key Names from INI/Preference Files by Change-and-Diff

**The Problem**: Many desktop apps store their settings in INI files, Windows registry keys, `.plist` files, or other opaque config formats. The config key names (e.g., `BcGracePeriod`, `SendKeysPostfix`, `FlipBitmap`) are internal implementation names, not the labels shown in the UI ("Delay (seconds)", "Terminating character", "Flip camera image"). They are typically:
- Not documented in any user-facing manual
- Abbreviated or encoded differently from the UI label
- Locale-specific (especially for numeric formats — see below)
- Potentially absent from the file entirely until the user changes the setting from its factory default

Writing `setup_task.sh`/`setup_task.ps1` or `export_result.ps1` that reads or writes the wrong key silently does nothing: the setting isn't changed, the export reads a wrong value, and the task appears to work (do-nothing test passes) while actually being broken for real agent runs.

**The Fix — Change-and-Diff**:

For EVERY setting you intend to use in a task, discover the exact key name experimentally:

1. Launch the application fresh (or with `setup_task.ps1` run once to establish the starting INI).
2. Take a baseline copy of the config file:
   ```bash
   cp ~/.config/myapp/settings.ini /tmp/settings_before.ini
   # or on Windows:
   # Copy-Item $iniPath C:\Windows\Temp\settings_before.ini
   ```
3. Change EXACTLY ONE setting in the application UI to a known value.
4. Close the application (force-quit if necessary, to flush config to disk).
5. Diff the config file:
   ```bash
   diff /tmp/settings_before.ini ~/.config/myapp/settings.ini
   # Shows exactly which key changed and what the new value looks like
   ```
6. Record: the key name, the section it belongs to (for INI files), and the value format.
7. Repeat for every setting involved in your task.

**What to look for in the diff**:
- **Key name casing**: Config keys are often CamelCase or SCREAMING_SNAKE_CASE regardless of UI labels
- **Value format**: Booleans may be `True`/`False`, `1`/`0`, `yes`/`no`, or `enabled`/`disabled`
- **Decimal separators**: Windows apps use the system locale — a German-locale Windows writes `0,8` not `0.8` for opacity values. Verifiers must compare as strings, not parse as floats
- **Missing key = factory default**: Some settings are omitted from the file until first changed. The absence of a key means "use application default", not zero or false

**Example discovery log**:
```
Setting: "Delay after scan (BcGracePeriod)"
Section: [General]
Key:     BcGracePeriod
Values:  0=none, 1=1s, 2=2s, 3=3s (integer stored as string "3")

Setting: "Opacity"
Section: [Overlay]
Key:     Opacity
Values:  uses Windows system decimal separator — "0,8" (not 0.8) on German locale

Setting: "Terminating key"
Section: [General]
Key:     SendKeysPostfix
Values:  "{TAB}", "{ENTER}", "" (empty string = no postfix)
```

**In verifiers, compare locale-specific values as strings**:
```python
# BAD: float() fails on "0,8" (German locale comma decimal)
opacity = float(result["general"].get("Opacity", "0"))

# GOOD: compare as string exactly as the app stores it
opacity = result["general"].get("Opacity", "")
if opacity == expected_opacity:   # e.g., expected_opacity = "0,6"
    score += 33
```

**Rule**: Before writing a single line of `setup_task.ps1`, `export_result.ps1`, or `verifier.py` for any config-file-based application, perform change-and-diff experiments for every setting your task involves. Document the discovered key names, sections, and value formats in a comment block at the top of each script. Never guess config key names from UI labels or documentation — they are almost always different.

---

## Lesson 71: PowerShell `ConvertTo-Json` Silently Produces No Output for Nested Hashtable Objects

**The Problem**: `ConvertTo-Json` in Windows PowerShell 5.x silently fails (produces truncated or empty output) when the input hashtable contains values that are themselves complex PowerShell objects — particularly hashtables nested inside hashtables where inner values include special characters (`{`, `}`, `null`, multi-line strings, or high Unicode). The resulting JSON may be truncated mid-object, syntactically invalid, or never written to disk at all if piped to `Set-Content`. No error is raised.

This is a common pattern in Windows `export_result.ps1` scripts where `$generalSection` and `$barcodeSection` are combined into a single nested hashtable:
```powershell
# BAD: may produce truncated JSON silently
$result = @{
    task    = "my_task"
    general = $generalSection      # itself a @{} hashtable
    barcode = $barcodeSection      # itself a @{} hashtable
}
$result | ConvertTo-Json -Depth 5 | Set-Content $outPath -Encoding UTF8
# → result file never created, or created but invalid JSON
```

**The Fix — Use a manual JSON string template**:

Write the JSON as a here-string, interpolating each individual field value directly. Then write it to disk with `[System.IO.File]::WriteAllText()` (which does NOT add a BOM):

```powershell
# GOOD: manual JSON construction — reliable across all PS versions
$json = @"
{
  "task": "my_task",
  "general": {
    "SendKeysPostfix": "$(Esc $skp)",
    "BcGracePeriod":   "$(Esc $grace)",
    "Beep":            "$(Esc $beep)",
    "Opacity":         "$(Esc $opacity)"
  },
  "barcode_l_type": "$(Esc $blType)"
}
"@
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.Encoding]::UTF8)
```

Where `Esc` is a helper function that escapes backslashes and double-quotes:
```powershell
function Esc($s) { if ($null -eq $s) { return "" }; return $s -replace '\\','\\' -replace '"','\"' }
```

**Why `[System.IO.File]::WriteAllText()` instead of `Set-Content`**:
- `Set-Content -Encoding UTF8` adds a BOM (`\xef\xbb\xbf`) that breaks Python's `json.load()` (see Lesson 24)
- `[System.IO.File]::WriteAllText(..., [System.Text.Encoding]::UTF8)` writes UTF-8 without BOM

**When to use**: Any `export_result.ps1` with more than one level of nesting (i.e., the result JSON has object-valued fields, not just string/number fields). As a conservative rule: if your export needs to build a JSON with nested objects at all, prefer the manual here-string approach over `ConvertTo-Json`.

**Rule**: Do not rely on `ConvertTo-Json` to correctly serialize nested `@{...}` hashtables in Windows PowerShell 5.x. For any export that produces a multi-level JSON result, use a manual JSON here-string template and write it with `[System.IO.File]::WriteAllText()`. This eliminates both the nested-serialization bug and the BOM encoding bug in a single change.

---

## Lesson 72: Companion Reference Documents as Difficulty Amplifiers for Hard Tasks

**The Pattern**: Create a companion document (audit report, compliance notice, specification sheet, lab report, email thread) that contains the specific values the agent must apply, then reference only the *document* in the task description — not the values themselves.

**Why it's powerful**:
- Forces multi-step reasoning: read document → extract values → navigate application → apply corrections
- Makes a task "very hard" even when each individual UI action is straightforward
- Reflects realistic professional workflows: people act on *external notifications*, not memorized procedures
- Creates natural partial credit: agent might read the document and make some corrections but miss others
- Prevents pattern-matching on task description text — agent must actually understand the document

**Implementation**:
```
data/
  task_source_data.xml       ← pre-seeded with errors/missing data
  reference_document.txt     ← contains all specific correction values

task.json description:
  "Read the audit report at C:\workspace\data\reference_document.txt
   and apply all corrections to the Lakeside Chemical Supply record."
  # NOT: "Change Hydrogen Peroxide average to 4,200 lbs, update Sulfuric Acid
  #       storage location to 'Drum Storage Building B', ..."
```

**What the companion document should contain**:
- The specific field/record to correct and why it is wrong
- The correct value to enter
- Who/what authority requires the correction (adds realism)

**What the companion document should NOT contain**:
- Step-by-step UI navigation instructions — the agent must discover these
- Anything that makes the task trivial if the agent only reads the description (those specifics belong in the document, not the description)

**Applies to any domain** where professionals receive external notifications requiring data corrections:
- Regulatory/compliance software: SERC/EPA audit findings, inspection reports
- Healthcare: lab reports requiring EMR updates, insurance denial notices
- Financial: audit letters, quality control findings, reconciliation discrepancies
- Scientific: calibration certificates, protocol change notices, data quality flags
- Engineering: ECO (engineering change orders), defect reports, spec updates

**Naming the document in the task description**: Use language that a professional would recognise — "the audit report", "the compliance notice", "the lab report". Avoid "the hints file" or "the answer key".

---

## Lesson 73: Embedding Discovery Information Inside Application Records

**The Pattern**: Place the information an agent needs to discover (what contact to add, what value to set, what configuration to apply) inside the application's own data — in a notes, description, or comments field of the record — rather than in the task description.

**Why it's powerful**:
- Agent must navigate *into* the application and read the specific record before it knows what to do next
- Mirrors real workflows: action items, onboarding checklists, and contact details live inside the records themselves
- Harder to shortcut: the agent cannot deduce the answer from the task description alone
- Works even when the app has no external file I/O — the "discovery" happens inside the app's UI

**Example** (regulatory software):
```xml
<!-- Contact section is empty; notes field contains what the agent must create -->
<facility>
  <facilityName>Montpelier Industrial Supply</facilityName>
  <notes>Emergency coordinator contact information pending update by
         Robert Flanagan (802-555-0219), designated as
         Fac. Emergency Coordinator.</notes>
  <!-- No <contact> elements — agent must read the notes and add them -->
</facility>
```

**vs. putting everything in the task description** (too easy for hard tasks):
```
# BAD for hard/very_hard — everything is handed to the agent:
"Add Robert Flanagan (phone: 802-555-0219) as Fac. Emergency Coordinator
 to Montpelier Industrial Supply."

# GOOD for hard/very_hard — agent must discover details from the record:
"The two facilities in C:\workspace\data\central_vt_facilities.xml have
 their emergency contact information noted in their facility records.
 Add the appropriate contacts as indicated."
```

**How to implement**:
1. Seed the data file/database record with a **populated notes/description field** containing the required action
2. Leave the **target field empty** (no existing contact, no fire district set, no value present)
3. Task description points to the facility/record set but does NOT spell out the specific values

**Applies to any app with free-text fields on records**:
- EMR/EHR: patient notes, encounter notes → agent must read to know what to update
- CRM: customer account notes, opportunity descriptions → discovery before action
- Project management: ticket/issue descriptions → requirements embedded in the ticket
- Inventory/ERP: item notes, purchase order comments → specifications to act on
- Scientific software: sample metadata, experiment descriptions → parameters to apply
- Any structured data app: the "notes" or "comments" field is the universal vehicle

**Seeding tip**: The notes field content should read like a real professional entry, not a task description. A facility notes field saying *"Emergency coordinator contact information pending update by Robert Flanagan (802-555-0219)"* is realistic; one saying *"TODO: add contact Robert Flanagan with phone 802-555-0219 and type Fac. Emergency Coordinator"* is not.

**Combining with Lesson 72**: These two patterns stack. The companion document (Lesson 72) tells the agent *which records* to look at and *why* corrections are needed; the embedded notes tell the agent *what specifically* to do in each record. Using both creates a genuine two-layer discovery workflow that is extremely realistic and extremely hard.

---

### 68a. Partial-Test Injection for File-Output Tasks: Inject the Agent's Output File, Not the Result JSON

**The Problem**: The `env.step([], mark_done=True)` pipeline always runs `export_result.sh` **before** the verifier. For file-output tasks (where the agent writes a report/CSV/text file), if you try to inject a partial result by writing directly to the intermediate result JSON (e.g., `/tmp/<task>_result.json`), `export_result.sh` will overwrite it before the verifier reads it — silently discarding your injection.

**What breaks**:
```python
# WRONG — inject into result JSON, then call step()
env._runner.exec_capture(f"echo '{partial_json}' > /tmp/my_task_result.json")
obs, reward, done, info = env.step([], mark_done=True)
# ↑ export_result.sh runs first, overwrites /tmp/my_task_result.json
# verifier reads the real (empty) result instead of your injection → info["verifier"] is None or wrong
```

**What actually happens in the pipeline**:
```
env.step([], mark_done=True)
    → runs export_result.sh   ← reads agent's output file, writes result JSON
    → runs verifier.py        ← reads result JSON
```

**The Fix**: For partial-completion testing in file-output tasks, inject content into the **agent's output file** (what the agent would write), then let `export_result.sh` process it normally:
```python
# CORRECT — inject into the agent's output file, let export run naturally
write_cmd = f"""python3 -c "
content = {repr(partial_content)}
with open('/home/ga/Documents/my_report.txt', 'w') as f:
    f.write(content)
" """
env._runner.exec_capture(write_cmd)

# Now let export_result.sh process it → it reads the file, writes result JSON
obs, reward, done, info = env.step([], mark_done=True)
result = info.get("verifier", {})  # Now has partial score
```

**Rule**: For partial-completion testing, always inject at the **same level as the agent** (the output file the agent would create), never at the intermediate JSON level. The result JSON is a temporary artefact owned by `export_result.sh`.

**Also applies to**: Database-backed environments where the agent would normally call an API or write to a DB. Don't mock the result JSON — instead directly manipulate the DB/API state as the agent would, then let `export_result.sh` query it.

---

### 68b. Keyword Co-Occurrence for Semantic Correctness in Free-Text Report Tasks

**The Problem**: When a task asks the agent to write a free-text report (an analysis, an audit, an investigation), simple keyword presence checks are too permissive. A word like "acetone" appearing in a chemical inventory list scores the same as "acetone" appearing in a sentence like "Hydrogen Peroxide + Acetone is an explosive combination." A keyword match detects *mention*, not *meaning*.

**Observed symptom**: A "partial" test report that listed chemicals in an inventory section, never flagging them as dangerous pairs, nonetheless triggered all the "dangerous pair identified" verifier checks — and scored 100% when it should have scored ~45%.

**The Fix**: For verifying semantic content (e.g., "agent identified X as dangerous"), require **co-occurrence** of the subject keyword with a relevance/hazard descriptor:

```bash
# BAD — triggers if "acetone" appears anywhere in the report (inventory list, background section, etc.)
if echo "$FILE_CONTENT" | grep -qi "acetone"; then
    MENTIONS_ACETONE=1
fi

# BETTER — requires "acetone" near a hazard-relevant term
if echo "$FILE_CONTENT" | grep -qi "acetone" && \
   echo "$FILE_CONTENT" | grep -qi "react\|hazard\|incompatible\|explosive\|dangerous\|peroxide"; then
    ACETONE_HAZARD_FLAGGED=1
fi
```

Or use a single `grep` with a proximity-sensitive pattern:
```bash
# Checks if a paragraph contains BOTH terms (paragraph = empty-line delimited block)
awk 'BEGIN{RS=""; FS="\n"}
     /[Aa]cetone/ && /[Pp]eroxide|hazard|react|incompatible/ {found=1}
     END {exit !found}' "$FILE" && ACETONE_PAIR_FLAGGED=1 || ACETONE_PAIR_FLAGGED=0
```

**In the verifier.py**: Structure the scoring so that identifying a chemical name alone gives partial credit, but only the correct characterization (reaction, hazard type, risk level) awards full points:
```python
# Partial credit for noticing the chemical
if mentions_chemical_a and mentions_chemical_b:
    score += 10  # Partial: both chemicals in report
    # Full credit only if the hazard is described
    if hazard_keyword_present:
        score += 20  # Full: correctly characterized the interaction
```

**When this matters most**: Any task where:
- The agent writes a long report covering many entities
- Chemical names, drug names, or other domain terms appear in multiple contexts
- You need to distinguish "correctly analyzed X" from "coincidentally mentioned X"

**When this doesn't matter**: Tasks where the agent produces structured output (fills in a form field, writes a CSV with exact column names). Keyword co-occurrence is a mitigation for the fundamental ambiguity of free-text verification — if the output is structured, use structural checks instead.

---

## Lesson 74: Force-Killing Electron / LevelDB Applications Erases Their Configuration

Electron-based desktop applications (and other apps using LevelDB, RocksDB, or similar write-ahead-log storage) store session configuration — account credentials, user preferences, window layout — in a `Local Storage/leveldb/` directory under the application's config path (e.g., `~/.config/AppName/Local Storage/leveldb/`). LevelDB writes use a write-ahead log format; when the process is force-killed, pending writes may not be flushed. On the next startup, the application recovers the log, finds it inconsistent, and resets to defaults.

**What breaks**:
```bash
# setup_task.sh that kills an Electron app (e.g., a desktop mail client)
pkill -f myapp    # ← WRONG: loses account configuration in LevelDB
sleep 3
su - ga -c "DISPLAY=:1 myapp &"
# After restart: app shows first-run wizard as if no account exists
```

**Diagnosis**: Check LevelDB content before and after the kill:
```bash
strings /home/ga/.config/MyApp/Local\ Storage/leveldb/*.log | grep -i "account"
# Before kill:  "nextAccountNum":1,"accountSettings":{"accounts":{"0":{...}}}
# After kill and restart: "nextAccountNum":0,"accountSettings":{"accounts":{}}
```

**The Fix**: Never force-kill the application in setup scripts when its configuration must be preserved. Instead:
1. Keep the application running throughout setup if you only need to change backend data (see Lesson 75)
2. If the application must be stopped, use a graceful shutdown (`wmctrl -c "AppName"`, `SIGTERM` + wait) and allow it to close cleanly before making changes; a clean shutdown flushes all pending LevelDB writes

**Applies to**: Any app using LevelDB (`~/.config/<App>/Local Storage/leveldb/`), RocksDB, or other WAL-based storage for application state. Common examples: Electron apps (VS Code, Slack, Discord, Signal, WhatsApp Desktop, Mattermost, and many desktop email/calendar clients), Chromium-based embedded browsers.

**Distinction from the SQLite lesson** ("App Startup Overwrites Externally-Inserted SQLite Records"): That lesson covers restarting an app after external DB manipulation causing the app to overwrite your changes. This lesson covers the opposite direction: the kill itself destroying data before any restart occurs.

---

## Lesson 75: Stopping Backend Services While a Frontend Wizard Has an Active Connection Freezes the Wizard

When a desktop application's first-run setup wizard initiates a connection to a backend service (IMAP server, database, OAuth endpoint), stopping that service mid-connection does not produce a clean "connection failed" response. Instead, the wizard waits for the TCP connection to time out or close, leaving it frozen on the connection/testing step. The wizard remains stuck for the duration of that session.

**What breaks**:
```bash
# setup_task.sh stops the IMAP server while the email client's wizard is mid-connection:
systemctl stop dovecot    # ← WRONG: severs the ongoing IMAP connection
# Result: the email client's IMAP settings wizard hangs indefinitely,
# never advances past "Testing connection..."
```

**The Fix**: Avoid stopping any backend service that a running frontend application may be connecting to. Instead:
1. **Manipulate data directly** (write files, insert DB rows) while the service stays running
2. **Use the service's own admin/invalidation tools** to flush caches or re-index:
   ```bash
   # For Dovecot: re-index Maildir without a service restart
   doveadm index -u ga INBOX
   doveadm index -u ga SomeFolderName

   # For MySQL: flush caches without restarting
   # mysql -u root -e "FLUSH TABLES;"

   # For PostgreSQL: no restart needed for DML changes — they're visible immediately
   ```
3. **If service restart is truly required** for seeding (e.g., config file changes that need reload), do it in `post_start.sh` or at the very start of `setup_task.sh`, before the frontend application is launched

**General principle**: In a running GUI environment, your setup script shares the system with the running application. Backend service restarts are not isolated — they affect all active connections. The safest pattern is:
```
manipulate data files / DB directly
       ↓
use service admin tools (re-index, flush, SIGHUP)
       ↓
let the application's next sync or refresh pick up the changes
```

**Applies to**: Any environment where a desktop GUI application (email client, browser, GUI tool) has a setup wizard or polling loop that maintains a live connection to a backend service, and the setup script runs while that application is already open.

---

## Lesson 76: Controlled Data Corruption for Database QA/Audit Tasks

**The Pattern**: Tasks involving data quality, auditing, or remediation require a database that has specific, measurable problems for the agent to find and fix. The cleanest way to achieve this is:
1. **Copy** the real production database to a task-specific file (never modify the original)
2. **Introduce exactly N problems** via targeted SQL (`DELETE`, `UPDATE`, `INSERT`)
3. **Record the counts** of each introduced issue to `/tmp/GT.json` *immediately after corruption*
4. The agent's job is to find and fix those problems; the verifier compares post-fix counts against GT

This is the database equivalent of Lesson 15 (planted bugs in config/code files), but for **relational data integrity** rather than syntax/logic issues.

**Why copy, not modify in place**: If the task fails or is re-run, `setup_task.sh` can always recreate the corrupted copy from the clean original. Modifying the original permanently would break every other task that uses it.

**Concrete example** (SQLite):
```bash
# setup_task.sh
CLEAN_DB="/home/ga/Documents/databases/chinook.db"
AUDIT_DB="/home/ga/Documents/databases/chinook_audit.db"

# Step 1: fresh copy
cp "$CLEAN_DB" "$AUDIT_DB"

# Step 2: introduce exactly 6 orphaned invoice_items
# by deleting their parent invoices (1–6)
sqlite3 "$AUDIT_DB" "DELETE FROM invoices WHERE InvoiceId BETWEEN 1 AND 6;"

# Get the resulting orphan count (should be sum of line items for those invoices)
ORPHAN_COUNT=$(sqlite3 "$AUDIT_DB" \
    "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId NOT IN (SELECT InvoiceId FROM invoices);")
echo "Orphaned invoice_items: $ORPHAN_COUNT"

# Step 3: introduce NULL Composer values in a known range
ROCK_GENRE_ID=$(sqlite3 "$AUDIT_DB" "SELECT GenreId FROM genres WHERE Name='Rock';")
sqlite3 "$AUDIT_DB" \
    "UPDATE tracks SET Composer = NULL WHERE TrackId BETWEEN 1 AND 200 AND GenreId=$ROCK_GENRE_ID;"
NULL_COMPOSER_COUNT=$(sqlite3 "$AUDIT_DB" \
    "SELECT COUNT(*) FROM tracks WHERE Composer IS NULL AND GenreId=$ROCK_GENRE_ID;")
echo "Null Rock composers: $NULL_COMPOSER_COUNT"

# Step 4: save ground truth
python3 << PYEOF
import json
with open('/tmp/audit_gt.json', 'w') as f:
    json.dump({
        "orphaned_invoice_items": $ORPHAN_COUNT,
        "null_rock_composers":    $NULL_COMPOSER_COUNT,
    }, f)
print("Ground truth saved")
PYEOF
```

**In the verifier**: Load GT from the export JSON (which reads it from `/tmp/`), then check post-fix counts:
```python
gt = result.get("ground_truth", {})
remaining_orphans    = result.get("orphaned_invoice_items_remaining", gt["orphaned_invoice_items"])
remaining_null_comp  = result.get("null_composers_remaining", gt["null_rock_composers"])

# Full points if agent fixed ALL issues
if remaining_orphans == 0:
    score += 25
elif remaining_orphans < gt["orphaned_invoice_items"]:
    score += 12   # partial credit for partial fix
```

**Key design rules**:
- Use `DELETE parent` (not `DELETE child`) to create orphans — this tests the agent's understanding of FK relationships, not just SQL syntax
- Use a known range (`TrackId BETWEEN 1 AND 200`) so the count is deterministic
- Verify the corrupted DB still opens and queries correctly after setup — don't make it so broken that DBeaver refuses to connect
- The agent should NOT be told exactly how many issues exist; that's what they need to discover via queries
- Export script re-queries the AUDIT DB at task end; verifier compares against GT saved at setup

**Applies to**: Any database environment (SQLite, PostgreSQL, MySQL, Firebird) where the task involves data quality, referential integrity repair, audit, or remediation. The same pattern works for column-level corruption (NULL, wrong type, out-of-range values), row-level corruption (duplicates, missing required records), and cross-table issues (orphaned FKs, dangling references).

---

## Lesson 77: Ground Truth Pre-Computation at Setup Time (GT-in-Setup Pattern)

**The Problem**: Many database tasks ask the agent to compute something from the data — "find the top-5 territories by revenue," "which genre has the highest average rating," "what is the most common composer." The correct answer depends on the actual data loaded into the database, not on a hardcoded expected value. If you hardcode the expected value in the verifier, it will silently break whenever the data changes (task re-seeded, different dataset version).

**The Pattern**: In `setup_task.sh`, run the "correct" query using the same database the agent will use, and save the result to `/tmp/<task>_gt.json`. `export_result.sh` reads this GT and includes it in the result JSON. The verifier then compares the agent's output against the GT — without re-running the query itself.

```bash
# setup_task.sh — compute GT from actual data at setup time
python3 << 'PYEOF'
import sqlite3, json

conn = sqlite3.connect("/home/ga/Documents/databases/northwind.db")

# GT: top 5 territories by revenue (what the agent should find)
rows = conn.execute("""
    SELECT t.TerritoryDescription, SUM(od.Quantity * od.UnitPrice) AS Revenue
    FROM territories t
    JOIN employeeterritories et ON t.TerritoryID = et.TerritoryID
    JOIN orders o ON et.EmployeeID = o.EmployeeID
    JOIN "order details" od ON o.OrderID = od.OrderID
    GROUP BY t.TerritoryID
    ORDER BY Revenue DESC
    LIMIT 5
""").fetchall()

gt = {
    "top_territories": [{"name": r[0].strip(), "revenue": round(r[1], 2)} for r in rows],
    "top_territory_name": rows[0][0].strip() if rows else "",
    "top_territory_revenue": round(rows[0][1], 2) if rows else 0,
}
with open('/tmp/northwind_territory_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print(f"GT saved: top territory = {gt['top_territory_name']} (${gt['top_territory_revenue']:,.2f})")
PYEOF
```

```bash
# export_result.sh — include GT in result JSON for verifier comparison
GT=$(cat /tmp/northwind_territory_gt.json 2>/dev/null || echo '{}')
cat > /tmp/territory_result.json << EOF
{
    "agent_top_territory": "$AGENT_TOP_TERRITORY",
    "agent_revenue":        $AGENT_REVENUE,
    "ground_truth":         $GT
}
EOF
```

```python
# verifier.py — compare agent output against GT, no hardcoded values
gt = result.get("ground_truth", {})
expected_name = gt.get("top_territory_name", "")
expected_rev  = gt.get("top_territory_revenue", 0)

agent_name = result.get("agent_top_territory", "")
agent_rev  = result.get("agent_revenue", 0)

if agent_name.lower() == expected_name.lower():
    score += 20
if expected_rev > 0 and abs(agent_rev - expected_rev) / expected_rev <= 0.10:
    score += 20  # within 10% of correct revenue
```

**Why this is better than hardcoding**:
- Verifier stays correct if the dataset is updated or re-seeded
- Task works even if the dataset download produces a slightly different version
- Easy to support multiple "acceptable" answers (e.g., top-3 acceptable instead of exact top-1)
- The GT can include multiple fields (count, names, values) for multi-criterion verification

**When to use**: Any task where the correct answer is a function of the input data:
- Aggregation queries (SUM, AVG, COUNT, MAX) — answer depends on actual data values
- Ranking queries (TOP N by X) — depends on distribution
- Existence checks that depend on seeded data (e.g., "orphan count" after setup corruption — see Lesson 76)
- Any task where you would otherwise hardcode an expected value

**When NOT to use**: Tasks with behavior independent of data — "create an index named X on table Y," "set the connection timeout to 30s." These are procedural tasks with known correct actions regardless of data.

**Security against GT staleness**: Save the GT timestamp in the GT JSON. If the export script detects the GT was saved before setup completed (e.g., a stale file from a previous run), it should re-compute or fail with a warning. Adding `"setup_timestamp": $(date +%s)` to the GT JSON and checking it in `export_result.sh` provides this guarantee.

**Rule**: For any database task where the correct answer is a computed value from the data, always pre-compute the expected result in `setup_task.sh` using the actual database, save it to `/tmp/`, and pass it through the export JSON to the verifier. Never hardcode expected query results in verifier.py.

---

## Lesson 78: Use Python via Temp File for Complex Data Processing in PowerShell Export Scripts

**The Problem**: Windows QEMU environments use `.ps1` (PowerShell) scripts for `export_result.ps1`. PowerShell's built-in CSV and JSON cmdlets (`Import-Csv`, `ConvertFrom-Json`, `Select-Object`) work well for simple field extraction, but become cumbersome for complex analysis: flexible column name detection, encoding-agnostic CSV parsing, floating-point arithmetic across hundreds of rows, fuzzy string matching (e.g., finding an item name in a CSV column that might use slightly different naming), or any logic involving multiple passes over data. Writing this logic inline in PowerShell produces verbose, brittle code that is hard to debug.

**The Pattern**: Embed the analysis logic as a Python script defined using a single-quoted PowerShell here-string, write it to `C:\Windows\Temp\`, execute it via `& python $script $args`, and have Python write its results to a temp JSON file that PowerShell reads back. This is the PowerShell equivalent of Lesson 37's bash temp Python file pattern.

```powershell
# export_result.ps1 — complex CSV analysis delegated to Python

$pythonScript = @'
import sys, csv, json, io, os

input_file  = sys.argv[1]
result_path = sys.argv[2]

items_found = {}
row_count   = 0

if os.path.exists(input_file):
    try:
        with open(input_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            content = f.read()
        reader    = csv.DictReader(io.StringIO(content))
        name_col  = None
        price_col = None
        for row in reader:
            row_count += 1
            if name_col is None:
                for k in row.keys():
                    if 'name' in k.lower() or 'item' in k.lower():
                        name_col = k; break
            if price_col is None:
                for k in row.keys():
                    if 'price' in k.lower() or 'sell' in k.lower():
                        price_col = k; break
            if name_col and price_col:
                name = str(row.get(name_col, '')).strip().lower()
                raw  = str(row.get(price_col, '0')).replace('$','').replace(',','').strip()
                try:    items_found[name] = float(raw)
                except: pass
    except Exception as e:
        print(f"Parse error: {e}", file=sys.stderr)

output = {"row_count": row_count, "items_found": items_found}
with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(output, f, indent=2)
print(f"Parsed {row_count} rows, {len(items_found)} named items")
'@

# 1. Write script using WriteAllText (NOT Out-File) to avoid BOM on the .py file itself
$pyScript    = "C:\Windows\Temp\parse_clearance.py"
$tempResult  = "C:\Windows\Temp\parse_result.json"
[System.IO.File]::WriteAllText($pyScript, $pythonScript)

# 2. Execute, passing file paths as arguments
$agentOutput = "C:\Users\Docker\Desktop\clearance_inventory.csv"
$pyOut       = & python $pyScript $agentOutput $tempResult 2>&1
Write-Host "Python parser output: $pyOut"

# 3. Read results from the JSON file (not from stdout, which may contain escape codes)
$parseResult = @{ row_count = 0; items_found = @{} }
if (Test-Path $tempResult) {
    try {
        $parseResult = Get-Content $tempResult -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Host "Failed to read parse result: $($_.Exception.Message)"
    }
}
```

**Four PowerShell-specific rules**:

1. **Single-quoted here-string `@' ... '@`** (not `@" ... "@`): Single-quoted here-strings suppress all variable expansion. Python code contains `$`-prefixed variable names that would be interpreted as PowerShell variables in a `@" ... "@` here-string, silently corrupting the Python script.

2. **`[System.IO.File]::WriteAllText()` for writing the `.py` file** (not `Out-File` or `Set-Content -Encoding UTF8`): Both `Out-File -Encoding UTF8` and `Set-Content -Encoding UTF8` add a UTF-8 BOM to the file in PowerShell 5.x. A BOM in a `.py` file can cause `SyntaxError: source code string cannot contain null bytes` or other interpreter-level issues. `WriteAllText()` with `[System.Text.Encoding]::UTF8` (the default when no encoding is specified) writes BOM-free UTF-8.

3. **Pass file paths as arguments, write results to a JSON file**: Do not capture Python stdout to parse results. PowerShell reading Python stdout via `$out = & python ... 2>&1` may include terminal escape codes (see Lesson 51). Writing to a temp JSON file and reading with `Get-Content | ConvertFrom-Json` is reliable.

4. **`$ErrorActionPreference = "Continue"` in export scripts** (not `"Stop"` like in setup scripts): Export scripts must produce a valid result JSON even when the Python parser encounters a malformed CSV, a missing file, or a type error. With `"Stop"`, any PowerShell error (including the Python execution call) crashes the export entirely and leaves no result JSON for the verifier to score. With `"Continue"`, the export degrades gracefully — zero items parsed is still a valid result, scored as 0 by the verifier.

**Why Python instead of PowerShell for this analysis**:
- `csv.DictReader` provides flexible column-name detection and handles encoding edge cases
- `encoding='utf-8-sig'` transparently strips BOMs from agent-created CSV files
- `errors='replace'` survives malformed byte sequences in files the agent exported from the application
- Floating-point arithmetic and string matching are more predictable in Python than in PowerShell (which has surprising behavior with numeric string comparison under `Set-StrictMode`)

**Applies to**: Any Windows QEMU environment where `export_result.ps1` needs to parse a CSV, validate structured text output, or perform multi-step data analysis. Python is typically available in Windows QEMU VMs used for business software environments (installed as part of the base image or alongside the main application).

**Rule**: In Windows QEMU `export_result.ps1` scripts, delegate any analysis beyond simple field lookup to Python. Define the Python as a `@' ... '@` single-quoted here-string, write it to `C:\Windows\Temp\` with `[System.IO.File]::WriteAllText()`, execute via `& python $script $args`, and have Python write its output to a second temp JSON file. Set `$ErrorActionPreference = "Continue"` in `export_result.ps1` so that parse failures produce a graceful zero-score result rather than crashing the export entirely.

---

### 55. Date Parsing Fallback Must Default to False, Not True

**The Problem**: When checking "was this record created after the task started?", the fallback on date-parse failure must be `False`, not `True`. Using `True` as the fallback turns any unparseable timestamp into a false positive — the verifier silently awards points for pre-existing records.

**What broke**:
```python
try:
    created = datetime.fromisoformat(created_str.replace('Z', '+00:00'))
    created_after = created >= task_start
except:
    created_after = True  # BUG: rewards any record whose date fails to parse
```

**Why it fails more than you'd expect**: Python 3.10's `datetime.fromisoformat()` is stricter than Python 3.11+. It rejects:
- Milliseconds: `2024-01-15T10:30:00.000+00:00` → `ValueError`
- Offset without colon: `2024-01-15T10:30:00+0000` → `ValueError`
- Offset without colon: `2024-01-15T10:30:00.123+0000` → `ValueError`

Many web services (DHIS2, OpenMRS, Canvas LMS) emit exactly these formats. If your QEMU base is Ubuntu 22.04, Python 3.10 is the default.

**The Fix**: Always use a robust parser and default to `False`:
```python
import re
from datetime import datetime, timezone

def parse_api_date(s):
    """Parse date strings from web APIs. Returns None on failure (do NOT default to True)."""
    if not s:
        return None
    # Normalize to Python 3.10-compatible ISO format
    s = s.replace('Z', '+00:00')
    s = re.sub(r'([+-])(\d{2})(\d{2})$', r'\1\2:\3', s)  # +0000 -> +00:00
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        pass
    # Strip milliseconds and retry
    s2 = re.sub(r'\.\d+', '', s)
    try:
        return datetime.fromisoformat(s2)
    except ValueError:
        return None  # Return None, let the caller decide (default False)

created_dt = parse_api_date(created_str)
created_after = (created_dt is not None and created_dt >= task_start)  # False if parse failed
```

**Rule**: The `created_after_start` flag must be `False` by default, not `True`. A record whose timestamp cannot be parsed should never earn points.

---

### 56. Demo Environments Have Setup-Time Timestamps — Use ID Sets, Not Timestamps

**The Problem**: In environments where demo/sample data is loaded during the QEMU setup phase (pre_start/post_start hooks), every pre-seeded record has a `created` timestamp from setup time — which is *after* the task_start timestamp recorded by setup_task.sh. A simple `created >= task_start` check therefore treats ALL demo data as agent-created.

**When this happens**: Any environment that runs a database seed or data import as part of installation:
- Health IS (DHIS2 Sierra Leone demo loaded during install)
- EHR systems (OpenMRS demo patients inserted at boot)
- LMS (Canvas/Moodle sample courses created by setup script)
- CRM/ERP systems with bundled demo company data

**Why counts alone are insufficient**: If you filter by keyword ("malaria" dashboards, "Jayson Fadel" patients) AND the keyword matches a pre-existing record, the record count increases from 0→N across the board, but that N is all pre-seeded data, not agent work. The do-nothing test will score non-zero.

**The Fix**: In `setup_task.sh`, record the full set of matching IDs — not just the count:

```bash
# In setup_task.sh — record ALL current IDs for anything matching your search criteria
dhis2_api "dashboards?fields=id&paging=false" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ids = [x['id'] for x in d.get('dashboards', [])]
    print('\n'.join(ids))
except: pass
" > /tmp/initial_dashboard_ids
```

In `export_result.sh`, detect new records by ID-set membership, not timestamp:
```python
# Load initial IDs recorded at task start
initial_ids = set()
try:
    with open('/tmp/initial_dashboard_ids') as f:
        initial_ids = {line.strip() for line in f if line.strip()}
except:
    pass

# A record is "new" only if its ID was not present at task start
is_new = record_id not in initial_ids
```

**Relationship to Pattern 1**: Pattern 1 (Baseline Recording) already recommends recording IDs. This lesson explains *why* it's mandatory for environments with demo data — timestamp comparison is not a reliable substitute when the environment seeds data at setup time.

---

### 57. Background Services Are Not Immediately Ready on Cached Boot

**The Problem**: When booting from a `pre_start` checkpoint (vs. a full install), background services that run in Docker/systemd are stopped and then restarted by the `post_start` hook. The VM becomes SSH-accessible almost immediately, but the service takes 30–120 seconds more to fully initialize. If `setup_task.sh` queries the service during this window, it silently gets 0 results and records a wrong baseline.

**Failure mode**:
1. setup_task.sh records `initial_record_count = 0` (service not ready yet)
2. Agent runs, service is now ready, pre-seeded data appears
3. Export finds N records. Verifier sees `current=N, initial=0` → awards points incorrectly

**The Fix**: In `setup_task.sh`, poll the service with a health check before recording any baselines:

```bash
# Wait for the service to be ready (adapt URL/command to your environment)
echo "Waiting for service to be ready..."
MAX_WAIT=90
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/health" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "Service ready after ${WAITED}s"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "WARNING: Service may not be fully ready. Baseline counts may be 0."
fi

# NOW record baselines — service is (probably) ready
INITIAL_COUNT=$(query_service ...)
```

**Why this matters for the do-nothing test**: If the service is not ready during setup AND not ready during export, the do-nothing test still passes (score=0). But if the service is ready during export but not during setup, the initial baseline is wrong and the test fails.

**Rule**: Always include a startup wait loop in `setup_task.sh` for any environment that runs a non-trivial background service (web server, database, Docker container). The wait should complete *before* recording any initial state.

---

## Lesson 79: Desktop Applications That Embed Compressed Data in Their Native File Format

**The Problem**: Some desktop applications save their native files as XML (or JSON) with the actual diagram/content embedded as a **base64-encoded, compressed blob** inside an attribute or element. If you try to parse the file with `grep` or a standard XML parser, you find nothing — the content text is not human-readable.

**Example**: draw.io Desktop (`.drawio` files) stores its diagram XML like this:

```xml
<mxfile ...>
  <diagram id="..." name="Page-1">
    7VhNc5swEP01PqYDiM/HxHHTQ6adSQ+dHGVYg1ohUCHi+N9XAmEMdpr2...
  </diagram>
</mxfile>
```

The inner text is `base64(raw-deflate(diagram_xml))`. Attempting `grep -i "service-name" file.drawio` will find nothing even if the service name is present.

**The Fix**: In your `export_result.sh`, decompress the content before grepping:

```bash
python3 - <<'PYEOF'
import xml.etree.ElementTree as ET
import base64
import zlib
import json

tree = ET.parse('/home/ga/Desktop/output.drawio')
root = tree.getroot()

all_text = ""
for diagram in root.findall('.//diagram'):
    raw = diagram.text or ""
    raw = raw.strip()
    if raw:
        try:
            # Try base64 + raw-deflate (wbits=-15)
            decoded = base64.b64decode(raw)
            xml_bytes = zlib.decompress(decoded, -15)
            all_text += xml_bytes.decode('utf-8', errors='replace')
        except Exception:
            # Fall back to plain text (uncompressed XML)
            all_text += raw

# Now grep all_text for keywords, count shapes, edges, etc.
import re
num_shapes = len(re.findall(r'<mxCell[^>]+vertex="1"', all_text))
num_edges  = len(re.findall(r'<mxCell[^>]+edge="1"',   all_text))
num_pages  = len(root.findall('.//diagram'))

result = {"num_shapes": num_shapes, "num_edges": num_edges, "num_pages": num_pages}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
print("Export Complete")
PYEOF
```

**General principle**: Before writing any keyword-search logic for a desktop application's output file, open the raw file with `cat` or `xxd | head` and confirm whether the content is human-readable. If you see mostly alphanumeric garbage with `=` padding at the end of lines, it's base64. Pipe it through `base64 -d | zlib-flate -uncompress` (or `python3 -c "import zlib,base64,sys; print(zlib.decompress(base64.b64decode(sys.stdin.read()), -15).decode())"`) to confirm.

**Other affected formats**: LibreOffice `.ods`/`.odt` (ZIP+XML), Inkscape SVG with compressed layers, some GIS formats (`.qgs` with embedded base64 icons), certain IDE project files.

**Rule**: Always manually decode and inspect a sample output file from the target application before writing `export_result.sh`. If the content is compressed, implement decompression in Python (not shell) and perform all content analysis on the decompressed string.

---

## Lesson 80: MD5 Anti-Copy-Paste Gate for "Edit a Starter File" Tasks

**The Problem**: Tasks that provide a starter file and ask the agent to correct/expand it are vulnerable to a trivial strategy: copy the starter file verbatim to the output path. A pure timestamp check (`file_modified_after_start`) does not catch this, because the file can be written after the task start even if it has identical content to the starter.

**The Fix**: Record the MD5 of the starter file during setup, then compare in the export script:

```bash
# In setup_task.sh — record MD5 of the starter file
md5sum /home/ga/Diagrams/partial_diagram.drawio | awk '{print $1}' > /tmp/partial_md5
cp /home/ga/Diagrams/partial_diagram.drawio /home/ga/Diagrams/starter_backup.drawio
```

```bash
# In export_result.sh — compute MD5 of the output file
STARTER_MD5=$(cat /tmp/partial_md5 2>/dev/null || echo "")
OUTPUT_MD5=$(md5sum /home/ga/Desktop/output.drawio 2>/dev/null | awk '{print $1}')

IS_COPY_OF_PARTIAL="false"
if [ -n "$STARTER_MD5" ] && [ "$OUTPUT_MD5" = "$STARTER_MD5" ]; then
    IS_COPY_OF_PARTIAL="true"
fi
```

Then in `verifier.py`, check this as a mandatory gate **before any other scoring**:

```python
if result.get('is_copy_of_partial'):
    return {
        "passed": False,
        "score": 0,
        "feedback": "Output is identical to the starter file. The file must be corrected.",
        "subscores": {"is_copy": True}
    }
```

**When to use**: Any task where:
1. A starter/partial/template file is provided to the agent, AND
2. The expected output is a modified version of that same file at a different path

This pattern is a stronger companion to `file_modified_after_start`: timestamps confirm *when* the file was written; MD5 confirms *what* was written. Use both together.

**Do NOT apply this pattern** when the output is a completely new file type (e.g., starter is `.drawio` but output is `.svg` or `.png`). In that case, file identity is impossible, and the timestamp check is sufficient.

**Naming convention**: Store the hash in `/tmp/<task_name_prefix>_md5` (e.g., `/tmp/partial_md5`, `/tmp/template_md5`). Store it as the raw hex string (no filename), so the comparison in the export script is a simple string equality test.

---

## Lesson 81: QEMU Work Dir Disk Quota on Cluster / NFS Home Filesystems

**The Problem**: On university clusters, HPC nodes, and shared servers, the home directory (`~`) is typically on an NFS filesystem with a per-user disk quota (e.g., 100 GB). The QEMU runner defaults to placing its work directory inside `~/.cache/gym-anything/qemu/work/`. When `use_savevm=True`, the runner **copies** the entire checkpoint qcow2 file (which can be 8–20 GB) into the work dir before starting QEMU. This immediately exceeds the home quota, producing an `[Errno 122] Disk quota exceeded` error and preventing any VM from booting.

**Why it's not obvious**: `df -h ~` may show, say, 16 GB free on the filesystem — but the OS-level quota is a per-user limit tracked separately by the NFS server. The user can be over quota even when the shared filesystem still has free blocks, and the `quota` command is often blocked by NFS. The symptom is `OSError: [Errno 122]` during `tempfile.mkdtemp()`, which looks like a random OS error rather than a quota issue.

**The Fix**: Redirect the QEMU work directory to a quota-free local filesystem (typically `/tmp` or `/scratch` on cluster nodes) using the `GYM_ANYTHING_QEMU_WORK_DIR` environment variable:

```bash
# In shell before running any gym_anything Python code:
export GYM_ANYTHING_QEMU_WORK_DIR=/tmp/qemu_work
mkdir -p /tmp/qemu_work
```

```python
# Or set it in Python before importing gym_anything:
import os
os.environ['GYM_ANYTHING_QEMU_WORK_DIR'] = '/tmp/qemu_work'
os.makedirs('/tmp/qemu_work', exist_ok=True)

from gym_anything import from_config
env = from_config(...)
```

**Check available space first**:
```bash
df -h /tmp /scratch 2>/dev/null   # find quota-free filesystem with enough space
# Need: ~2× the checkpoint size (copy + running disk). For 8 GB checkpoint → need ~16 GB free in /tmp
```

**Does NOT affect checkpoints**: The `GYM_ANYTHING_QEMU_WORK_DIR` only controls the ephemeral per-run work directory (the running disk.qcow2 copy). Checkpoints are still stored in `~/.cache/gym-anything/qemu/` and are read-only at run time, so they don't trigger quota writes.

**Rule**: In any Phase 4 test script that may run on a cluster or shared server, always set `GYM_ANYTHING_QEMU_WORK_DIR=/tmp/qemu_work` at the top of the script, before calling `from_config()`.

---

## Lesson 82: Orphaned QEMU Work Directories Accumulate After Timeouts

**The Problem**: Every `env.reset()` call creates a new temporary work directory inside `QEMU_WORK_DIR` (e.g., `ga_qemu_<hash>_<random>/`). When a Python process is killed by a timeout signal (e.g., the shell's `timeout` command), the QEMU process is also killed but the work directory is left behind — the runner's `stop()` cleanup code never runs. Over hundreds of test runs and timeouts, thousands of orphaned directories accumulate. Even though each directory is essentially empty (no disk.qcow2 because QEMU was killed mid-copy or never started), they consume inodes and can trigger inode-based quota limits.

**The Symptom**: `ls ~/.cache/gym-anything/qemu/work/ | wc -l` reports 6,000+ directories, almost all empty.

**The Fix — Periodic cleanup**:
```bash
# Find and remove work dirs that have NO disk.qcow2 (orphaned, no active VM)
# Run this ONLY when no QEMU processes are running (check first)
ps aux | grep qemu-system | grep -v grep
# If no QEMU procs running, safe to clean:
for d in ~/.cache/gym-anything/qemu/work/*/; do
    [ ! -f "$d/disk.qcow2" ] && rm -rf "$d"
done
echo "Remaining: $(ls ~/.cache/gym-anything/qemu/work/ | wc -l)"
```

**Safety rule**: Never remove a work directory that contains `disk.qcow2` — it may belong to a currently running VM. Only remove directories where `disk.qcow2` is absent.

**When to run**: Run this cleanup at the start of any evidence-collection or Phase 4 test session. It takes <30 seconds for thousands of dirs and can free significant inode usage.

---

## Lesson 83: Application Socket Initialization Is Dramatically Slower After QEMU loadvm

**The Problem**: When `use_savevm=True`, QEMU's `loadvm` instantly restores the VM's memory and CPU state, including all running processes. However, many application processes that expose **Unix socket proxies** (Docker Desktop's `docker.sock` proxy, database TCP listeners, web server accept queues) enter a "zombie socket" state immediately after `loadvm`. The socket file *exists* on disk and the process is *running*, but every API call through the socket returns a 5xx error or hangs for 20–30 seconds before failing.

**The Concrete Example**: Docker Desktop's `docker.sock` proxy takes 15–20 minutes to fully reinitialize after `loadvm`, even though the Docker Desktop process appears healthy. Each `docker info` call blocks for ~30 seconds before returning a 500 error. A `wait_for_docker_daemon` loop written as `for i in {1..60}; do sleep 2; docker info && break; done` (expecting 120s total) actually runs for **30 minutes** because each iteration takes 30s, not 2s.

**Why this happens**: The OS network stack is rebuilt from scratch after `loadvm`. Sockets created before the snapshot have their kernel-side state reset. Multi-process applications (like Docker Desktop's backend + proxy + frontend) need to detect this state change internally and re-establish their IPC channels — a process that can take many minutes.

**Design patterns for wait loops in `setup_task.sh` and `setup_<app>.sh`**:

```bash
# BAD: Assumes each iteration is short (it may block for 30s+)
for i in {1..60}; do
    docker info > /dev/null 2>&1 && { echo "ready"; break; }
    sleep 2
done

# GOOD: Set a per-call timeout to prevent blocking
for i in {1..30}; do
    if timeout 5 docker info > /dev/null 2>&1; then
        echo "Docker ready after ${i} attempts"
        break
    fi
    sleep 2
done
```

**Alternative: check process health first, socket second**:
```bash
# Fast process check (instant) before slow API check
if pgrep -f "com.docker.backend" > /dev/null; then
    echo "Docker Desktop process running, checking socket..."
    timeout 10 docker info > /dev/null 2>&1 && echo "Socket ready"
fi
```

**Implication for `env.reset()` timing**: If your `post_start` hook waits for a slow-socket application, `env.reset()` with `use_cache=True, cache_level="pre_start", use_savevm=True` may take 20–30 minutes instead of the expected 5 minutes. Plan your Phase 4 test scripts with generous `timeout` values (1800–3600 seconds) or, better, use a `post_start` checkpoint (which caches the application in a fully running state so the socket is ready immediately after loadvm).

**Rule**: For any environment where the `post_start` hook starts an application that exposes a socket-based API, use `cache_level="post_start"` (not `"pre_start"`) to capture the fully-running state in the checkpoint. This way, `loadvm` restores the application with its socket already operational.

---

## Lesson 84: Use `python3 -u` for Background Phase 4 Test Monitoring

**The Problem**: When running a Phase 4 test script in the background with output redirected to a log file (`python3 script.py > log.log 2>&1 &`), the log file stays at 0 bytes for many minutes. This makes it impossible to monitor progress — you cannot tell if the script is running correctly or silently stuck.

**Why it happens**: Python uses block buffering (typically 8 KB) when stdout is not a TTY. All `print()` output accumulates in memory until the buffer fills or the process exits. For long-running scripts with modest output (e.g., Phase 4 tests that boot VMs and wait for results), the buffer may never fill during the run.

**The Fix**: Use `python3 -u` (unbuffered) or set `PYTHONUNBUFFERED=1`:

```bash
# Option 1: -u flag (simplest)
python3 -u /tmp/test_phase4.py > /tmp/phase4.log 2>&1 &

# Option 2: environment variable
PYTHONUNBUFFERED=1 python3 /tmp/test_phase4.py > /tmp/phase4.log 2>&1 &

# Option 3: sys.stdout.flush() after each print (useful inside scripts)
import sys
print("VM booted"); sys.stdout.flush()
```

**In test scripts, use `flush=True`**:
```python
# Add flush=True to critical progress prints so they appear immediately in logs
print(f"[{time.strftime('%H:%M:%S')}] Reset complete!", flush=True)
print(f"Score: {score}", flush=True)
```

**Rule**: All Phase 4 test scripts that run in the background should use `python3 -u` or `flush=True` on key `print()` statements so progress is visible in real time via `tail -f log.log`.

---


## Lesson 86: Structural Wrong-Target Gate for Subsystem/Pipeline Tasks

**The Problem**: Pattern 2 in `03_verification_patterns.md` covers the classic wrong-target case — agent modifies the wrong named entity (wrong patient, wrong record ID). But many tasks involve *configuring a subsystem, pipeline, or workflow area* (e.g., "configure the pvbms energy node", "set up the zone submetering inputs", "configure the smartmeter processlist") rather than editing a record identified by an ID. For these tasks, the wrong-target scenario has a different signature:

- The **target-specific indicators** (e.g., `pvbms_feed_count`, `zone_feed_count`, `import_steps`) are all 0
- But **generic indicators** (e.g., `new_feed_count`, `total_records_modified`) may be non-zero — because the agent did real work, just on the wrong subsystem

A verifier that checks `if new_feed_count >= 4: score += 20` will award partial credit to the wrong-target scenario, because 4 feeds were created — just for a different node.

**The Fix**: Add a GATE at the top of the verifier that checks: "did the agent touch the TARGET subsystem at all?" If not, return score=0 immediately.

```python
def verify_<task>(traj, env_info, task_info):
    # ...parse result JSON...

    # GATE: Structural wrong-target check
    # If the primary target-specific indicator is 0 AND there are no target-specific
    # entities created, the agent configured the wrong subsystem → score=0
    if result.get('target_steps', 0) == 0 and result.get('target_entity_count', 0) == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: target subsystem was not configured. "
                        "Agent may have modified a different pipeline/node/area.",
            "subscores": {}
        }

    # Normal scoring below...
```

**What to use as the gate condition**: Choose the most specific indicator that can ONLY be non-zero if the agent worked on the correct target:
- For a workflow pipeline: `(primary_input_steps == 0 AND target_specific_feed_count == 0)`
- For a zone/region config: `(all_zone_steps_zero AND zone_specific_feed_count == 0)`
- For a form/record type: `(target_record_count == 0 AND target_field_modified == False)`

**Caveat on partial credit**: The gate must not fire for *partially correct* work. If an agent correctly configured only 1 of 3 required zones, the gate should allow scoring to proceed (some zone steps are non-zero). Design the gate to only trigger when there is literally no evidence of work on the target.

**Rule**: Any task where the "target" is a subsystem or pipeline (not a uniquely-identified record) needs a structural wrong-target gate in addition to — or instead of — the standard entity-ID comparison.

---

## Lesson 87: `max(target_count, generic_count)` in Verifiers Silently Credits Off-Target Work

**The Problem**: A common impulse when writing feed/record count criteria is to be "flexible" and use `max()` across two counts:

```python
# "Be flexible: count either target-specific OR total new"
feed_count = max(result.get('zone_feed_count', 0), result.get('new_feed_count', 0))
if feed_count >= 6:
    score += 25
```

The intent is good: maybe the export script can't perfectly distinguish which feeds belong to the target vs. other nodes, so use the larger of the two. But this is a security hole. In a wrong-target scenario, `zone_feed_count = 0` but `new_feed_count = 4` (feeds created for a different node), so `max(0, 4) = 4`, which earns partial credit.

**The Fix**:

```python
# CORRECT: Use only the target-specific count; the gate already ensures non-zero target work
feed_count = result.get('zone_feed_count', 0)  # Only zone-specific feeds
if feed_count >= 6:
    score += 25
elif feed_count >= 4:
    score += 15
```

Combined with the structural wrong-target gate (Lesson 86), this is safe: if zone_feed_count is 0 AND zone_steps are 0, the gate already returns score=0 before reaching this criterion.

**Diagnostic**: Run a wrong-target test (payload with all target-specific indicators = 0 but non-zero generic counts). If the score is non-zero, look for `max()`, `or`, or implicit fallbacks in the criteria.

**Rule**: In criteria that count created entities (feeds, records, files, etc.), use ONLY the most specific count available. Reserve generic counts (`new_feed_count`, `total_records`) for summary/diagnostic reporting in the export JSON, not as fallbacks in scoring.

---

## Lesson 88: Partial Test Payload Must Yield Score STRICTLY Below Pass Threshold

**The Problem**: When designing a partial completion test, it's easy to accidentally create a payload that achieves exactly the pass threshold score. For example, if `pass_threshold = 60` and each of 5 subtasks is worth 20 points, fixing exactly 3/5 subtasks gives 60 points, which is `score >= 60` → `passed = True`. The "partial" test then incorrectly reports `passed = True`.

**Example**:
```python
# Scoring: 5 subtasks × 20pts = 100pts, pass_threshold = 60
# Partial payload: subtasks 1, 2, 3 fixed → 20+20+20 = 60pts → passed = True ← WRONG
```

**The Fix**: Design the partial test payload to complete either:
- `floor(pass_threshold / pts_per_subtask) - 1` subtasks (strictly below threshold), or  
- A specific combination whose total is explicitly verified to be < threshold

```python
# GOOD: Only fix 2 of 5 subtasks → 40pts → passed = False ✓
partial_payload = {
    "subtask_1_fixed": True,   # 20pts
    "subtask_2_fixed": True,   # 20pts
    "subtask_3_fixed": False,  # 0pts
    "subtask_4_fixed": False,  # 0pts
    "subtask_5_fixed": False,  # 0pts
}
# Total: 40pts < 60 threshold → passed = False ✓
```

**Systematic check**: After creating your partial payload, mentally compute its score:
1. Sum all points from `True` fields
2. Verify `sum < pass_threshold`
3. Verify `sum > 0` (partial, not do-nothing)

**Rule**: Never use `ceil(pass_threshold / pts_per_subtask)` subtasks in a partial payload without verifying the total. Always calculate the exact score. A partial payload that achieves exactly the pass threshold (e.g., 60/100 when threshold=60) is incorrect — it must be strictly below.

---

## Lesson 89: Gate "Context" Criteria on "Outcome" Criteria to Prevent Navigation-Menu False Positives

**Context**: Many verifiers include a "soft" criterion worth a few points that checks whether the agent is on the correct screen or section of the application — e.g., "Three-phase power calculator is visible (15 pts)." These criteria are typically implemented as keyword searches over the UI dump or displayed text. The problem is that application navigation menus, sidebars, and home screens display the **names of every section** in the app. When the agent does nothing, the app is often sitting on the main menu, which already contains every section label.

**The Problem**:
```
App main menu text (do-nothing UI dump):
  "Three Phase Power Calculator"
  "Single Phase Power"
  "Cable Size Calculator"
  "Reactive Power"
  "Line Current / Phase Current Converter"
  ...
```

A keyword check like `any(kw in combined for kw in ['three phase', 'reactive', 'apparent'])` will match all of these menu items — scoring 15 points in the do-nothing test.

**This is not unique to mobile apps.** Desktop GUI apps (web browsers, IDEs, CAD tools) similarly display menu bars, toolbars, and sidebars that name every available feature. Web apps often show dashboard links. Any environment where navigation exposes section names will trigger this false positive.

**The Fix**: Gate the context criterion on at least one outcome criterion being satisfied.

```python
# BAD: keyword alone — matches app navigation menu in do-nothing
if _has_threephase_keywords(texts):
    score += 15

# GOOD: keyword AND at least one result found
any_result = reactive_found or real_found or apparent_found
if _has_threephase_keywords(texts) and any_result:
    score += 15
```

**Why this is correct**: If a numeric result is on screen, the agent *must* be on the calculator result screen (not the menu), so the keyword check is meaningful. If no result is found, the keyword match is meaningless noise from the navigation menu.

**Broader principle**: Criteria that check CONTEXT ("is the agent on screen X?") should only award points when there is also evidence of OUTCOME ("did the agent accomplish something on screen X?"). A context criterion that fires when the agent simply opened the app is not testing the task.

**When to apply**:
- Any criterion based on "does the UI contain keyword K?" where K could appear in a navigation sidebar, main menu, tab bar, or toolbar
- Any "screen presence" criterion (e.g., "calculator is visible", "editor is open", "form is displayed")
- When do-nothing score for this criterion is non-zero and no numerical results are present

**Rule**: Before finalizing any keyword-based criterion, ask: "Would this keyword appear in the main menu / home screen / navigation of the app even if the agent did nothing?" If yes, gate the criterion on a mandatory outcome criterion.

---

## Lesson 90: Avoid Scale-Factor Arithmetic and Excessive Tolerance in Numeric Verifiers

**Context**: Verifiers for calculator-type applications sometimes add "convenience" logic to `_number_near` or similar functions to handle unit-scaled display values — for example, matching `16.627` (kVA display) against target `16627` (VA) by checking `abs(num * 1000 - target) <= margin`. This seems helpful but creates **severe false positives** from unrelated numbers that happen to be near the scaled target.

**Problem 1: Kilo-scale multiplication**

```python
# BAD: adds kilo-scale matching
def _number_near(numbers, target, tol_pct=3.0):
    margin = abs(target) * tol_pct / 100.0
    for num in numbers:
        if abs(num - target) <= margin:        # direct match
            return True
        if abs(num * 1000 - target) <= margin: # BUG: num=4.9 → 4900 ≈ 4894
            return True
```

With `target=4894` and `tol_pct=3`, margin = 146.8. Any number between 4.747 and 5.041 on screen — a version string "4.9", a percentage "4.9%", a decimal in an unrelated label — will match via `num * 1000`. The do-nothing screen of many apps (navigation menus, version labels, system status bars) can easily contain such a number.

**Problem 2: Overly permissive tolerance for discrete values**

```python
# BAD: 10% tolerance for discrete cable sizes
common_sizes = [1.5, 2.5, 4.0, 6.0, 10.0]
for size in common_sizes:
    if _number_near(numbers, size, 10.0):  # 10% tolerance
        return True
```

With 10% tolerance, target `4.0mm²` has margin 0.4. Any number between 3.6 and 4.4 on screen matches. A calculator button labeled "4" → 4.0, or the number "4" anywhere on screen, matches perfectly. Results that come in discrete standard sizes should not use percentage tolerance matching at all — they should require the **unit label** to be present in the text.

**The Fixes**:

```python
# GOOD: no scale-factor arithmetic, direct match only
def _number_near(numbers, target, tol_pct=3.0):
    target = float(target)
    if target == 0:
        return False
    margin = abs(target) * tol_pct / 100.0
    for num in numbers:
        if abs(num - target) <= margin:
            return True
    return False

# GOOD: discrete results require unit text, not number matching
def _has_cable_size_result(texts, numbers):
    combined = ' '.join(texts)
    # Match only when the unit label is explicitly shown (e.g. "4.0 mm²")
    # Do NOT match bare numbers — calculator buttons (4, 6, etc.) would falsely match
    return 'mm²' in combined or 'mm2' in combined or 'awg' in combined
```

**General rules**:

1. **Never multiply or divide parsed numbers by unit factors** (×1000, ÷1000, etc.) inside `_number_near`. The app always displays results in a single unit — find out what that unit is and use it as the target. If the app displays "16,627 VA" then the target is 16627, not 16.627.

2. **Tolerance must be calibrated to real display precision**. For a calculator showing results to the nearest integer, 3% tolerance is reasonable. For discrete-value results (standard cable sizes, standard resistor values, dropdown options), require the **unit text** to appear alongside a plausible number instead of number-matching alone.

3. **Before adding any scale transformation**, test the do-nothing scenario manually: extract all numbers from the UI dump and verify that none of them, when multiplied/divided by the scale factor, fall within the tolerance band of any target value.

4. **When results are displayed as exact integers** (e.g., "9976 VAR"), do not accept scaled-decimal variants. A real agent will see "9976" on screen, not "9.976". Reject the kilo/mega form entirely.

**Rule**: Keep `_number_near` simple — direct range check only. Handle unit scale by using the correct target value for the unit the app actually displays, not by adding arithmetic inside the tolerance check.

---

## Lesson 91: GUI Accessibility Tree Dump as a Verification Source

**When to use this pattern**: Some tasks have the agent interact entirely within a GUI application that writes no output files and updates no database — it only changes what's visible on screen. Examples: a mobile app where the agent creates list entries, a desktop tool where the agent fills in on-screen forms, or any application that stores data only in memory or its own opaque internal store. In these cases the standard verification toolkit (SQL queries, file parsing, JSON result files) does not apply. The accessibility tree is the correct verification source.

**What is the accessibility tree?** Every modern GUI toolkit exposes an accessibility API for screen readers and automated testing. This API provides a structured description of every visible UI element — buttons, labels, list items, text fields — with their full text content, even when the on-screen display is visually truncated (e.g., "Pre-spray boom calibra..." → full text in the tree: "Pre-spray boom calibration check"). This means the tree is more reliable for text verification than screenshots, which require OCR and may show truncated strings.

**How to dump the tree in common environments:**

| Environment | Command | Output |
|---|---|---|
| Android AVD | `uiautomator dump /sdcard/ui_dump.xml` | XML with `text="..."` attributes |
| Linux/GTK (AT-SPI) | `python3 -c "import pyatspi; ..."` or `accerciser` | Tree object / XML |
| Windows (UIA) | `inspect.exe` export, or PowerShell UIA API | XML or structured text |
| Electron/web | `chromium --dump-dom` or DevTools accessibility tree | JSON / HTML |

**The standard verification pattern (Android example):**

In `export_result.sh`:
```sh
#!/system/bin/sh
# Navigate back to the list view before dumping
input keyevent KEYCODE_BACK; sleep 1
input keyevent KEYCODE_BACK; sleep 1
# Dump the accessibility tree to a file the host can copy
uiautomator dump /sdcard/ui_dump_mytask.xml 2>/dev/null
```

In `verifier.py`:
```python
import os, tempfile, logging
logger = logging.getLogger(__name__)

REQUIRED_ITEMS = [
    "First expected list entry",
    "Second expected list entry",
    "Third expected list entry",
]

def _extract_all_text(xml_path):
    """Extract all text="..." attribute values from an Android UI hierarchy XML."""
    try:
        with open(xml_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        texts = []
        idx = 0
        while True:
            start = content.find('text="', idx)
            if start == -1:
                break
            start += 6
            end = content.find('"', start)
            if end == -1:
                break
            val = content[start:end].strip()
            if val:
                texts.append(val.lower())
            idx = end + 1
        return ' ||| '.join(texts)
    except Exception as e:
        logger.error(f"Failed to parse UI XML: {e}")
        return ''

def _item_present(all_text, item_name):
    """Check for item name (full or first 20 chars for truncation tolerance)."""
    name_lower = item_name.lower()
    if name_lower in all_text:
        return True
    prefix = name_lower[:20]
    if len(prefix) >= 10 and prefix in all_text:
        return True
    return False

def verify_mytask(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    tmp.close()
    try:
        copy_from_env('/sdcard/ui_dump_mytask.xml', tmp.name)
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0, "feedback": f"No UI dump: {e}"}

    all_text = _extract_all_text(tmp.name)
    os.unlink(tmp.name)

    score = 0
    feedback = []
    for item in REQUIRED_ITEMS:
        if _item_present(all_text, item):
            score += 20
            feedback.append(f"FOUND: '{item}'")
        else:
            feedback.append(f"MISSING: '{item}'")
    return {"passed": score >= 80, "score": score, "feedback": " | ".join(feedback)}
```

**The critical false-positive pitfall — app chrome text**: The accessibility tree contains ALL text on screen, including navigation items, button labels, tab headers, menu entries, and status text that the app always shows regardless of what the agent did. If any of your required item names partially match these static UI strings, the do-nothing test will return a non-zero score.

**How to prevent it**:
1. After designing your required item names, dump the app's UI in its *default/empty state* (before any agent interaction) and grep for substrings of your required names.
2. If any required item name's first 20 characters appear in the default UI dump, make the name more specific.
3. For mock pipeline tests, include a representative sample of the app's chrome text in your test XML to confirm zero false positives.

```python
# In test_new_tasks_pipeline.py — always include app chrome in mock XMLs
def _make_xml(item_names=()):
    """Build minimal Android UI dump with standard app chrome + given item names."""
    chrome = ["Tasks", "Sync", "Settings", "Activity", "Harvest", "Input", "Done"]
    nodes = [f'<node text="{c}" />' for c in chrome]
    nodes += [f'<node text="{n}" />' for n in item_names]
    return f'<?xml version="1.0"?>\n<hierarchy>\n' + "\n".join(nodes) + '\n</hierarchy>\n'

# Test that app chrome alone scores 0
r_chrome = _run(TASK, FN, _make_xml([]))   # no item names, only chrome
assert r_chrome["score"] == 0, "App chrome caused false positive"
```

**The 20-character prefix check — when to use it**: On devices with small screens or narrow list views, long text strings are displayed truncated (e.g., with ellipsis). Some accessibility APIs report the displayed (truncated) string rather than the full string. To make the verifier robust to both behaviors, check both the full string AND its first 20 characters. Only use the prefix check when `len(prefix) >= 10` (short prefixes are too likely to match unrelated text).

**Mock-testing accessibility tree verifiers** (no VM required): Because the verifier only reads an XML file via `copy_from_env`, you can test it entirely offline. Write the full pipeline test (`test_new_tasks_pipeline.py`) before running on a real device:

```python
# do-nothing: no XML on device → copy_from_env raises → score=0
# partial: XML with 2/5 item names → score=40
# full: XML with 5/5 item names → score=100, passed=True
# wrong-target: XML with item names from a *different* task → score=0
```

**When NOT to use this pattern**: If the app writes its state to a file (SQLite, JSON, XML config) or exposes an API, use those instead. The accessibility tree is a last resort when no other structured output exists. It is also fragile if the app changes its UI layout across versions — keyword matching may fail if the app renames navigation items that you inadvertently depended on.

**Rule**: For pure-GUI tasks with no file or database output, dump the accessibility tree in `export_result.sh` and parse `text="..."` attributes in the verifier. Make required item names specific enough (≥ 15 distinct characters) that they cannot accidentally appear in static app chrome. Always include app chrome in mock pipeline tests to confirm zero false positives in the do-nothing scenario.

---

## Lesson 92: Offline Mock Testing for JSON-Based Verifiers Before Any VM Boots

**The problem this solves**: Every VM boot costs 30–90 minutes. Running five test scenarios (do-nothing, partial ×2, wrong-target, full) against a real VM for every task you write burns hours. And the thing you actually want to confirm — that the verifier's *scoring logic* is correct — does not require a real VM at all. The verifier only interacts with the VM through one function: `copy_from_env`. Replace that function with a mock that writes a pre-crafted payload to disk, and you can exercise every code path in the verifier locally in seconds.

**This pattern applies whenever**: the verifier reads a JSON result file from the VM (the most common pattern: `export_result.sh` or `export_result.ps1` writes a result JSON, verifier copies it with `copy_from_env`).

**How to implement the mock**:

```python
import json, os, tempfile

def make_mock_copy_from_env(payload_dict):
    """Returns a copy_from_env replacement that writes payload_dict to dst."""
    def _mock(src, dst):
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump(payload_dict, f)
    return _mock

def run_verifier_offline(verify_fn, task_info, payload_dict):
    """Run a verifier function with a mocked result JSON payload."""
    mock_env_info = {'copy_from_env': make_mock_copy_from_env(payload_dict)}
    return verify_fn([], mock_env_info, task_info)
```

**The three payloads to always test**:

```python
# 1. Do-nothing: no result file at all (copy_from_env raises)
def mock_missing(src, dst):
    raise FileNotFoundError(f"Source not found: {src}")

result_nothing = verify_fn([], {'copy_from_env': mock_missing}, task_info)
assert result_nothing['score'] == 0 and not result_nothing['passed']

# 2. Partial: some subtasks done, below pass threshold
result_partial = run_verifier_offline(verify_fn, task_info, {
    "subtask_a_done": True,
    "subtask_b_done": False,
    "subtask_c_done": False,
    # ... other fields at baseline / default values
})
assert 0 < result_partial['score'] < PASS_THRESHOLD and not result_partial['passed']

# 3. Wrong target: correct structure but wrong entity
result_wrong = run_verifier_offline(verify_fn, task_info, {
    "target_id": WRONG_ID,  # different entity than the task requires
    "subtask_a_done": True,
    # ...
})
assert result_wrong['score'] == 0 and not result_wrong['passed']
```

**Run these before touching the VM.** If all three pass, you have high confidence in the verifier. Only boot the VM for the do-nothing confirmation (which validates the setup script's state, not the verifier's logic).

**Lesson 91 vs. 92**: Lesson 91 covers this pattern specifically for accessibility-tree XML (Android/GUI-only apps). This lesson covers the general case: any environment where the verifier reads a JSON result file. The mechanics are the same; only the payload differs.

**Rule**: Write and run all three mock test scenarios (do-nothing, partial, wrong-target) offline before your first VM boot. The VM test's only job is to confirm the *setup script* works correctly, not to re-validate verifier scoring logic you already confirmed offline.

---

## Lesson 93: `[gym-anything] exec failed` Is Diagnostic Noise — Check Actual State, Not Exit Codes

**What it looks like**:

```
[gym-anything] Running pre_task hook...
[QemuApptainer] exec failed: At C:\workspace\tasks\my_task\setup_task.ps1:93 char:76
+ ... te-Host "=== my_task setup complete ==="
+
Profiling time for task specific hooks: 2.97s
```

This is alarming on first encounter. It looks like the setup script crashed. **In the vast majority of cases, the setup succeeded** and the non-zero exit code comes from a completely unrelated minor failure:

| Root cause | Why it happens |
|---|---|
| PowerShell `Stop-Transcript` | If the transcript was never started (e.g., `Start-Transcript` was suppressed by `try-catch`), `Stop-Transcript` can exit non-zero even wrapped in `try { } catch { }` |
| `grep` returning 1 in bash | `grep` exits 1 when it finds zero matches — expected in cleanup checks like `grep -c "old_value" file` |
| `ErrorActionPreference = "Stop"` + benign cmdlet | `Stop-Process` on a non-existent PID, `Remove-Item` of an already-absent file, or `Get-Process` returning empty all raise under `Stop` policy |
| `Out-Null` on cmdlets that still set `$LASTEXITCODE` | Some cmdlets propagate the exit code of sub-processes even after piping to `Out-Null` |

**How to diagnose a real failure vs. noise**:

1. **Check the actual state** — did the setup script produce its artifacts? (timestamp file, baseline files, app process running, project directory created)
2. **Check that the do-nothing test still returns score=0** — if the setup is broken in a way that matters, the verifier will show it; `exec failed` alone is not evidence of a broken setup
3. **Read the error message carefully** — if the script printed "=== setup complete ===" as its last line but still exited non-zero, the body succeeded and only the cleanup failed

**How to minimize exit-code noise in your scripts** (without suppressing real errors):

```powershell
# Good: suppress only cleanup failures, not logic failures
try {
    # real setup logic here — let errors propagate
    ...
    Write-Host "=== setup complete ==="
} finally {
    # cleanup that might legitimately fail
    try { Stop-Transcript | Out-Null } catch { }
    $global:LASTEXITCODE = 0  # reset exit code before returning
}
```

```bash
# Good: reset exit code at the very end of bash setup scripts
# so minor cleanup failures don't propagate
echo "=== setup complete ==="
exit 0
```

**Rule**: When you see `exec failed` in the gym-anything logs, do NOT immediately assume the setup is broken. Check that (a) the setup artifacts exist, (b) the application is running, and (c) the do-nothing test returns score=0. Only if those checks fail is the `exec failed` actually meaningful.

---

## Lesson 94: Document-Centric GUI Apps Require an Explicit Save Step in the Task Design

**The pattern this applies to**: Applications where the agent manipulates a *document* — an engineering model, a drawing, a configuration file, a spreadsheet — that lives in a native binary/text format and is only persisted when the user explicitly saves or exports it. Examples: building energy simulators (.inp files), CAD tools (.dwg), drawing tools (.drawio), word processors (.docx), spreadsheet apps.

**Why this is different from database-backed apps**: In a database-backed application (EMR, CRM, ticketing system), the agent's changes are written to a database in real time. The verifier can query that database at any point. In a document-centric application, changes exist only in the application's in-memory state until the user saves. The verifier can only read the on-disk file — it has no access to in-memory state.

**The design implication**: If the task description says "modify X", but doesn't say "save your work", a capable agent might make all the right changes and still score 0 because the saved file on disk was never updated. This is an intentional property (anti-gaming: changes in memory don't count), but task designers must be explicit about it.

**How to handle it in the task description**:

```
# Too vague — agent might not save
"Update the HVAC system efficiency parameters in the building model."

# Correct — explicitly requires save + simulation
"Update the HVAC system efficiency parameters in the building model, save the
 project, and run a full simulation to confirm the changes take effect."
```

**How to handle it in the verifier**:

The verifier must read the *saved* file, not the live app state. This means:
1. The setup script records `task_start_ts` **before** the application is launched
2. The export script reads the saved file's modification time and checks `int(mtime) > task_start`
3. The verifier does the same check — a file that predates the task start gets no credit, even if its values are correct (the agent might have inherited a pre-modified file)

```python
# In verifier: always gate on file modification time
sim_is_new = result.get('sim_file_is_new', False)
if not sim_is_new:
    feedback.append("Document not saved/modified during this task session.")
    # Either give 0 or significantly reduce score
```

**The task start timestamp ordering matters**: Delete any stale output files and record the task start timestamp *before* launching the application. If the application auto-creates files on launch (e.g., creating a new project directory), those files will have an mtime equal to or greater than the timestamp — but so will legitimately agent-modified files. To distinguish: record the timestamp *before* the app touches anything, then in the export script check whether the file was modified *after* the agent had time to act (not just after the app launched).

**Corollary — the "simulate to confirm" requirement**: For simulation tools, requiring the agent to run a simulation (not just save the model) provides a second, independent confirmation that changes were actually applied. The simulation output file (.SIM, .log, .out) is produced only when the simulation runs, and its mtime confirms the agent actually triggered computation — not just edited and closed the file.

---

## Lesson 95: SSH PTY Backtick Substitution in exec_capture — Use Base64 for Complex Commands

**The Problem**: The gym-anything framework's `exec_capture` function typically runs commands via SSH with PTY flags (`-t -t`). This allocates a pseudo-terminal on the remote side, which means the remote bash shell is running in *interactive* mode. In this mode, backtick characters (`` ` ``) anywhere in the command string — including inside SQL queries — are interpreted as **command substitution**, not as literal characters.

This is particularly dangerous in MySQL queries that use backtick-escaped reserved-word column names. For example, a column named `index` (a SQL reserved word) must be quoted as `` `index` `` in MySQL. But when this SQL is embedded in a shell command and passed via SSH PTY, bash substitutes `` `index` `` with the output of running a command named `index`, producing:

```
bash: index: command not found
```

This error message appears in stdout (because PTY merges stderr into stdout), making `result.strip()` truthy. If the verifier checks `if result:` to decide whether a record exists, it will score a false positive on the do-nothing test.

**Why it's hard to spot**: The do-nothing test passes (score=0) because the verifier returns False when exec is None during development, but once exec_capture is wired up, the PTY-mangled output silently produces phantom truthy results. The score jumps from 0 to a non-zero value without any code change.

**The Fix**: Base64-encode the entire SQL or complex command, then decode it on the remote side:

```python
import base64

def exec_sql(exec_capture, sql):
    """Run SQL via exec_capture without shell-quoting issues."""
    sql_b64 = base64.b64encode(sql.encode('utf-8')).decode('ascii')
    # Base64 output contains only [A-Za-z0-9+/=] — no shell-special chars
    result = exec_capture(
        f'echo "{sql_b64}" | base64 -d | '
        f'docker exec -i db-container mysql -u user -ppass dbname 2>&1'
    )
    return result
```

**Why base64 works**: The base64 alphabet (`A-Z`, `a-z`, `0-9`, `+`, `/`, `=`) contains no backticks, single quotes, double quotes, dollar signs, or semicolons. The encoded string passes through the PTY shell unchanged. The `base64 -d` command on the remote side reconstructs the original SQL exactly before it reaches the database.

**Bonus**: This same technique eliminates ALL shell-quoting issues — no need to escape single quotes in SQL strings, no issues with embedded newlines, no problems with apostrophes in data values.

**Narrower alternative (if base64 is unavailable)**: Escape the backticks with a backslash in the Python string: `` `index` `` → `\\`index\\`` in the Python string literal, which produces `\`index\`` in the actual string value, which the shell interprets as an escaped (non-special) backtick. Use this only when base64 is unavailable and the SQL is simple enough that escaping every special character is tractable.

**Applies to**: Any environment where `exec_capture` uses SSH with PTY (`-t -t`) and the verifier or test script passes complex SQL, shell scripts, or other strings with backtick-special characters. Docker-compose environments with MySQL/MariaDB databases are the most common case.

---

## Lesson 96: Wrong env_info Key for the Exec Function Silently Passes Do-Nothing — But Breaks All Completion Tests

**The Problem**: Verifiers retrieve the execution function from `env_info` by key name:

```python
exec_in_env = env_info.get('exec_in_env')
if not exec_in_env:
    return {"passed": False, "score": 0, "feedback": "exec not available"}
```

If the framework actually provides the function under a *different* key (e.g., `exec_capture` instead of `exec_in_env`), then `exec_in_env` is `None` and the verifier always returns `{"passed": False, "score": 0}`.

**Why this looks correct at first**: Score=0, passed=False is the *correct* result for the do-nothing test. So the do-nothing validation passes. The bug is invisible unless you also run a partial or full completion test — which requires a live VM.

**The consequence**: Every single verifier in the environment is broken. The do-nothing test passes (score=0 ✓) for the *wrong* reason — not because the agent did nothing, but because the exec lookup always fails. A fully-completed task would also score 0.

**Detection**: If all tasks in a new environment consistently score exactly 0 for both do-nothing AND partial injection tests (where injected DB records should produce non-zero scores), the exec function lookup is the first thing to check.

**The Fix**: Before writing verifiers for a new environment, check the actual key names available in `env_info` by looking at:

1. **A working verifier in the same environment** (if any real ones exist — not stubs):
   ```bash
   grep -r "env_info.get(" benchmarks/cua_world/environments/<env>/tasks/*/verifier.py | head -5
   ```

2. **A working verifier in any other environment** that uses the same runner type (QEMU, Android AVD, etc.):
   ```bash
   grep -rh "env_info.get('exec" benchmarks/cua_world/environments/*/tasks/*/verifier.py | sort -u
   ```

3. **The framework runner source** (`src/gym_anything/runtime/runners/*.py`): look for what keys are set in the env_info dict the runner passes to verifiers.

**Common key names by runner type** (verify against the actual codebase — these may change):
- QEMU/Linux environments: `exec_capture`, `copy_from_env`
- Android AVD environments: `exec_capture`, `copy_from_env`
- Windows (QEMU): `exec_capture`, `copy_from_env`

**The defensive pattern**: Add a fallback that tries multiple known key names, and emit a clear error if none work:

```python
exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
if not exec_in_env:
    return {
        "passed": False,
        "score": 0,
        "feedback": "ERROR: No exec function found in env_info. "
                    "Check key name against framework runner."
    }
```

**Applies to**: Every verifier in every new environment. This is a framework-coupling issue: the verifier must know the exact key the runner uses. When in doubt, use the fallback pattern above rather than assuming a single key name.

**Rule**: For any task involving a document-centric application, explicitly state in the task description that the agent must save (and ideally export or run/compile) the modified document. Gate verification on file mtime > task_start. Require a derivative artifact (simulation result, rendered output, compiled binary) as a second independent confirmation that changes were actually applied, not just made in memory.

---

## Lesson 97: Open-Ended Research/Writing Tasks Need an Entity-Specific Content Gate

**The Problem**: Lessons 86/87 address wrong-target gates for pipeline and database tasks (wrong patient ID, wrong node configured). But for **open-ended research or writing tasks** — where the agent freely browses, downloads data, and writes a report or notes file — the structural indicators can all look correct even when the agent researched the wrong entity.

**Example**: A task asks a journalist to research **Department of Defense (DOD) spending** on USASpending.gov and write a research notes file. A wrong-target agent researches **Health and Human Services (HHS)** spending instead. Both agents:
- Visit USASpending.gov ✓ (visit count non-zero)
- Download a CSV ✓ (file exists)
- Write a notes file ✓ (file fresh, non-empty, contains dollar amounts and URLs)

Without an entity-specific gate, the wrong-target agent earns 58/100 — nearly passing — because all structural criteria are satisfied. The ONLY difference is which agency appears in the notes text.

**The Fix**: Export an entity-specific boolean field from the output file and gate scoring on it.

In the export script:
```bash
# Check for entity-specific keywords in the output file
python3 << PYEOF
import re, json
content = open("/home/ga/Documents/research_notes.txt").read()
# Use entity-specific keywords that only appear if the agent researched the right entity
entity_pattern = re.compile(
    r'\bdod\b|department\s+of\s+defense|defense\s+contract|pentagon|darpa|army|navy',
    re.IGNORECASE
)
result["has_entity_content"] = bool(entity_pattern.search(content))
PYEOF
```

In the verifier, gate the notes-content criterion on this flag:
```python
has_entity_content = bool(data.get("has_entity_content", False))
has_dollar_amount  = bool(data.get("has_dollar_amount", False))

if has_entity_content and has_dollar_amount:
    content_score += 10   # Full credit: right entity + quantified finding
elif has_entity_content:
    content_score += 5    # Partial: right entity, no dollar amount
elif has_dollar_amount:
    content_score += 2    # Minimal: dollar amounts present but wrong entity
```

**When this pattern applies**: Any task that:
1. Requires the agent to produce a **free-text output** (notes file, report, analysis document)
2. The task specifies a **named target entity** (specific company, agency, pathogen, person, product, country, etc.)
3. A wrong-target agent could produce structurally identical output (same file, same size, same numerical content) about a different similar entity

**What makes a good entity keyword set**: Choose terms that are:
- Highly specific to the target entity (not shared by similar entities)
- Likely to appear naturally in a correct research document
- Rare enough that they won't appear in general-purpose text

**Rule**: For any task that produces a free-text output about a specific named entity, add a `has_<entity>_content` boolean field in the export script, and require it to be `True` to earn full credit on the content criterion. This closes the structural-equivalence loophole where right-workflow + wrong-entity ≈ passing score.

---

## Lesson 98: Mock Test Data Field Names Must Exactly Match Export Script Keys

**The Problem**: When writing offline mock tests (test data dicts passed directly to verifiers without a VM), every key in the test dict must exactly match the corresponding key produced by the export script. A mismatch silently falls back to `result.get('wrong_key', default)` — which returns the default value (0, False, [], etc.) — and produces a misleading mock test score that hides real verifier behavior.

**Example**: The export script writes:
```python
result["sandworm_subfolder"] = True   # boolean
result["sandworm_bookmarks"] = 5      # int
```
But the mock test dict uses:
```python
"sandworm_subfolder_exists": True,    # WRONG name
"sandworm_subfolder_bookmarks": 5,    # WRONG name
```
The verifier calls `result.get("sandworm_subfolder", False)` → gets `False` (key not found). The mock test scores 0 for that criterion even though the "full completion" test data intended to award full points.

**Why it's hard to notice**: The do-nothing mock test still passes correctly (all fields default to 0/False). The wrong-target mock test may also still fail (score too low). Only the partial and full mock tests reveal the problem — and only if you inspect the score breakdown, not just whether `passed` is True.

**The Fix**: Before writing any mock test data, open the export script and copy the exact key names from the `result["key"] = value` assignments. Do not guess, infer, or paraphrase:

```bash
# Get all result keys from the export script
grep 'result\["' benchmarks/cua_world/environments/<env>/tasks/<task>/export_result.sh | sed 's/.*result\["\([^"]*\)".*/\1/' | sort -u
```

Then build your mock test dict from this list, not from the verifier's comments or criterion descriptions.

**Systematic validation**: After creating mock test data, run the verifier once with your "full completion" payload and check that every criterion fires at its maximum score. If any criterion shows 0 in the full-completion result, a field name mismatch is the most likely cause.

**Rule**: Always derive mock test data keys directly from the export script source, not from memory or verifier documentation. One mismatched key silently zeroes an entire criterion and invalidates the mock test as a correctness check.

---

## Lesson 99: Use the Application's ORM Mapping Files to Discover the Exact Database Schema Without a Live VM

**The Problem**: Lesson 61 covers discovering the exact schema by querying the live database. This requires the VM to be booted and the database to be accessible — which is not always possible during initial task design. Writing SQL against guessed table/column names produces silent failures (empty results, wrong export values) that are only revealed after full VM tests.

**The Fix — ORM mapping files as an authoritative schema source**: Most database-backed applications define their schema via an Object-Relational Mapper (ORM). The ORM mapping files are the **ground truth** for the exact table name, column name, and data type that the application actually uses. They are faster to consult than booting a VM and are available from the application's public source repository.

**For Java / Hibernate (`.hbm.xml` files)**:
```xml
<!-- MenuItem.hbm.xml -->
<class name="MenuItem" table="MENU_ITEM">
    <id name="id" column="ID" type="integer"/>
    <property name="name" column="NAME"/>
    <property name="price" column="PRICE" type="big_decimal"/>
    <many-to-one name="menuGroup" column="GROUP_ID" class="MenuGroup"/>
    <many-to-one name="tax" column="TAX_ID" class="Tax"/>
</class>
```
This tells you the table is `MENU_ITEM` (not `MENUITEM`), the FK to the group is column `GROUP_ID` (not `MENUGROUP_ID`), and to get the category you must join through the group: `MENU_ITEM → MENU_GROUP (GROUP_ID) → MENU_CATEGORY (CATEGORY_ID)`.

**For Django (Python `models.py`)**:
```python
class MenuItem(models.Model):
    class Meta:
        db_table = "menu_item"   # exact table name
    name = models.CharField(max_length=255)
    price = models.DecimalField(db_column="PRICE")  # exact column name
    group = models.ForeignKey("MenuGroup", db_column="GROUP_ID")
```

**For Ruby on Rails (`db/schema.rb`)**:
```ruby
create_table "menu_items", force: :cascade do |t|
    t.string  "name"
    t.decimal "price"
    t.integer "group_id"
end
```

**How to find these files**: Search the application's GitHub/GitLab/Bitbucket repository:
- Hibernate: `*.hbm.xml` or `@Table(name=...)` annotations in `*.java`
- Django: `class Meta: db_table =` in `models.py`
- Rails: `db/schema.rb` or migration files
- Sequelize (Node.js): `tableName:` in model definitions
- SQLAlchemy (Python): `__tablename__ =` in model classes

**What to verify from ORM files**:
1. Exact table names (case-sensitive on Linux, often uppercase for Java/Derby)
2. Exact column names (especially FKs — `GROUP_ID` vs `MENUGROUP_ID` vs `CATEGORY_ID`)
3. Join paths — many fields that look like direct attributes are actually FK traversals requiring a JOIN
4. Column names for non-obvious fields (e.g., `RATE` vs `PERCENTAGE_RATE` for a tax rate column)

**Important caveat**: ORM files reflect the *source code version*, which may differ from the installed/deployed version. Always confirm against the live DB when possible, but ORM files eliminate 95% of schema guessing and drastically reduce the number of live-VM iterations needed.

**Rule**: Before writing any SQL for a database-backed task, search the application's source repository for ORM mapping files. Read the table name and all column names directly from these files. Only fall back to guessing if the application has no ORM (pure JDBC/ODBC) and no queryable live DB. Document the discovered schema in a comment at the top of each export script.

---

## Lesson 100: Pre-Existing Database Records With Task-Required Names Cause Partial-Credit False Positives

**The Problem**: Many tasks require the agent to create records in a database with specific names (modifier groups, tax categories, menu items, product types, etc.). A natural verifier pattern awards partial credit for individual child records that exist with the required names — but does *not* require the parent record (group, category, folder) to also exist. In the do-nothing test, the initial database state may already contain records whose names happen to match some required names, silently triggering partial credit.

**Concrete example**: A task requires the agent to:
1. Create a modifier group named "PIZZA TOPPINGS"
2. Create modifiers named EXTRA CHEESE, MUSHROOMS, PEPPERONI, SAUSAGE, etc. inside it

The initial database already contains modifiers named SAUSAGE, BACON, and FRIED EGG (installed by the application as defaults). A verifier that awards 2 pts per required modifier found by name — with a fallback path that runs even when "PIZZA TOPPINGS" group doesn't exist — will score 6 pts in the do-nothing test from these pre-existing records.

**This is different from Lesson 89 (navigation-menu false positives)**: Here the false positive comes from the actual data in the database, not from UI element labels. The records are genuine data rows that legitimately share names with task requirements.

**The Fix — Gate child-record credit on parent-record existence**:

```python
# BAD: partial credit for individual records independent of parent existence
pizza_group = get_group("PIZZA TOPPINGS")
if pizza_group:
    for req in PIZZA_MODIFIERS:
        if modifier_exists_in_group(req["name"], pizza_group["id"]):
            score += 4   # full credit
        else:
            score += 0
else:
    # WRONG: fallback partial credit — matches pre-existing records by name alone
    for req in PIZZA_MODIFIERS:
        if any_modifier_exists_with_name(req["name"]):  # ignores group
            score += 2   # false positive from pre-existing data
        else:
            score += 0
```

```python
# GOOD: no partial credit when parent does not exist
pizza_group = get_group("PIZZA TOPPINGS")
if pizza_group:
    for req in PIZZA_MODIFIERS:
        if modifier_exists_in_group(req["name"], pizza_group["id"]):
            score += 4
        else:
            score += 0
else:
    # No partial credit — pre-existing records of same name are irrelevant
    # without the required parent group
    for req in PIZZA_MODIFIERS:
        score += 0   # or simply skip awarding anything
```

**How to detect this problem**: After running the do-nothing offline test and confirming score=0, check the debug output for which criteria fired. If any child-record criteria scored > 0 when no parent was created, you have a pre-existing-data false positive.

**How to audit initial DB state before designing the verifier**: Before finalizing required record names, query the initial DB for any existing records that share those names:

```sql
-- Derby / SQL: check for pre-existing modifiers matching task requirements
SELECT NAME FROM MENU_MODIFIER WHERE NAME IN ('SAUSAGE', 'BACON', 'FRIED EGG', 'PEPPERONI');

-- MySQL: check for pre-existing categories
SELECT NAME FROM categories WHERE NAME IN ('BEVERAGES', 'APPETIZERS', 'DESSERTS');
```

If any match, either:
1. Remove those names from the task requirements (choose names not in the initial state), or
2. Require exact group/category membership in the verifier (no name-only fallback)

**Broader principle**: Any verifier criterion that matches records by name alone (without requiring structural context like group, category, folder, parent) must be validated against the initial DB state to confirm no records pre-exist with those exact names.

**Rule**: When a task requires hierarchical records (parent group + child items), the verifier must not award points for child items if the parent does not exist — even as partial credit. Name-only matching of child records is always vulnerable to pre-existing data collisions in the initial environment state.

---

## Lesson 101: New-Entity Creation Tasks Require an Identity Gate in the Verifier

**Problem**: Tasks that require *creating* a new entity that does not yet exist at task start (e.g., register a new patient, create a new user, add a new account) have a silent false-positive vulnerability: if the verifier only checks whether *some* new entity exists with the correct attributes, it will award full credit to an agent that created the WRONG entity with the correct data attached to it.

**Concrete example**: A task says "Register new patient Helena Vasquez and add Type 2 Diabetes diagnosis." The setup script deletes any pre-existing Helena Vasquez record. The export script finds the first new patient after the baseline count and returns her diagnoses. Without an identity gate, if an agent registers "John Smith" but correctly adds ICD 250.00 and all other required clinical data, the verifier scores 87/100 — passing — because it only checked the presence of the correct diagnoses, not which patient they belong to.

The wrong-target test that reveals this: create an offline mock where `patient_found=True, fname="John", lname="Smith"` but all downstream data fields are perfect. If the verifier returns passed=True, the identity gate is missing.

**This is distinct from Lesson 100 (pre-existing records)**: Lesson 100 covers false positives from records that already exist in the initial DB state. This lesson covers tasks where the *agent* creates the wrong new entity from scratch and correctly populates its data.

**Fix — Add a named identity gate immediately after the entity-existence gate**:

```python
# Gate 1: Entity must exist
if not result.get("entity_found"):
    return {"passed": False, "score": 0, "feedback": "Entity not created"}

# Gate 2: It must be the RIGHT entity — check identity before awarding any points
entity = result.get("entity_data", {})
fname_ok = EXPECTED_FNAME in entity.get("fname", "").lower()
lname_ok = EXPECTED_LNAME in entity.get("lname", "").lower()
if not fname_ok or not lname_ok:
    got = f"{entity.get('fname', '')} {entity.get('lname', '')}".strip()
    return {"passed": False, "score": 0,
            "feedback": f"Wrong entity created — expected {EXPECTED_NAME}, got '{got}' (score=0)"}
```

For non-person entities (username, organization, document name), use the appropriate unique identifier. The key principle: no downstream criterion should receive any points until the correct identity is confirmed.

**Export script requirement**: The export script must query and include the entity's identity fields (name, username, email, role, etc.) in the result JSON alongside the downstream data. Without identity fields in the JSON, the verifier cannot perform the identity check.

**Rule**: Any task that requires creating a brand-new entity must: (1) export the entity's identity fields in the result JSON, (2) add a named identity gate as the second gate (after existence check) in the verifier, and (3) include a wrong-target offline test where a different entity is created with otherwise correct downstream data — confirm this returns score=0.

---

## Lesson N+1: Manually Trace Partial Scores When Verifier Criteria Interact Through Shared JSON Fields

**Problem**: When two or more verifier criteria both read the same JSON result field, setting that field to a "sufficient" value in a partial test scenario can silently satisfy multiple criteria at once — making the partial scenario exceed the pass threshold unexpectedly.

**Concrete example**: Consider a backlog triage verifier with two criteria:
- Criterion 1 (25 pts): awards full points if `tagged_count >= 4`
- Criterion 2 (20 pts): awards full points if `tagged_assigned_to_admin >= tagged_count`

If the partial test data sets `tagged_count=4` and `tagged_assigned_to_admin=4`, both criteria award their full points (25+20=45). Add a few other partial criteria and the total easily exceeds 60 — causing `assert partial['score'] < 60` to fail in the pipeline test.

The issue is invisible when designing criteria in isolation. It only surfaces when you trace all criteria simultaneously with the same data dict.

**Solution — Manually trace the full scoring path before writing the pipeline test assertion**:

1. Write out every criterion's scoring branch as a table:
   ```
   Field values in partial dict → Branch taken → Points awarded
   tagged_count=4              → "all 4" branch → 25 pts
   tagged_assigned_to_admin=4  → ">= tagged_count" branch → 20 pts
   notes_on_unresponded=0      → "none" branch → 0 pts
   reopened_count=0            → "none" branch → 0 pts
   target_replied=False        → "no reply" branch → 0 pts
   target_assigned=False       → "not assigned" branch → 0 pts
   TOTAL: 45 pts → BELOW 60 ✓
   ```

2. Only after confirming the total is below threshold, write `assert result['score'] < threshold`.

3. If the total accidentally equals or exceeds threshold, reduce one field in the partial dict (e.g., change `tagged_count=2` so criterion 2 also reduces) until the total falls below.

**Rule**: Before finalizing partial test data in any pipeline test, always sum the expected criterion scores manually in a comment block in the test function. Never assume a "halfway" set of field values will stay below threshold — trace every branch, including criteria that interact through shared fields.

**Broader principle**: This is especially common in task verifiers that have "dependency" criteria (e.g., "count of X assigned to Y" depends on both the count-of-X and the assignment status). Treat any criterion whose point award depends on a field that another criterion also reads as a potential interaction point, and trace those criteria together.

---

### 80. Published Technical Standards Are a Third Category of "Real Data"

**The Problem**: Principle 2 (Real Data — No Exceptions) covers two categories of real data: (a) database/file records already in the environment, and (b) downloadable real datasets from named public sources. But for **engineering, manufacturing, design, electronics, and construction tasks**, the natural "data" is neither a database nor a downloadable file — it is a published technical standard. Where does NEMA 17's 31mm bolt hole pattern come from? The NEMA ICS 16 standard document. Is writing that value into a `setup_task.sh` spec reference file "synthetic data generation"? No — it is transcription from a real, named, citable document.

**The Rule**: For design and engineering tasks, writing a spec reference file (plain text, embedded in setup_task.sh via heredoc) with exact values from published technical standards is **valid real data** and is **not** a synthetic data violation, provided:
1. The values are copied exactly from the named standard — **not approximated, not randomly varied**
2. The source is cited in `README.md` (standard name, issuing body, and clause/section if applicable)
3. The spec file is written to the VM during `setup_task.sh` so the agent can read it as a real constraint to design to

**Examples of valid standards sources**:
- NEMA ICS 16: stepper motor dimensions (bolt hole patterns, collar diameters)
- ANSI/EIA-310-E: 19-inch rack dimensions (1U height, mounting hole spacing)
- AISC Steel Construction Manual: bolt gauge/pitch, clearance hole sizes
- ISO 2768: general tolerances for machined parts
- IEC 60950: IT equipment mounting and connector standards
- ASTM A36/A572: structural steel grades

**What this is NOT**: Generating fake values ("let's say the motor has 28mm bolt pitch and a 19mm collar") — that IS a synthetic data violation even if it looks like real standard data.

**When to use this pattern**: Only for tasks where the agent must create something (CAD model, fabrication drawing, electrical layout) that conforms to a real-world standard. The spec file acts the same role as a database record in a web-app task — it gives the agent a real set of constraints to work with.

**Implementation**:
```bash
# In setup_task.sh: write real standard values from named publication
cat > /home/ga/Documents/NEMA17_specifications.txt << 'SPECEOF'
NEMA 17 Stepper Motor Standard Dimensions (NEMA ICS 16)
  Motor body:      42.3mm x 42.3mm square face
  Mounting holes:  4x M3, at 31mm x 31mm square pattern (center-to-center)
  Shaft collar:    22mm diameter boss
SPECEOF
```

**In README.md**: "Real data source: NEMA ICS 16 standard (National Electrical Manufacturers Association). Motor body 42.3mm, bolt pattern 31mm×31mm, collar 22mm — exact published values, no approximation."

---

### 81. Offline Partial Tests for Pattern 8 Verifiers Require Minimal In-Memory File Fixtures

**The Problem**: Lesson 20 explains how to test verifiers offline by mocking `copy_from_env` with result JSON. But this approach breaks when the verifier uses **Pattern 8 (Independent File Re-Analysis)** — i.e., it also independently copies the agent's output file and re-parses it for feature content. With a JSON-only mock, the file copy raises `FileNotFoundError` and the verifier skips all structure-based scoring, making partial tests unable to test those criteria at all.

**Concrete example**: A verifier for a FreeCAD task does two things:
1. Reads result JSON (for mtime, export file sizes, existence flags)
2. Copies `motor_mount.FCStd` and parses `Document.xml` to check for `PartDesign::Hole`, `Spreadsheet::Sheet`, etc.

A JSON-only mock scores 0 on all structure-based criteria — you can't test "agent created Body+Pad but no holes → 30 pts, passed=False."

**The Fix**: Extend the mock `copy_from_env` to also serve **minimal valid file fixtures** constructed in-memory for the output file path:

```python
import io, zipfile, json

def make_minimal_fcstd(obj_types: list, aliases: list = None) -> bytes:
    """Build a minimal valid FCStd (ZIP+Document.xml) with given feature types."""
    objects_xml = "\n".join(
        f'    <Object type="{t}" name="{t.split("::")[-1]}{i}"/>'
        for i, t in enumerate(obj_types)
    )
    cells_xml = ""
    if aliases and 'Spreadsheet::Sheet' in obj_types:
        cells_xml = "\n".join(
            f'  <Cell alias="{a}" address="A{i+1}" content="10"/>'
            for i, a in enumerate(aliases)
        )
        cells_xml = f"\n<ObjectData><Object name='Spreadsheet0'><Properties><Property name='cells'><Cells>{cells_xml}</Cells></Property></Properties></Object></ObjectData>"
    doc_xml = f"<?xml version='1.0'?>\n<Document>\n  <Objects>\n{objects_xml}\n  </Objects>{cells_xml}\n</Document>"
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as z:
        z.writestr('Document.xml', doc_xml)
        z.writestr('GuiDocument.xml', '<GuiDocument/>')
    return buf.getvalue()

def make_env_info_with_fcstd(json_data: dict, fcstd_bytes: bytes):
    def copy_from_env(src, dst):
        if src.endswith('.json'):
            with open(dst, 'w') as f:
                json.dump(json_data, f)
        elif src.endswith('.FCStd') and fcstd_bytes is not None:
            with open(dst, 'wb') as f:
                f.write(fcstd_bytes)
        else:
            raise FileNotFoundError(src)
    return {'copy_from_env': copy_from_env}

# Now test "Body+Pad but no holes" partial scenario:
task_start = 1700000000
fcstd_bytes = make_minimal_fcstd(['PartDesign::Body', 'PartDesign::Pad'])
json_data = {"task_start": task_start, "fcstd_exists": True,
             "fcstd_mtime": task_start + 60, "fcstd_size": len(fcstd_bytes), "stl_exists": False, "stl_size": 0}
result = verify_motor_mount([], make_env_info_with_fcstd(json_data, fcstd_bytes), {})
assert 20 <= result['score'] <= 40 and not result['passed']  # ~30 pts expected
```

**What formats this applies to**: Any application format that is a ZIP containing XML:
- FreeCAD `.FCStd` → `Document.xml` with `<Objects>` list
- draw.io `.drawio` → XML (or ZIP for multi-page)
- LibreOffice `.ods`/`.xlsx` → content.xml / xl/workbook.xml
- DOCX/PPTX → word/document.xml / ppt/presentation.xml
- eQUEST `.inp` → BDL text blocks (not ZIP, but still constructible)

**Key validation step**: Before using a minimal fixture in tests, verify it parses correctly with the *same* parse function used in the verifier:
```python
obj_types, root = _parse_fcstd_from_bytes(make_minimal_fcstd(['PartDesign::Body']))
assert 'PartDesign::Body' in obj_types  # fixture is valid
```

**What this is NOT**: These in-memory fixtures are test-only scaffolding for verifier validation. They never appear in `setup_task.sh` or any agent-facing file. This is distinct from providing real data to agents.

---

### 82. env.reset() Returns the Start-State Screenshot in the Observation Dict

**The Problem**: Phase 4 requires saving a screenshot of the start state to `evidence_docs/` as proof that the environment loaded correctly. Task creators often try `env.save_screenshot()` or `env._get_screenshot()` — these methods don't exist. The screenshot is already captured automatically by `env.reset()` as the first frame.

**The Fix**: The observation from `env.reset()` is a dict with the screenshot path:
```python
obs = env.reset(seed=42, use_cache=True, use_savevm=True)
# obs = {'screen': {'path': 'artifacts/episode_YYYYMMDD_.../frame_00000.png',
#                    'resolution': [1920, 1080]}}
```

Copy it to evidence_docs:
```python
import shutil, os

def save_start_screenshot(obs, task_name: str, evidence_dir: str):
    """Copy the start-state screenshot from env.reset() obs to evidence_docs/."""
    if isinstance(obs, dict) and 'screen' in obs:
        src = obs['screen']['path']
        # path may be relative to the repo root
        if not os.path.isabs(src):
            src = os.path.join(os.getcwd(), src)
        if os.path.isfile(src):
            dest = os.path.join(evidence_dir, f'{task_name}_start_screenshot.png')
            shutil.copy(src, dest)
            print(f"Start screenshot saved: {dest}")
```

**When the screenshot is taken**: The framework captures it right after all hooks (post_start + pre_task) have run, so it shows the actual starting state the agent sees — FreeCAD with the source file loaded, browser on the starting page, etc.

**Applies to**: All environments (Linux/GNOME, Windows 11, Android AVD). The `obs['screen']['path']` pattern is consistent across platforms.

**Rule**: Always collect the start screenshot in Phase 4 by reading `obs['screen']['path']`. This is the single most useful piece of evidence — it proves the task setup worked and shows what the agent's first frame looks like.

---

## Lesson 102: `from_config()` task_id Must Be the Directory Name, NOT the `task.json` id Field

**The Problem**: `task.json` contains `"id": "task_name@1"` (with a `@version` suffix). It is tempting to pass this value directly to `from_config()`:

```python
env = from_config("benchmarks/cua_world/environments/my_env", task_id="task_name@1")  # WRONG
```

This raises `FileNotFoundError: Task 'task_name@1' not found under benchmarks/cua_world/environments/my_env/tasks` because `from_config()` resolves the task by looking for a **directory** named exactly as the `task_id` argument. No directory is ever named `task_name@1` — the directory is always named `task_name` (without the version suffix).

**The Fix**: Always pass the bare directory name:

```python
env = from_config("benchmarks/cua_world/environments/my_env", task_id="task_name")  # CORRECT
```

**Where this matters**: Every Phase 4 test script that calls `from_config()` in a loop:

```python
# WRONG — will raise FileNotFoundError for every task
for task_id in ["task_a@1", "task_b@1", "task_c@1"]:
    env = from_config(BASE_DIR, task_id=task_id)

# CORRECT — strip the @version suffix
for task_id in ["task_a@1", "task_b@1", "task_c@1"]:
    task_name = task_id.split("@")[0]
    env = from_config(BASE_DIR, task_id=task_name)
```

**Root cause**: The `"id"` field in `task.json` identifies the task in the registry (env_id@version), but `from_config()` discovers tasks by scanning `tasks/<task_name>/task.json` — the directory name is the lookup key, not the `"id"` field value.

**Rule**: In all Phase 4 and live test scripts, use the directory name (without `@version`) as `task_id`. If you have a list of task IDs with version suffixes (as some `task.json` `id` fields carry), strip the suffix with `.split("@")[0]` before passing to `from_config()`.

---

## Lesson 103: Default Application Configuration Satisfying Verifier Criteria Produces Non-Zero Do-Nothing Scores

**The Problem**: When a task requires the agent to *configure* a feature or service (e.g., "enable WFS and set a max features limit"), the application's **factory-default state** may already partially satisfy the verifier criteria — before the agent does anything. The do-nothing test then returns a non-zero score, which violates Lesson 24's invariant.

**Why it's subtle**: Pre-existing-data false positives (Lesson 100) come from records you know you added. This is different: no records were added, no setup was seeded — the application ships with defaults that match your criteria. You never think to check whether the criteria already fire on a fresh install.

**Real example**: GeoServer 2.25.2 ships with:
- WFS service enabled by default
- Default WFS title: `"GeoServer Web Feature Service"`
- Default `maxFeatures`: `1000000`

A task requiring "Enable WFS, set a Natural Earth title, and set maxFeatures to 5000" with verifier criteria:
```python
if result.get('wfs_enabled'): score += 15          # fires immediately (default: enabled)
elif 'feature' in wfs_title.lower(): score += 5    # fires immediately (default title)
if max_features >= 5000: score += 10               # fires immediately (default 1000000)
```
...produces score=30 on a do-nothing run with no agent interaction.

**How to detect this**: After writing the verifier, construct a mock result JSON using the application's actual default state (query it via the API, read the default config file, or run the do-nothing live test) and feed it to the verifier. Any non-zero score is a false positive.

**Two-part fix**:

**Part 1 — Reset the relevant defaults in `setup_task.sh`** so the environment starts in a predictable non-default state that the agent must actively change:

```bash
# GeoServer example: disable WFS at task start so agent must enable it
curl -s -u "admin:password" -X PUT \
    "http://localhost:8080/geoserver/rest/services/wfs/settings" \
    -H "Content-Type: application/json" \
    -d '{"wfs": {"enabled": false}}' 2>/dev/null || true
echo "false" > /tmp/initial_wfs_enabled
```

This turns a "default satisfies criterion" situation into a "agent must change this" situation, while also making setup idempotent.

**Part 2 — Design numeric criteria to exclude obvious defaults** using bounded ranges instead of one-sided inequalities:

```python
# BAD: default value 1000000 satisfies ">= 5000" without any agent action
if max_features >= 5000:
    score += 10

# GOOD: [1000, 50000] explicitly excludes the default 1000000
if 1000 <= max_features <= 50000:
    score += 10
```

When the application has a well-known sentinel default (0=unlimited, 1000000=no limit, -1=inherit), express the criterion as a range that excludes that sentinel. Document the expected value in the task description so the agent knows what to target.

**More broadly — checklist for configuration-based criteria**:

For every verifier criterion that checks a configuration setting or service state, ask:
1. What is the application's default value for this setting?
2. Does the default value satisfy my criterion?
3. If yes: either reset the default in setup, or tighten the criterion so the default doesn't satisfy it.

**Scope**: This applies to any task that requires configuring a service, toggling a feature, adjusting a limit, or modifying a preference. It is especially common in server applications (GeoServer, GeoServer WFS/WCS/WMS, emoncms, FreeScout) that ship with sensible defaults, and in desktop applications that remember user preferences across sessions.

**Rule**: Before finalizing any verifier criterion based on a configuration value, query the live initial state and verify that criterion returns False on the default configuration. If it does not, fix either `setup_task.sh` (reset the default) or the criterion (tighten the range).

---

## Lesson 104: Command Substitution Inside Python Heredocs Must Produce Python-Capitalized Booleans

**The Problem**: Lesson 16 covers `$BASH_VAR` interpolated directly into a `python3 -c "..."` block — bash `"true"`/`"false"` strings become Python `NameError` because Python uses `True`/`False`. The same issue has a second variant: **command substitution** inside an unquoted `python3 << PYEOF` heredoc:

```bash
# BAD — command substitution echoes lowercase 'true'/'false', which Python can't parse
python3 << PYEOF
result = {
    "wfs_enabled": $([ "$WFS_ENABLED" = "true" ] && echo "true" || echo "false"),
    "layer_found": $([ "$LAYER_FOUND" = "true" ] && echo "true" || echo "false"),
}
PYEOF
```

When `$()` executes and echoes `"true"` or `"false"`, Python sees a bare identifier — `true` and `false` are not defined in Python. The block raises `NameError`, Python exits non-zero, and the heredoc writes nothing to the output file. The `safe_write_result` call then copies an empty file, and `json.load()` raises `"Expecting value: line 1 column 1 (char 0)"`. The export script may still print "Export Complete" because the heredoc error doesn't propagate to the enclosing bash script.

**What's different from Lesson 16**: Lesson 16 covers direct variable interpolation (`$VAR`). This lesson covers *command substitution* (`$(...)`). With direct interpolation, the fix is string comparison (`'$VAR' == 'true'`). With command substitution, the fix is at the echo level.

**The Fix**: Use Python-capitalized output in the echo statements:

```bash
# GOOD — echo "True"/"False" (capital T/F) matches Python's boolean literals
python3 << PYEOF
result = {
    "wfs_enabled": $([ "$WFS_ENABLED" = "true" ] && echo "True" || echo "False"),
    "layer_found": $([ "$LAYER_FOUND" = "true" ] && echo "True" || echo "False"),
}
PYEOF
```

**Why the empty-file failure is silent**: The Python process exits non-zero, but bash's `<< PYEOF` heredoc does not propagate the Python exit code unless you explicitly check `$?` after the block. The enclosing script continues normally. Always verify the output file is non-empty after running an export script that uses Python heredocs:

```bash
# After running export
if [ ! -s /tmp/task_result.json ]; then
    echo "ERROR: result JSON is empty — Python heredoc likely failed"
fi
```

**When to use this pattern vs. Lesson 16's alternatives**:

| Pattern | Use when |
|---------|----------|
| `'$BASH_VAR' == 'true'` (Lesson 16) | Direct bash variable, `python3 -c "..."` |
| `$(... && echo "True" \|\| echo "False")` (this lesson) | Command substitution, unquoted `<< PYEOF` heredoc |
| Pass value through a file (Lesson 16 alternative) | Complex values, or when quoted `<< 'PYEOF'` is preferred |
| Use integer 0/1 instead of booleans | Both contexts — works in Python, JSON, and bash equally |

**Rule**: Any `echo "..."` statement whose output is interpolated into a Python context must produce Python-valid literals. For booleans: `echo "True"` and `echo "False"` (capital). For strings: standard quoted strings. For numbers: numeric literals. Never echo bare `true`/`false` into a Python heredoc.

---

## Lesson 105: Reference-Data Tasks — Specify What the Data Must Be, Not How to Create It

**Context**: Some applications — GPS route planners, GIS tools, CAD packages, drawing tools, form designers — produce structured reference data as their primary output (waypoints, features, geometry, layers, records). Tasks for these applications require the agent to create specific data objects with precise attributes (names, coordinates, symbols, relationships). This creates a subtle but critical confusion that does not arise in document-editing or database-entry applications.

**The trap**: Because the task must specify exact target data (e.g., "waypoint named X at lat/lon Y with symbol Z"), the description naturally starts to feel like a recipe. Task designers drift from specifying WHAT the data must be into specifying HOW to create it.

**Two signals that your description has crossed the line:**

1. **Numbered steps**: If you find yourself writing "Step 1 —", "Step 2 —", etc., you are writing a recipe, not a goal. A task goal has no inherent ordering — it describes an end state. A recipe has explicit ordering — it describes a workflow. Hard and very-hard tasks must describe end states.

2. **Export menu path**: Writing `"File → Export → Export 'My Collection'... → GPX → save to C:\path\file.gpx"` specifies HOW to export (which menus to navigate). The correct form specifies WHAT the deliverable is: `"export the entire My Collection as a GPX file and save it to C:\path\file.gpx"`. The output path is end-state; the menu path is UI navigation.

**The correct pattern for reference-data tasks:**

```
# WRONG — specifies HOW (UI navigation + workflow steps)
"Step 1 — Create waypoints: Click the New Waypoint button in the toolbar.
 Enter Name: DEPOT SOUTH BOSTON, Lat: 42.3456, Lon: -71.0123, Symbol: Building.
 Repeat for each waypoint below.
 Step 2 — Create route: Use the New Route tool and add waypoints in order...
 Step 3 — Export: File → Export → Export 'My Collection'... → GPX → Desktop\file.gpx"

# CORRECT — specifies WHAT (data requirements + end state)
"Create these 7 waypoints in My Collection with exact names, coordinates, and symbols:
 1. Name: DEPOT SOUTH BOSTON  |  Lat: 42.3456  Lon: -71.0123  |  Symbol: Building
 2. ...
 Create this route — Name: FREIGHT RUN  |  Waypoints in order: DEPOT, STOP1, STOP2
 When done, export the entire My Collection as a GPX file and save it to
 C:\Users\Docker\Desktop\FreightRoute.gpx"
```

The second form tells the agent exactly what data must exist in the output; the agent must discover which tools, menus, and dialogs to use. The first form reduces the task to a tutorial walkthrough.

**Why this matters for difficulty**: If you specify "click the New Waypoint button", any agent that can read text can complete the task without any knowledge of the software. If you specify only the required data, the agent must know (or discover) how to create waypoints in this specific application — which is the actual skill being tested.

**The output path vs. the menu path distinction**: Specifying where to save an output file (`C:\Users\Docker\Desktop\filename.gpx`) is an end-state requirement — it tells the agent WHAT the deliverable looks like. Specifying the export dialog sequence (`File → Export → ...`) tells the agent HOW to reach that end state. Always specify the former; never the latter for hard/very_hard tasks.

**Applies to**: GPS route planners (BaseCamp, OziExplorer), GIS tools (QGIS, ArcGIS), CAD packages (AutoCAD, LibreCAD), drawing tools (draw.io, diagrams.net, Inkscape), any application where the agent creates structured spatial or graphical data objects with specific attributes.

---

## Lesson 106: Docker Hub Unauthenticated Rate Limiting in Shared VM Environments — Pre-Save Images Offline via Skopeo

**The problem**: The QEMU/Apptainer VM infrastructure often shares outbound IP addresses across many concurrent test runs. Docker Hub's unauthenticated pull rate limit (100 pulls per 6 hours per IP) is exhausted quickly. Every `docker pull` in `setup_docker.sh` or `setup_task.sh` fails silently (with `|| true`) — the images never load, the task environment is empty, and your tests report phantom results (trivy returning 0 CVEs for non-existent images, docker compose failing to find base images, etc.).

**How to detect it**: Run `docker pull ubuntu:20.04` inside the VM and look for "You have reached your unauthenticated pull rate limit". If you see `docker images` showing 0 images after `setup_docker.sh` completes, rate limiting is the cause.

**The fix — pre-save images as tarballs using skopeo**:

On the host machine (where `skopeo` is typically available), use Amazon ECR Public Gallery as a Docker Hub mirror — it has no unauthenticated rate limit:

```bash
# ECR Public mirrors official Docker Hub images at public.ecr.aws/docker/library/<name>:<tag>
mkdir -p benchmarks/cua_world/environments/<your_env>/data/docker_images/
skopeo copy docker://public.ecr.aws/docker/library/ubuntu:20.04 \
    "docker-archive:benchmarks/cua_world/environments/<your_env>/data/docker_images/ubuntu_20.04.tar:ubuntu:20.04"
skopeo copy docker://public.ecr.aws/docker/library/postgres:15 \
    "docker-archive:benchmarks/cua_world/environments/<your_env>/data/docker_images/postgres_15.tar:postgres:15"
# ... repeat for all required base images
```

Then update `setup_docker.sh` to use `docker load` instead of `docker pull`:

```bash
IMG_DIR="/workspace/data/docker_images"
load_image() {
    local tarfile="$1" tag="$2"
    if [ -f "${IMG_DIR}/${tarfile}" ]; then
        docker load < "${IMG_DIR}/${tarfile}" 2>&1 | grep -v "^$" || true
    else
        docker pull "${tag}" 2>/dev/null || true  # fallback
    fi
}
load_image "ubuntu_20.04.tar"   "ubuntu:20.04"
load_image "postgres_15.tar"    "postgres:15"
```

The workspace `/workspace/data/` is copied from the host into the VM at boot, so tar files stored in `benchmarks/cua_world/environments/<env>/data/docker_images/` are accessible as `/workspace/data/docker_images/` inside the VM.

**Key properties of ECR Public Gallery**:
- `public.ecr.aws/docker/library/<name>:<tag>` mirrors all Docker Hub official images
- No authentication required, no rate limits
- Works with skopeo, crane, and other OCI tools without a Docker daemon
- The `docker-archive` format (used with `:tag` annotation) produces tars loadable by `docker load`

**Storage considerations**: Base images are large (Python 3.11: ~1.1 GB tar, Postgres 15: ~430 MB tar). Budget approximately 100–500 MB per image. Store them in `data/docker_images/` outside of git tracking if your repo has size limits (add to `.gitignore` and store on shared filesystems instead).

**Applies to**: Any environment that requires Docker images and uses QEMU/Apptainer VMs with shared outbound IPs. This is a structural infrastructure constraint, not a task design flaw — adapt setup scripts to load from pre-saved tarballs rather than pulling live.

---

## Lesson 107: Trivy Cannot Scan Docker-Built Images in `overlayfs` Storage Environments — Use `trivy fs` for Package Manifest Scanning

**The problem**: In QEMU VMs where Docker uses the `overlayfs` storage driver (check with `docker info | grep "Storage Driver"`), images built via `docker build` are stored in a layer format that Trivy's image scanner cannot read. Trivy reports:

```
FATAL Fatal error  run error: image scan error: scan failed: failed analysis: analyze error:
pipeline error: failed to analyze layer (sha256:...): walk error:
failed to extract the archive: unexpected EOF
```

This happens even with `--scanners vuln` (to disable secret scanning) and even with `docker save | trivy image --input`. It affects ALL locally-built images regardless of whether BuildKit is enabled. Images loaded from Docker-archive tarballs (via `docker load`) scan fine because their layer format differs from freshly-built images in overlayfs.

**Why it happens**: With `overlayfs`, the diff layers added by `docker build` are stored as plain overlay directories rather than compressed tar archives. Trivy's image layer walker expects a gzip-compressed tar archive for each layer and receives raw bytes, producing the "unexpected EOF" error.

**The fix — use `trivy fs` to scan source manifests instead of Docker images**:

`trivy fs` scans dependency manifest files (requirements.txt, package.json, Gemfile.lock, go.sum, etc.) directly on the filesystem. It finds the same package-level CVEs without touching Docker's layer storage:

```bash
# Instead of:
trivy image --severity CRITICAL --format json acme-myapp:current

# Use:
trivy fs --severity CRITICAL --scanners vuln --format json /path/to/project/
```

`trivy fs` correctly detects CVEs in `requirements.txt`, `package.json`, `Pipfile.lock`, `Gemfile.lock`, `go.sum`, `cargo.lock`, etc. — the same vulnerability data, without any Docker layer access.

**Adapting task logic**: When the verifier uses CVE counts to measure agent success, replace Docker image scanning with filesystem scanning:
- **Initial count** (setup_task.sh): `trivy fs` on the project directory that contains the vulnerable manifest → should return > 0
- **Post-fix count** (export_result.sh): `trivy fs` on the same project directory after agent edits → should return 0 if the agent upgraded vulnerable packages
- **Rebuilt check** (export_result.sh): keep `docker inspect <image> --format '{{.Created}}'` to verify the agent actually rebuilt after editing; the image timestamp tells you this without scanning

**Why this is actually better**: The agent's primary action is editing `requirements.txt`/`package.json` and then rebuilding. Scanning the source manifest directly is semantically correct — it measures whether the dependency declaration was fixed, which is the actual remediation the task requires.

**Applies to**: Any task that uses Trivy or similar tools to measure vulnerabilities in a QEMU/overlayfs environment. The `overlayfs` driver is common in container-in-VM setups. If `docker info | grep "Storage Driver"` shows `overlayfs` (not `overlay2`), use `trivy fs` or another manifest-based scanner instead of `trivy image`.

---

## Lesson 108: Python Package CVE Selection — Avoid Very Old Versions That Lack Pre-Built Wheels

**The problem**: When designing security tasks that require intentionally vulnerable Python packages, it is tempting to use very old package versions (e.g., `cryptography==2.1.0` from 2017, `cffi==1.14.0`). These old versions:
1. Pre-date the manylinux wheel format, so PyPI has no pre-built binary for them
2. Require a C compiler and native libraries (gcc, libssl-dev, libffi-dev) to build from source
3. Slim/minimal Docker images (`python:3.x-slim`, `node:x-slim`, `alpine`) do not include a C toolchain
4. `pip install` fails inside the Dockerfile's `RUN pip install -r requirements.txt` → the `docker build` fails → the image never exists → the task is broken

**How to detect it**: Run `docker build` and look for `error: command 'gcc' failed` or `Missing required library` in the output. If the task expects a vulnerable image but `docker images | grep acme-*` shows nothing, the build likely failed due to a missing C toolchain.

**The fix — choose packages with guaranteed pre-built wheels**:

Use packages whose vulnerable versions have manylinux or platform wheel artifacts on PyPI. These install without any native compilation:

| Package | Vulnerable version | CVE | CVSS | Fix version |
|---|---|---|---|---|
| PyYAML | 5.3.1 | CVE-2020-14343 | 9.8 CRITICAL | ≥6.0.1 |
| Pillow | 8.2.0 | CVE-2021-34552 | 9.8 CRITICAL | ≥8.3.2 |
| ejs (npm) | 1.0.0 | CVE-2022-29078 | 9.8 CRITICAL | ≥3.1.7 |
| minimist (npm) | 0.2.3 | CVE-2021-44906 | 9.8 CRITICAL | ≥1.2.6 |

**Verification pattern**: Before finalizing a vulnerable package version, confirm pre-built wheel availability:
```bash
pip download --no-deps <package>==<version> --dest /tmp/testpkg
ls /tmp/testpkg  # should show a .whl file, NOT a .tar.gz source distribution
```
If only a `.tar.gz` is shown, the package has no binary wheel and will fail to install without a C toolchain.

**For packages that genuinely require C extensions at newer versions** (e.g., cryptography ≥2.5 has wheels, but 2.1.0 does not): either use a version that does have wheels, or add `gcc libssl-dev libffi-dev` to the Dockerfile's `apt-get install` line. The latter works but bloats the image and makes the task slightly less realistic.

**Applies to**: Any task that ships intentionally-vulnerable Docker images with Python or native packages. The same principle applies to Ruby gems (check for `.gem` vs source), Node native addons, and Rust crates — always verify that your chosen vulnerable version has a pre-compiled artifact available for the target platform (linux/amd64 or linux/arm64).

---

### 109. Environments May Share a Tasks Directory via Symlink — Inspect Before Modifying

**The discovery**: Some environments that are minor variants of each other (e.g., a "fast" variant with different startup parameters, a "lite" variant with lower resolution) share the same tasks directory via a symlink rather than maintaining a separate copy.

```
benchmarks/cua_world/environments/
├── gimp_env_all/
│   └── tasks/           ← real directory (150+ tasks)
└── gimp_env_all_fast/
    └── tasks -> ../gimp_env_all/tasks   ← symlink to the same directory
```

**Why this matters for task creation**:

1. **Creating a task "in" the symlinked environment actually creates it in the real target** — it becomes visible from both environments automatically.
2. **Deleting a task "from" the symlinked environment deletes it from the real target** — `rm -rf benchmarks/cua_world/environments/env_fast/tasks/my_task` removes from `env_all/tasks/` too.
3. **If the symlink itself is accidentally deleted**, the environment's `env.json` mount will break — the framework will fail to mount `benchmarks/cua_world/environments/env_fast/tasks` because the path no longer exists.

**Before creating or deleting tasks, always inspect the target directory**:

```bash
# Check whether 'tasks' is a real directory or a symlink
ls -la benchmarks/cua_world/environments/<env_name>/

# Output for a symlink:
# lrwxrwxrwx  1 user user  21 Jan  1 00:00 tasks -> ../gimp_env_all/tasks
#             ↑ 'l' prefix = symlink

# Output for a real directory:
# drwxr-x---  4 user user 128 Jan  1 00:00 tasks
#             ↑ 'd' prefix = real directory
```

**If you accidentally delete the symlink**, recreate it:

```bash
cd benchmarks/cua_world/environments/<env_name>/
ln -s ../other_env/tasks tasks
```

**If you are adding tasks that should be visible in BOTH the variant and the original environment**: create them anywhere in the shared tasks directory — both environments will see them through their respective paths.

**If you are adding tasks that should only be visible in ONE environment**: you cannot share a symlink; you need to convert the symlinked path to a real directory (copy the symlink target, then create a real directory). This is rarely needed — most variant environments are intended to share the same task set.

**Applies to**: Any environment discovery step. Before touching any `tasks/` directory, run `ls -la` on the parent to check for the `l` prefix on the directory entry.

---

### 110. Multi-URL Fallback Strategy for Real-Data Downloads

**The context**: Section 23 establishes that you must never fall back to synthetic generation when a download fails. But it leaves open the question: *how* do you make a real-data download robust enough to not fail the whole task due to a transient network issue or a changed URL?

**The answer: multiple real URLs, validated by size, fail-hard if all fail.**

A robust download block tries 2–3 different real sources in sequence. It validates that each download produced a plausibly-sized file (not a 404 HTML page), and exits with a clear error only when every real source has been exhausted:

```bash
DEST="/home/ga/Desktop/source_photo.jpg"
MIN_BYTES=20000   # anything smaller is likely an error page

# Primary source (e.g., Wikimedia Commons)
wget -q --timeout=30 -O "$DEST" \
  "https://upload.wikimedia.org/wikipedia/commons/thumb/.../photo.jpg" 2>/dev/null

# Check size — a 404 page is typically < 5 KB
if [ ! -f "$DEST" ] || [ $(stat -c%s "$DEST" 2>/dev/null || echo 0) -lt $MIN_BYTES ]; then
  echo "Primary URL failed, trying first fallback..."
  wget -q --timeout=30 -O "$DEST" \
    "https://other-real-source.org/photo.jpg" 2>/dev/null
fi

# Second fallback (different domain)
if [ ! -f "$DEST" ] || [ $(stat -c%s "$DEST" 2>/dev/null || echo 0) -lt $MIN_BYTES ]; then
  echo "Second fallback..."
  wget -q --timeout=30 -O "$DEST" \
    "https://images.unsplash.com/photo-xyz?w=1280&q=80" 2>/dev/null
fi

# Hard fail — no synthetic generation
if [ ! -f "$DEST" ] || [ $(stat -c%s "$DEST" 2>/dev/null || echo 0) -lt $MIN_BYTES ]; then
  echo "ERROR: All download sources failed for $DEST"
  echo "ERROR: This task requires a real image. Check network connectivity."
  exit 1
fi
```

**Rules for choosing fallback URLs**:

- **Use different domains** for each URL. If Wikimedia is down, Unsplash might not be. Two Wikimedia URLs for the same image provide no redundancy against a Wikimedia outage.
- **Use the same or equivalent subject matter**. All fallbacks should depict the same kind of content the task needs (a product photo, a building exterior, a portrait) — not just any available image.
- **Document license and source in comments**. Each URL should have a comment naming the license (CC-BY-SA, Public Domain, Unsplash License) so future maintainers can verify compliance.
- **Set a meaningful minimum size**. A 20 KB minimum rejects 404 HTML pages but accepts most compressed photographs. Adjust based on expected content: a full-resolution screenshot may be 500 KB+.
- **Keep `--timeout` short** (20–30 seconds). A hanging download is worse than a fast failure.

**What NOT to do**:

```bash
# WRONG: falls back to synthetic image generation
wget -q -O image.jpg "$URL" || python3 -c "
import numpy as np
from PIL import Image
Image.fromarray(np.random.randint(0, 256, (800,600,3), dtype=np.uint8)).save('image.jpg')
"

# WRONG: no size check — a 2 KB 404 page is accepted as success
wget -q -O image.jpg "$URL"
if [ -f image.jpg ]; then ...   # file exists but is an error page
```

**Applies to**: Any `setup_task.sh` that fetches real data from the internet. Even tasks that use built-in application sample data can benefit from this pattern for any *supplementary* downloads (fonts, reference images, etc.).

---

### 111. Save Source Files to `/tmp` at Setup Time for Before/After Verifiers

**The problem**: Many image-editing and document-editing tasks ask the agent to *transform* a provided file (e.g., retouch a photo, annotate a diagram, enhance an image). The verifier needs to measure whether the agent actually changed the file, and whether the changes go in the right direction. This requires comparing the output against the original input.

But after the agent has run, the original input may no longer be accessible in its pristine form — the agent may have saved over it, GIMP or another application may have modified it in memory, or the Desktop version may differ from what was there at setup time.

**The fix**: At the end of `setup_task.sh`, always save a copy of every input file to `/tmp/`:

```bash
# Save source for verifier comparison
cp /home/ga/Desktop/source_photo.jpg /tmp/source_photo_baseline.jpg

# Also record key statistics about the source (faster than copying the full file in some cases)
python3 -c "
from PIL import Image
import json, numpy as np
img = Image.open('/home/ga/Desktop/source_photo.jpg').convert('RGB')
arr = np.array(img)
stats = {
    'width': img.size[0], 'height': img.size[1],
    'brightness_mean': float(np.mean(arr)),
    'brightness_p5':   float(np.percentile(arr, 5)),
    'brightness_p95':  float(np.percentile(arr, 95)),
    'contrast_range':  float(np.percentile(arr, 95) - np.percentile(arr, 5)),
    'r_mean': float(np.mean(arr[:,:,0])),
    'g_mean': float(np.mean(arr[:,:,1])),
    'b_mean': float(np.mean(arr[:,:,2])),
}
with open('/tmp/source_photo_gt.json', 'w') as f:
    json.dump(stats, f, indent=2)
"
```

**In the verifier**, copy both the output file and the baseline:

```python
# Copy output (what agent produced)
copy_from_env("/home/ga/Desktop/retouched.png", str(result_local))

# Copy baseline (what was there before the agent ran)
copy_from_env("/tmp/source_photo_baseline.jpg", str(source_local))

# Copy precomputed stats (cheaper than always copying the full image)
copy_from_env("/tmp/source_photo_gt.json", str(gt_local))
gt = json.loads(gt_local.read_text())
```

**What you can verify with this pattern**:

| Criterion | How to detect |
|-----------|--------------|
| Agent actually changed the file | `np.mean(np.abs(output_arr - source_arr)) > threshold` |
| Brightness improved | `np.mean(output) > gt['brightness_mean'] + N` |
| Contrast stretched | `(p95 - p5) of output > gt['contrast_range'] + N` |
| Color cast corrected | Channel means shifted, or std of channel means reduced |
| Dimensions preserved | `output.size == (gt['width'], gt['height'])` |
| Vignette added | Center of output darker relative to corners than source |

**This pattern generalizes beyond images**: Any task that provides a starter file for the agent to modify should save that starter's state to `/tmp/` at setup time — a starter document, configuration file, or code file. The verifier then uses the `/tmp/` copy to measure delta from the starting state, not to trust that the file on the agent's Desktop is unchanged.

**Applies to**: Image editing environments (GIMP, Fiji, Photoshop), document editing environments (LibreOffice Writer/Calc, Word), code editors (VSCode, IntelliJ), and any other environment where the agent modifies a provided input file and the verifier needs to measure the extent or direction of those changes.

---

### 112. Use Output Type as an Early-Exit Gate for Data Transformation Tasks

**The problem**: Tasks that transform data from one type to another (buffer points → polygons, reproject to a different CRS, dissolve polygons by attribute, convert CSV to XML) have a dangerous failure mode: the agent exports the *source* data unchanged instead of the *transformed* result. In many cases, the source data satisfies nearly every secondary criterion — the correct number of features, the correct attribute fields, correct file existence — while failing only the primary criterion (wrong geometry type, wrong CRS, wrong schema). This causes partial-credit inflation that can push a fundamentally wrong output past the pass threshold.

**The fix**: Check the output's fundamental type (geometry type, CRS, file format, schema) immediately after confirming the file exists, and exit with a low score if the type is wrong:

```python
# In verifier.py — geometry gate for a buffer task
if data.get('file_exists'):
    score += 15  # file-existence credit
else:
    return {"passed": False, "score": 0, "feedback": "Output file not found"}

# GATE: If geometry is not polygon, the buffer was not applied
if not data.get('is_polygon'):
    geom = data.get('geom_type', 'unknown')
    return {
        "passed": False,
        "score": score,  # Only the file-existence credit
        "feedback": (
            f"FAIL: Expected polygon geometry but got '{geom}'. "
            "The buffer was not applied — the original layer may have been exported unchanged."
        ),
        "subscores": {"file_exists": score, "geometry_gate": 0}
    }
# Only award secondary criteria (feature count, attributes) after the gate passes
```

Similarly for other transformation types:

| Task type | Gate check |
|-----------|------------|
| Reproject to EPSG:X | `output_epsg == X` or `srs.IsSame(target_srs)` |
| Buffer points → polygons | `geom_type in ('POLYGON', 'MULTIPOLYGON')` |
| Dissolve N → M features | `feature_count <= source_count * 0.5` (rough gate) |
| Convert CSV → XML | file extension + valid XML parse |
| Rasterize vector → raster | `isinstance(output, rasterio.DatasetReader)` |

**Why a gate rather than a scored criterion**: If the transformation type is a scored criterion (e.g., "correct geometry: 35 pts"), the agent still gets credit for passing other criteria even when the core operation failed. A gate prevents this entirely — if the output type is wrong, no secondary criteria are evaluated.

**Applies to**: Any task in GIS (QGIS, gvSIG, ArcGIS), data processing (GDAL, GeoPandas), file conversion (LibreOffice macros), and ETL workflows where the output must be a structurally different type than the input.

---

### 113. Verify Scoring Distribution Won't Produce False-Positive Partial Passes

**The problem**: When a verifier uses N binary criteria (each criterion is either fully satisfied or 0 points) with a fixed pass threshold (e.g., 60%), an agent can pass by satisfying only ⌈0.6 × N⌉ criteria. For N = 4, satisfying any 3 of 4 criteria gets 75% → passes. This creates false positives when the "wrong" 3 criteria pass but the decisive criterion (the one proving the core operation was done) fails.

**Example failure**: A GIS buffer task has these 4 criteria (20 pts each, threshold 60%):
1. File exists (20 pts) — passes for ANY exported shapefile
2. Geometry is polygon (20 pts) — fails if buffer wasn't applied
3. Feature count ~180 (20 pts) — passes if source data was exported unchanged (same 180 points)
4. NAME field present (20 pts) — passes if source data was exported unchanged

An agent that exports the source point layer without buffering scores: 20+0+20+20 = 60 pts → **passes**. The decisive criterion (polygon geometry) failed, but the task passes.

**The fix**: Before finalizing a verifier, enumerate the 3–5 most plausible "wrong" submissions and compute their scores:

```python
# Mental model: wrong_submissions = [
#   "agent exports source unchanged":         file✓ + geom✗ + count✓ + attr✓ = 60%
#   "agent exports wrong layer":              file✓ + geom? + count✗ + attr✗ = 20%
#   "agent exports partial result (50 feat)": file✓ + geom✓ + count✗ + attr✓ = 60%
# ]
# Any that score ≥ threshold is a design flaw — fix before finalizing
```

**Fixes in order of preference**:

1. **Add a gate** (preferred): If the decisive criterion fails, return immediately with score = file-credit only. This prevents secondary criteria from inflating the score.

2. **Increase the decisive criterion's weight**: Move points from secondary criteria to the one that can *only* be satisfied by actually doing the operation. For a buffer task, polygon geometry is easy to produce incorrectly (just use any polygon source), so feature count (proving the RIGHT number of features were buffered) or a spot-check of a specific feature are better decisive criteria.

3. **Raise the pass threshold**: 60% is the default but not sacred. If the scoring naturally produces 65–70% for a well-executed wrong submission, use 75% as the threshold. The threshold should be set based on what the worst "plausible wrong" submission scores, not as a blanket default.

4. **Run Phase 5 validation DURING design**: Do not leave Phase 5 (do-nothing, wrong-target, partial tests) until the end. Enumerate plausible wrong scenarios as you write the verifier. If any of them passes, fix the scoring before moving on.

**Applies to**: All verifiers with multiple binary criteria and a fixed pass threshold. Particularly acute for geospatial and data processing tasks where many secondary criteria (file existence, attribute fields, feature count) can be satisfied by simply exporting the source data unchanged.

---

### 114. For Attribute-Filter Tasks, Set Count Range to Exclude "Single-Filter" Results

**The problem**: Tasks that require filtering a dataset by two or more attribute conditions (e.g., CONTINENT = 'South America' AND POP_EST > 5,000,000) can be partially completed by applying only one of the two conditions. The one-filter result has a different feature count than the two-filter result. If the verifier's acceptable count range is too wide, it accepts both.

**Example**: The NaturalEarth countries dataset has 12 South American countries total. Of these, 9 have population > 5 million. The task requires both filters. If the verifier's range is [7, 13], a submission with 12 features (only continent filter applied) passes. Range [7, 10] correctly rejects 12-feature submissions.

**The fix**:

1. Compute the "full filter" count: apply ALL required conditions to the source data and count the results (e.g., 9 countries with CONTINENT='South America' AND POP_EST>5M).

2. Compute the "single-filter" count for each individual condition: apply each condition alone (e.g., 12 countries with CONTINENT='South America').

3. Set the upper bound of the acceptable range below all "single-filter" counts: if any single filter produces ≥ N features and the full filter produces M features (M < N), set `upper_bound = N - 1` and `lower_bound = max(1, M - 2)`.

```python
# In setup_task.sh — compute and store ground truth at setup time
python3 << 'PYEOF' > /tmp/filter_ground_truth.json
from osgeo import ogr
import json

src = '/path/to/source.shp'
ds = ogr.Open(src)
lyr = ds.GetLayer()

# Full filter (both conditions)
lyr.SetAttributeFilter("CONTINENT = 'South America' AND POP_EST > 5000000")
full_count = lyr.GetFeatureCount()

# Single filter A (continent only)
lyr.SetAttributeFilter("CONTINENT = 'South America'")
single_a_count = lyr.GetFeatureCount()

lyr.SetAttributeFilter(None)
print(json.dumps({'full_count': full_count, 'single_a_count': single_a_count}))
PYEOF
```

Then in the verifier, use ground-truth counts rather than hard-coded ranges:

```python
# Read ground truth computed at setup time
copy_from_env('/tmp/filter_ground_truth.json', gt_path)
gt = json.loads(open(gt_path).read())
full_count = gt['full_count']          # e.g., 9
single_a_count = gt['single_a_count']  # e.g., 12

fc = result.get('feature_count')
# Accept range: [full_count - 2, single_a_count - 1]
# This includes the correct answer but excludes single-filter results
low = max(1, full_count - 2)
high = single_a_count - 1  # Strictly exclude the single-filter count

if fc is not None and low <= fc <= high:
    score += 20  # Full credit: count is in the "both filters applied" range
elif fc is not None and fc == single_a_count:
    score += 0   # No credit: only one filter was applied
    feedback_parts.append(
        f"Feature count {fc} matches applying only ONE of the two required filters. "
        f"Both conditions must be applied simultaneously."
    )
```

**Key insight**: Hard-coding a range like [7, 13] is fragile — it depends on properties of the specific dataset that may change. Computing expected counts dynamically at setup time and deriving the acceptable range from them produces a verifier that is both dataset-aware and robust to partial-filter submissions.

**Applies to**: Any task requiring multi-condition attribute filtering in GIS (QGIS, gvSIG, ArcGIS, GDAL), database tools (DBeaver, MySQL Workbench), spreadsheet tools (LibreOffice Calc), or any environment where the agent selects a subset of records by multiple criteria.

---

### 115. GT-in-Setup Must Restore the Clean State After Computing Ground Truth

**The problem**: When setup_task.sh uses the GT-in-Setup pattern (Lesson 77) and computing the ground truth requires running the same tool or simulation that the agent must run, the tool may write its output into the same template file it read as input — leaving the environment in an already-solved state before the agent even starts.

**Concrete example**: A hydraulic simulation tool is invoked on `model.tmp.hdf` (the template). It writes results directly into `model.tmp.hdf`. After setup_task.sh finishes collecting GT, `model.tmp.hdf` now contains computed results. The agent discovers a fully-populated output file and can extract the answer without running any simulation at all — trivializing the task.

The same problem arises with:
- A 3D rendering tool that writes its output into the source scene file.
- A solver that appends results to the input deck.
- A data processing script that modifies the source CSV in place.
- Any tool that uses the input file as both input and output.

**The fix**: After the GT computation, immediately restore the template to its clean, pre-run state before the agent sees the environment:

```bash
# Step 1 — back up the clean template at the START of setup_task.sh, before touching it
cp ~/project/model.tmp.hdf /tmp/model_template_clean.hdf

# Step 2 — run the tool to compute GT
run-solver ~/project/model.tmp.hdf
python3 -c "
import h5py, json
with h5py.File('~/project/model.tmp.hdf', 'r') as f:
    peak = float(f['Results/WaterSurface'][:].max())
json.dump({'peak_wse': peak}, open('/tmp/GT.json','w'))
"

# Step 3 — RESTORE the clean template so the agent starts fresh
cp /tmp/model_template_clean.hdf ~/project/model.tmp.hdf

# Also remove any output files the tool may have created
rm -f ~/project/model.output.hdf  # or whatever output file the tool creates
```

**What to back up**: Back up the template at the very start of setup_task.sh, before any tool invocation — not after, not inside the GT block. If your setup has multiple GT simulation runs (e.g., baseline and improved), back up the clean template once at the start and restore from that single backup after each run.

**What the verifier must check**: Because the agent must run the simulation from a clean state, the verifier should confirm that the agent's output file is *newer* than the task start time (using file mtime), not just that the file exists. A file that predates the task cannot be the agent's work.

```python
import os, time
output_mtime = os.path.getmtime('/path/to/output.hdf')
task_start   = task_info.get('start_time', 0)
if output_mtime <= task_start:
    return {"passed": False, "score": 0,
            "feedback": "Output file predates task start — simulation was not run by the agent."}
```

**Applies to**: Any simulation, solver, or rendering environment where the tool writes output into (or alongside) its input template. Particularly common in hydraulic modeling (HEC-RAS, HEC-HMS), finite-element solvers (OpenFOAM, ANSYS), circuit simulators (LTspice, ngspice), and statistical tools (R scripts, MATLAB scripts) that modify the workspace file in place.

---

### 116. Multi-Phase Tasks — Use Score Ceilings to Require Both Phases, Not Just a High Pass Threshold

**The problem**: Some tasks require completing two sequential phases: Phase A (a baseline or prerequisite run), followed by Phase B (the main deliverable that builds on Phase A). An agent that completes only Phase A can accumulate substantial partial credit — sometimes enough to reach the pass threshold — even though the core deliverable of the task was never attempted.

Raising the pass threshold (e.g., to 80%) is insufficient if Phase A itself is worth more than the threshold. A score ceiling is the correct structural fix.

**Example**: A scenario comparison task awards:
- 30 pts for Phase A (baseline run + baseline outputs)
- 50 pts for Phase B (improved run + comparison deliverables)
- 20 pts for the final summary report

Pass threshold: 60%. An agent that does only Phase A scores 30 pts → does not pass. But if Phase A is worth 40 pts, the agent scores 40 pts → still does not pass at 60%. If Phase A is worth 65 pts for any reason, the agent passes without ever doing Phase B.

**The fix**: In the verifier, detect whether Phase B was attempted. If not, apply a score ceiling *below* the pass threshold before returning:

```python
# Determine whether Phase B was attempted
phase_b_done = (
    result.get("improved_output_exists") and
    result.get("comparison_file_exists")
)

# If Phase B was never attempted, cap the score below the pass threshold
# regardless of how many Phase A criteria passed
if not phase_b_done:
    score = min(score, PASS_THRESHOLD - 1)  # e.g., min(score, 59)
    return {
        "passed": False,
        "score": score,
        "feedback": (
            "Only Phase A (baseline) was completed. Phase B (the improved scenario) "
            "is required. Score capped below pass threshold. "
            f"Partial credit for Phase A: {score} pts."
        )
    }
```

**When to use this vs. a gate (Lesson 112)**: A gate returns immediately with a fixed score when a prerequisite fails. A ceiling allows partial credit to accumulate from Phase A but enforces that the total cannot pass. Use a gate when Phase A is trivially satisfied (just "did the file exist?"). Use a ceiling when Phase A involves substantial legitimate work that deserves credit even when Phase B is incomplete.

**Setting the ceiling**: Set the ceiling at `pass_threshold - 1`. If your pass threshold is 60, set the ceiling at 59. If the threshold is 70, set it at 69. This makes the rule structurally clear: Phase A alone, no matter how well executed, cannot pass the task.

**Labeling the ceiling in feedback**: Always tell the agent explicitly that a ceiling was applied, what the ceiling value is, and why. This makes it visible in evaluation logs that the score was not a natural result of criteria scoring.

**Applies to**: Any task that requires two sequential deliverables where the second builds meaningfully on the first — A/B scenario comparisons (hydraulic modeling, structural analysis, energy simulation), baseline + optimized workflow tasks, pre- and post-treatment comparisons in medical or environmental applications, and benchmark + tuned-model tasks in data science.

---

### 117. Iterative Calibration Tasks — Reward the Exploration Trajectory, Not Just the Final Answer

**The problem**: Some tasks ask the agent to *calibrate* a model parameter by running multiple simulations, comparing outputs to a target observation, and iteratively converging to the correct parameter value. These tasks are inherently different from single-run tasks: the agent is not just producing one output, it is running an optimization loop. A verifier that only checks the final parameter value or the final simulation output misses the structure of the task and is vulnerable to guessing.

**Why "just check the final answer" is insufficient**:
1. An agent might hard-code a plausible-looking parameter value without running any simulation.
2. An agent might run only one simulation and pick the result, even if it is far from converged.
3. An agent that runs N iterations but converges in the wrong direction (diverges) should not receive the same credit as one that converges correctly.

**The correct verifier structure for calibration tasks**:

```python
# ── Criterion A: Evidence that at least N simulations were run ───────────
log = result.get("calibration_log", [])  # list of {"n_value": x, "peak_wse": y}
distinct_n = len(set(entry["n_value"] for entry in log))
if distinct_n >= 3:
    score += 20   # Exploration credit — agent ran multiple trials
elif distinct_n == 2:
    score += 10   # Partial credit
# distinct_n <= 1: 0 pts

# ── Criterion B: Final parameter within tolerance of the known-best value ─
# NOTE: The "correct" value is whatever produces the target output,
# not an arbitrary hard-coded n. Use GT-in-Setup to compute it.
final_n = result.get("final_n_value")
gt_best_n = gt["true_default_n"]          # from /tmp/GT.json
if final_n is not None and abs(final_n - gt_best_n) / gt_best_n <= 0.20:
    score += 25   # Final parameter is within 20% of the correct value

# ── Criterion C: Best simulation output within tolerance of target ────────
# This is independent of parameter accuracy — rewards agents who found a
# good n even via a different path than expected
target_wse = gt["observed_peak_wse"]
best_wse = min(abs(e["peak_wse"] - target_wse) for e in log) if log else float("inf")
if best_wse <= 0.5:   # within 0.5 ft of observed
    score += 25

# ── Criterion D: Log or report documents the iterations ──────────────────
if result.get("report_exists") and result.get("report_word_count", 0) >= 50:
    score += 10
```

**Key principle**: Criteria A, B, and C are independent. An agent that:
- Gets lucky and guesses the correct n on iteration 1: earns B + C but not A (no exploration evidence).
- Runs 5 iterations but diverges: earns A but not B or C.
- Runs 3 iterations, converges to within 15% of the correct n, and achieves WSE within 0.3 ft: earns A + B + C — full credit.

**The "target" is the observable output, not the parameter**: In calibration tasks, the ground truth is the observed measurement (e.g., a gauge reading of 952.1 ft) — not a canonical "correct" parameter. The GT-in-Setup pattern should run the reference simulation with default parameters and record the resulting observable as the "target". This makes the task physically meaningful: the agent is calibrating to match reality, not to reproduce an arbitrary number.

**Offline mock test design**: When testing the partial scenario, choose parameter values that go in the *wrong direction* (away from the target) or that show too few iterations. Do not accidentally choose "partial" values that happen to be close to correct — a mock that scores 80% when it should score ~40% indicates the partial scenario is too easy (see Lesson 113).

```python
# BAD partial mock — n_values converge toward correct answer
mock_partial = {"n_values": [0.036, 0.031], "final_n": 0.031, "best_wse": 947.0}
# GOOD partial mock — n_values go in the wrong direction
mock_partial = {"n_values": [0.036, 0.040], "final_n": 0.040, "best_wse": 950.1}
```

**Applies to**: Any task requiring iterative model calibration — hydraulic model calibration (HEC-RAS, HEC-HMS Manning's n), hydrological model calibration (SWAT, VIC), structural model updating, PID controller tuning, and machine learning hyperparameter tasks where the agent must empirically search a parameter space rather than derive the answer analytically.

---

### 118. Unit-Test Verifiers Offline with a Mock `copy_from_env` Before Booting the VM

**The discovery**: You do not need a running VM to validate Phase 5 (do-nothing, wrong-target, partial tests). Create a mock `copy_from_env` function that writes pre-crafted JSON and CSV content directly to the destination path, then call the verifier function directly in Python. This validates the entire verifier logic in seconds, on any development machine, without Apptainer or QEMU.

**The mock pattern**:

```python
import json, importlib.util, tempfile, os

def make_copy_from_env(json_data, csv_content=None):
    """Return a mock copy_from_env that serves pre-crafted content."""
    def copy_from_env(src_path, dst_path):
        if src_path.endswith('.json'):
            with open(dst_path, 'w') as f:
                json.dump(json_data, f)
        elif src_path.endswith('.csv') or src_path.endswith('.txt'):
            if csv_content is None:
                raise FileNotFoundError(f"Mock: output file not present: {src_path}")
            with open(dst_path, 'w') as f:
                f.write(csv_content)
        else:
            raise FileNotFoundError(f"Mock: unknown path: {src_path}")
    return copy_from_env

# Load verifier module dynamically
spec = importlib.util.spec_from_file_location('verifier', 'benchmarks/cua_world/environments/<env>/tasks/<task>/verifier.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
fn = getattr(mod, 'verify_<task_name>')

# ── Test 1: Do-nothing — output file does not exist ──────────────────────
result = fn([], {'copy_from_env': make_copy_from_env({'file_exists': False})}, {})
assert result['score'] == 0 and result['passed'] == False, f"FAIL do-nothing: {result}"
print(f"[PASS] do-nothing: score={result['score']}")

# ── Test 2: Wrong-target — file exists but irrelevant content ─────────────
wrong_csv = "col1,col2\nWrong Record,Wrong Corp\n"
wrong_json = {'file_exists': True, 'file_size': len(wrong_csv), 'file_content': wrong_csv}
result = fn([], {'copy_from_env': make_copy_from_env(wrong_json, wrong_csv)}, {})
assert result['score'] <= 25 and result['passed'] == False, f"FAIL wrong-target: {result}"
print(f"[PASS] wrong-target: score={result['score']}")

# ── Test 3: Partial — some required items present, not all ────────────────
partial_csv = "col1,col2\nCorrect Name,Correct Corp\n"  # only 1 of N expected records
partial_json = {'file_exists': True, 'file_size': len(partial_csv), 'file_content': partial_csv}
result = fn([], {'copy_from_env': make_copy_from_env(partial_json, partial_csv)}, {})
assert 20 <= result['score'] <= 60 and result['passed'] == False, f"FAIL partial: {result}"
print(f"[PASS] partial: score={result['score']}")
```

**Structuring the mock JSON**: The mock JSON should mirror what `export_result.sh` writes to `/tmp/<task>_result.json`. At minimum it needs `file_exists`, `file_size`, and `file_content`. Copy these field names from your actual `export_result.sh` to keep the mock consistent.

**For the partial test, pre-calculate the expected score**: Before writing the assert, manually trace through the verifier's criteria with the partial CSV content and add up the points. Confirm the total falls below the pass threshold. If your calculated score equals the threshold, adjust the partial CSV content to include one fewer item. (See also Lesson 113 on preventing false-positive partial passes.)

**When to run it**: Immediately after writing `verifier.py`, before any attempt to boot the environment. If all three offline tests pass, the verifier logic is correct. Booting the VM is then needed only to validate the setup and export scripts (Phase 4 — testing that `/tmp/initial_*` files are created, that `export_result.sh` runs without errors, and that the real output JSON matches the shape the verifier expects).

**Applies to**: All environments. The offline unit-test pattern is environment-agnostic — it works regardless of whether the environment uses Docker, QEMU, Wine, or any other execution backend.

---

### 119. Generic Column Names and Field Labels Are Unreliable Verifier Keywords

**The problem**: When a verifier checks file content by searching for keywords, it is easy to accidentally choose keywords that appear in ANY export the application can produce — not just the correct one. Generic column headers like `"duration"`, `"company"`, `"type"`, `"total"`, `"count"`, `"status"`, `"date"`, and `"name"` are present in virtually every CSV a reporting application generates. A criterion that checks for `"duration" in content` will award points to any agent that exports any report containing that column header, regardless of whether the report contains the correct records.

**Example failure**:

```python
# Criterion: "Duration information is present in the report" (25 pts)
has_duration = "duration" in content.lower()   # ← WRONG
```

An agent that opens any built-in report with a "Duration" column header satisfies this criterion, even if the report lists entirely wrong records.

**The fix — check for values unique to the correct answer, not for field names**:

```python
# Check for specific duration values that only appear in the correct records
duration_values = ["150", "180", "2:30", "3:00", "2.5", "3.0"]
has_duration = any(kw in content for kw in duration_values)   # ← BETTER

# Or check for the combination of a specific record AND a duration figure
has_correct_record_with_duration = (
    "garcia" in content.lower() and
    any(kw in content for kw in ["150", "2:30", "2.5"])
)
```

**How to identify risky keywords**: For each criterion keyword, ask: *"Would this keyword appear in an export of the WRONG report from the same application?"* If yes, the keyword is too generic. Replace it with a value that is specific to the correct records — a person's last name, a company's distinctive word, a precise numeric figure, a specific date.

**When generic keywords ARE acceptable**: A size-based completeness criterion (e.g., "file is at least 500 bytes") uses an implicit generic signal — it does not check content at all. Similarly, checking that the file has "multiple rows" or that multiple department names appear is appropriate when the criterion's purpose is to verify that the agent produced a substantive output, not to verify correctness of specific records. For these breadth criteria, generic presence is intentional.

**Relationship to Lesson 16 (Starter File Keyword Contamination)**: Lesson 16 warns about keywords that match data already present in the environment *before* the agent acts. This lesson warns about the symmetric problem on the output side: keywords that match data present in any *wrong* export the agent might produce. Both require the same diagnostic step — grep the corpus of plausible wrong outputs against your verifier keywords before finalizing.

**Applies to**: Any file-output task where the agent uses a reporting or export feature of an application (visitor management, ERP, EHR, GIS, CRM systems) and the verifier checks the exported file's content by keyword search.

---
### 120. New Files Added After Checkpoint Creation Arrive Without Execute Permission

**The problem**: When you add new task files (such as `export_result.sh`) to an environment that already has a cached pre_start checkpoint, those new files are SCP'd into the VM without the `-p` (preserve permissions) flag. The SCP creates them as *new* files using the default umask (typically resulting in 644 — no execute bit), regardless of their permissions on the host. Files that already exist in the checkpoint keep their original permissions (e.g., 755 for scripts that were there when the checkpoint was made).

**Concrete consequence**: `setup_task.sh` was already in the checkpoint with 755, so it runs fine. `export_result.sh` was added later; it arrives as 644 and fails with exit code 126 (Permission Denied) when the framework tries to run it as post_task.

**The symptom that will confuse you**: `chmod +x` applied on the host doesn't help, because the permissions are not preserved during the VM-side file copy — the execute bit is lost in transit.

**The fix**: At the top of `setup_task.sh`, immediately after sourcing the shared utilities, add an explicit `chmod +x` for `export_result.sh`. Since `setup_task.sh` runs before `export_result.sh`, this ensures the execute bit is set inside the VM before post_task runs:

```bash
source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/<task_name>/export_result.sh 2>/dev/null || true
```

The `2>/dev/null || true` makes the line safe: it won't abort the script if the file doesn't exist yet, and it won't cause `set -e` to fire.

**Why this works**: `setup_task.sh` has its permissions preserved from the checkpoint (it's not a new file), so it runs successfully. Once it sets the execute bit on `export_result.sh` inside the VM's live filesystem, the post_task hook can execute it normally.

**Applies to**: Any environment using the `QemuApptainerRunner` where `export_result.sh` (or any other hook script) was added to the task directory after the pre_start checkpoint was originally created.

---

### 121. Do Not Prefix hook_cmd Values with `bash` — The Framework Already Wraps Hooks

**The problem**: When debugging post_task "Permission Denied" failures, it is tempting to change the `post_task` value in `task.json` from:

```json
"post_task": "/workspace/tasks/<task>/export_result.sh"
```

to:

```json
"post_task": "bash /workspace/tasks/<task>/export_result.sh"
```

thinking that this bypasses the execute-bit requirement. **This causes a timeout instead.** The framework constructs the actual SSH command as:

```
sudo -E bash -lc {hook_cmd} > /home/ga/task_post_task.log 2>&1
```

where `{hook_cmd}` is inserted *without quotes*. So `bash /workspace/tasks/.../export_result.sh` becomes:

```
sudo -E bash -lc bash /workspace/tasks/.../export_result.sh > ...
```

Shell parsing: `bash -l -c "bash"` — bash starts an interactive session (command is just the word `bash`), the script path becomes `$0`, nothing executes. The SSH command times out.

**The correct fix** is Lesson 120: use `chmod +x` inside `setup_task.sh` to give the file an execute bit before post_task runs. The `hook_cmd` field in `task.json` must always be a single executable path — no spaces, no prefixes.

**Applies to**: Any environment using the `QemuApptainerRunner` with Linux-style hook invocation.

---

### 122. The Setup → Export → Verifier Key-Name Contract: Mismatches Cause Silent False Test Results

**The problem**: Every database-backed task (EHR, ERP, CRM, inventory systems, etc.) involves three Python-writing stages:

1. `setup_task.sh` writes a ground-truth JSON to `/tmp/<task>_gt.json` with keys like `"expected_value"`, `"wrong_value"`, `"init_appts"`, etc.
2. `export_result.sh` reads that GT JSON, queries the database, and writes a result JSON to `/tmp/<task>_result.json` with keys like `"actual_value"`, `"appt_count"`, etc.
3. `verifier.py` reads the result JSON using those exact key names via `.get('actual_value', '')`, `.get('appt_count', 0)`, etc.

These three files form a **key-name contract**. If any key name drifts between the files — even a single typo like `"expected_value"` vs `"correct_value"` — Python's `.get()` silently returns the default (typically `''` or `0`). The verifier then compares `'' == ''` (or `0 == 0`) and **awards full points for nothing**, making do-nothing tests appear to pass with non-zero scores.

**The subtle failure mode**: The most dangerous drift pattern is when mock GT data in an offline test uses a different key name than the production GT. For example:

```python
# Mock GT (WRONG key name — test will produce false results)
GT = {"patients": [{"pid": 100, "correct_value": "617-555-0847"}]}  # ← "correct_value"

# Production GT from setup_task.sh (real key name)
gt = {"patients": [{"pid": 100, "expected_value": "617-555-0847"}]}  # ← "expected_value"

# Verifier reads:
expected_val = expected.get('expected_value', '')  # → '' for the mock, '617-555-0847' for production
```

In the mock test, `expected_val` is `''`. If `actual_val` is also `''` (because the mock result uses field-specific keys like `phone_home` instead of the generic `actual_value` that the export script writes), then `actual_val == expected_val` evaluates to `True` and the criterion awards full points — even though no work was done. The do-nothing test falsely reports a high score, making the verifier *appear* broken when the test data is actually wrong.

**The diagnostic step**: When a do-nothing offline test returns a non-zero score, first check whether the mock data uses the correct key names — compare them character-for-character against what `setup_task.sh` and `export_result.sh` actually write. This is more likely the cause than a logic bug in the verifier itself.

**Prevention — read before mocking**: Before writing any offline mock test, read the GT-writing Python block in `setup_task.sh` and the result-writing Python block in `export_result.sh`. Copy the exact key names from those two blocks into your mock data. Do not invent key names from memory or from the task description.

**Prevention — explicit schema comments**: Add a one-line comment to each Python writing block listing the keys it produces:

```python
# GT schema: patients[].{pid, fname, lname, field, wrong_value, expected_value,
#                         extra_field, extra_wrong, extra_expected}
gt = {"patients": [...]}

# Result schema: patients_result[].{pid, fname, lname, field, actual_value,
#                                    extra_field, extra_actual}
result = {"patients_result": [...]}
```

These comments take 30 seconds to write and prevent the entire class of key-name drift errors across all three files.

**The broader contract**: Key-name consistency must be maintained across the full pipeline:

```
setup_task.sh  ──writes──►  /tmp/<task>_gt.json
                                    ↓  (key names must match)
export_result.sh  ──reads──►  GT keys, queries DB, ──writes──►  /tmp/<task>_result.json
                                                                         ↓  (key names must match)
verifier.py  ──reads──►  result keys via .get('key', default)
```

Any key rename in one file requires the same rename in all downstream consumers. The explicit schema comments are the strongest safeguard because they make the contract visible at the point of writing.

**Applies to**: All database-backed environments (EHR, ERP, CRM, ticketing, inventory, or any task where setup seeds data, export queries it, and verifier reads the results from a structured JSON file).

---

### 123. `scrot` Produces Black Screenshots on Compositor-Enabled Desktops — Use ImageMagick `import -window root`

**The problem**: `scrot` (a common X11 screenshot utility) returns a completely black PNG when the desktop session uses a compositing window manager (e.g., Mutter on Ubuntu GNOME, Compiz, picom). The command exits with code 0 and writes a valid-looking file — it's just all black. This makes it appear to work in setup scripts and evidence-collection code, while silently producing useless screenshots.

```bash
# WRONG — produces a black image on Ubuntu GNOME with Mutter compositor
DISPLAY=:1 scrot /tmp/screenshot.png   # exits 0, black PNG

# Also broken — same root cause
DISPLAY=:1 scrot --silent /tmp/screenshot.png
```

**Why this happens**: `scrot` reads pixel data from the X compositor's internal buffer, which may not be exposed to direct X11 pixel reads when a compositor is active. The compositor renders windows off-screen and composites them; `scrot`'s direct X11 pixel read bypasses the compositor output and sees nothing.

**The fix**: Use ImageMagick's `import` tool with the `-window root` flag. `import` uses a different X11 mechanism that reads the compositor's rendered output:

```bash
# CORRECT — captures the full composited desktop including all open windows
DISPLAY=:1 import -window root /tmp/screenshot.png

# Confirm the result is not blank (non-trivial PNG is typically > 20 KB)
SIZE=$(stat -c%s /tmp/screenshot.png 2>/dev/null || echo 0)
echo "Screenshot size: $SIZE bytes"  # should be 100 KB+ for a full desktop
```

**Availability**: ImageMagick (`imagemagick` package, provides `import`) is installed by default on most Ubuntu/Debian desktop images. If it is not present, install it in `post_start.sh`:

```bash
apt-get install -y imagemagick 2>/dev/null || true
```

**Applies to**: Any evidence-collection script, setup script screenshot, or verification helper that captures a screenshot of the desktop state in Ubuntu GNOME environments (and any other compositor-enabled X11 session). Replace all `scrot` calls with `import -window root` when targeting GNOME or any other environment where a compositor is active.

---

## Lesson 124: Trace Every Verifier Criterion Against the Starting File (Complete Contamination Audit)

**Lesson #14 in this document covers keyword/text contamination**, where a starting file's text matches a verifier's text-based criterion and awards unearned points. That lesson is important but narrower than the full problem. The real rule is:

> **For every scored criterion in your verifier, manually trace what score the starting file would receive before the agent touches it. Every criterion must return 0 points for a do-nothing submission.**

This applies to ALL criterion types, not just text matching:

| Criterion type | Contamination example | Remedy |
|---------------|----------------------|--------|
| Keyword present in text | Starting title already contains required keyword | Change starting file text to neutral placeholder |
| File count / slide count | Starting file has enough slides to score partial credit on slide criterion | Lower starting count, or add a volume gate (Lesson 125 / Pattern 12) |
| Shape count / diagram detection | Starting file already has a complex slide with 6+ shapes | Simplify starting slides to minimal placeholders |
| Notes / speaker notes | Starting file includes boilerplate notes > 25 chars on every slide | Strip notes from setup_task.sh-generated ODP |
| Chart count | Starting file has embedded charts already | Remove charts from the starting stub |
| Transitions | Starting file has slide transitions set | Create slides without any transition attribute |
| Export file exists | setup_task.sh accidentally produces the export (PDF, PPTX) as a side effect | Remove any accidental export step; verify the export does not exist after setup |

**Procedure to follow before finalizing any task**:
1. Copy your `verifier.py` scoring logic to a scratch pad.
2. Mentally (or actually) run the starting file through it, criterion by criterion.
3. Confirm each criterion yields 0 points.
4. Confirm the total score is 0.
5. If any criterion yields > 0 points, fix `setup_task.sh` (not the verifier) so the starting file is genuinely neutral.

**This is especially easy to miss for**:
- Slide/chart counts when odfpy's `save()` in setup_task.sh inadvertently creates chart placeholder XML
- Notes when your `P(text=...)` elements in odfpy exceed 25 characters
- Shape counts when a text frame + text box on a slide already counts as 2 shapes toward a diagram threshold

**Applies to**: Every task in every environment. Run this audit before submitting any new task.

---

## Lesson 125: Do-Nothing Score Must Be 0 — Use a Volume Gate for Content-Building Tasks

For tasks that ask an agent to *build* a minimum quantity of content items (slides, rows, pages, paragraphs), it is tempting to rely on the item-count criterion to naturally produce a low do-nothing score. This reasoning is flawed because secondary quality criteria (charts, notes, formatting, keywords, transitions) may already score partial points on the starting file, and their combined weight can push the do-nothing score above zero or even above the pass threshold.

**The reliable fix is a blocking volume gate** (described as Pattern 12 in `03_verification_patterns.md`):

```python
if volume_count < minimum_qualifying_threshold:
    return {"passed": False, "score": 0, "feedback": "GATE FAIL: ..."}
```

Choose `minimum_qualifying_threshold` to be:
- Strictly above the starting-file item count (so do-nothing always triggers the gate)
- Below the full-credit target (so agents that made real progress are not unfairly blocked)
- Approximately halfway between starting count and target count

**Example calculation**:
- Starting file: 5 slides
- Full-credit target: 12 slides
- Gate threshold: `ceil((5 + 12) / 2) = 9`, or simply `8` (round number above 5 and below 12)

**Secondary benefit**: The gate also prevents agents from discovering that they can inflate charts/notes/transitions on the existing minimal slides (by scripting LibreOffice macros or manipulating the ODP XML directly) without doing the substantive presentation-building work the task requires.

**Applies to**: Any task that directs the agent to "expand", "build", "complete", "extend", or "add to" an existing stub document, when the verifier scores both the quantity of items and their quality.

---

## Lesson 126: Offline Testing for Multi-File Verifiers — Path-Dispatch Mock and Programmatic Binary Fixtures

**Context**: Lesson 92 covers offline mock testing for verifiers that read a single JSON result file. But some verifiers — particularly those implementing Pattern 8 (anti-tamper independent re-analysis, see `03_verification_patterns.md`) — call `copy_from_env` multiple times for *different* file types: an export JSON, a baseline JSON, and a binary application format file (ODB, XLSX, ODP, etc.). The simple "all calls return the same payload" mock from Lesson 92 breaks here: when the binary parse path receives a JSON file, it crashes or silently returns an empty result, and Pattern 8 never exercises its real code path.

**The core problem with the Lesson 92 mock for Pattern 8 verifiers**:

```python
# Lesson 92 approach (works for single-JSON verifiers, breaks for multi-file verifiers)
def mock_copy(src, dst):
    shutil.copy2(my_json_file, dst)   # writes JSON to ALL paths

# Verifier calls:
copy_from_env('/tmp/<task>_result.json',   tmp_json)   # ← gets JSON ✓
copy_from_env('/tmp/<task>_initial.json',  tmp_initial) # ← gets JSON ✓
copy_from_env('/home/ga/application.odb',  tmp_binary)  # ← gets JSON, zipfile.BadZipFile ✗
```

The existing guidance says "Pattern 8 naturally fails/skips in offline tests, exercising the fallback path." This is an acceptable minimum but means you're testing the *fallback path*, not the real binary-parse path. A scoring bug in the binary-parse branch will not be caught.

**Fix 1 — Path-dispatch mock**: dispatch on the `remote_path` argument to serve different content per file type.

```python
def make_path_dispatch_copy(binary_bytes, result_data, initial_data):
    """
    A copy_from_env mock that serves different content based on the remote path.
    Use when the verifier calls copy_from_env for 3+ different file types.
    """
    def copy_from_env(remote_path, local_path):
        # Detect binary format files by extension
        if any(remote_path.endswith(ext)
               for ext in ('.odb', '.accdb', '.mdb', '.xlsx', '.odp', '.odt', '.db')):
            with open(local_path, "wb") as f:
                f.write(binary_bytes)
        elif "_initial.json" in remote_path:
            with open(local_path, "w") as f:
                json.dump(initial_data, f)
        else:
            # Default: export result JSON
            with open(local_path, "w") as f:
                json.dump(result_data, f)
    return copy_from_env
```

**Fix 2 — Programmatic binary fixture**: create a minimal valid binary file (ZIP-based format) in memory using `io.BytesIO`, so the Pattern 8 parse actually succeeds and exercises the real scoring logic.

```python
import io, zipfile

def make_minimal_odb_fixture(
    queries=None,         # dict: {name: sql_string}
    forms=None,           # list of form names
    reports=None,         # list of report names
    new_tables=None,      # list of new table names
    insert_data=None,     # dict: {table_name: [(col1, col2, ...), ...]}
    original_tables=None, # list: pre-existing table names to exclude from new-table detection
):
    """
    Build minimal ODB ZIP bytes for offline verifier testing.
    Adapt the content.xml namespace and database/script format for your specific app.
    """
    queries = queries or {}
    forms = forms or []
    reports = reports or []
    new_tables = new_tables or []
    insert_data = insert_data or {}

    queries_xml = "\n".join(
        f'<db:query db:name="{name}" db:command="{cmd}"/>'
        for name, cmd in queries.items()
    )
    content_xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<office:document-content '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:db="urn:oasis:names:tc:opendocument:xmlns:database:1.0">\n'
        '<db:data-source><db:query-collection>\n'
        + queries_xml + '\n</db:query-collection>\n'
        '<db:forms>\n'
        + "\n".join(f'<db:form db:name="{n}"/>' for n in forms) + '\n</db:forms>\n'
        '<db:reports>\n'
        + "\n".join(f'<db:component db:name="{n}"/>' for n in reports) + '\n</db:reports>\n'
        '</db:data-source></office:document-content>\n'
    )

    script_lines = []
    for tname in (original_tables or []):
        script_lines.append(f'CREATE CACHED TABLE PUBLIC."{tname}" ("Id" INTEGER)')
    for tname in new_tables:
        script_lines.append(f'CREATE CACHED TABLE PUBLIC."{tname}" ("Id" INTEGER, "Value" VARCHAR(100))')
    for tname, rows in insert_data.items():
        for row in rows:
            vals = ",".join(f"'{v}'" if isinstance(v, str) else str(v) for v in row)
            script_lines.append(f'INSERT INTO PUBLIC."{tname}" VALUES({vals})')

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("mimetype", "application/vnd.oasis.opendocument.base")
        zf.writestr("content.xml", content_xml)
        zf.writestr("database/script", "\n".join(script_lines))
    return buf.getvalue()
```

**Why `io.BytesIO`**: No disk I/O, no cleanup needed. Create the bytes once at module level; share across all test scenarios.

**Putting it together** — the recommended test script structure when your verifier uses Pattern 8:

```python
ORIGINAL_TABLES = ['ARTIST', 'ALBUM', 'TRACK', ...]  # pre-existing tables in your app's dataset
EMPTY_BASELINE  = {"query_count": 0, "query_names": [], "new_table_names": []}

do_nothing_bytes = make_minimal_odb_fixture(original_tables=ORIGINAL_TABLES)
partial_bytes    = make_minimal_odb_fixture(
    queries={"MyQuery": "SELECT a FROM b JOIN c ON b.id=c.bid GROUP BY a"},
    original_tables=ORIGINAL_TABLES,
)
full_bytes = make_minimal_odb_fixture(
    queries={"MyQuery": "...", "MyQuery2": "..."},
    reports=["Revenue Analysis"],
    new_tables=["TargetTable"],
    insert_data={"TargetTable": [(1, "a"), (2, "b"), (3, "c"), (4, "d")]},
    original_tables=ORIGINAL_TABLES,
)

for label, binary, check_fn in [
    ("DO_NOTHING", do_nothing_bytes, lambda r: r["score"] == 0 and not r["passed"]),
    ("PARTIAL",    partial_bytes,    lambda r: 0 < r["score"] < 70 and not r["passed"]),
    ("FULL",       full_bytes,       lambda r: r["score"] >= 70 and r["passed"]),
]:
    copy_fn = make_path_dispatch_copy(binary, {}, EMPTY_BASELINE)
    result  = verify_my_task([], {"copy_from_env": copy_fn}, {})
    assert check_fn(result), f"[FAIL] {label}: score={result['score']}, feedback={result['feedback']}"
    print(f"[PASS] {label}: score={result['score']}")
```

**When to use this vs. the simpler Lesson 92 mock**:
- Verifier calls `copy_from_env` for ONE JSON file only → use Lesson 92's single-mock approach
- Verifier calls `copy_from_env` for JSON + baseline JSON + binary file → use path-dispatch + binary fixture (this lesson)

**Rule**: When a verifier uses Pattern 8 (independent binary file re-analysis), build a programmatic binary fixture and use a path-dispatch mock so Pattern 8 actually runs in your offline tests. Testing only the fallback path gives incomplete coverage.

---

## Lesson 127: Embedded-Database Applications — Graceful Shutdown Before Parsing, Not Force-Kill

**Context**: Lesson 28 covers applications that buffer config changes in memory and flush them on exit. Lesson 94 covers document-centric apps requiring explicit saves. This lesson addresses a harder variant: applications whose *embedded database engine* requires a structured shutdown sequence to produce a consistent, parseable on-disk file. Force-killing these applications does not merely risk losing in-memory changes — it leaves the database in a write-ahead-log or partially-flushed state that the verifier may be unable to parse correctly.

**What makes embedded databases different from config files**:

| Config files (Lesson 28) | Embedded databases |
|---|---|
| Single file, overwritten atomically on exit | Multi-file (data + log + script + index) or single-file with WAL shadow |
| `pkill + sleep 2` usually sufficient | Must wait for full process exit so engine runs its shutdown procedure |
| Reading stale file → wrong value but parseable | Reading mid-shutdown file → may be empty, truncated, or unparseable |
| One flush step (write to disk) | Two steps: engine-level SHUTDOWN → then OS-level file write |

**Common embedded engines and their shutdown triggers**:

| Engine | Example apps | Required action before parsing |
|---|---|---|
| HSQLDB 1.8 (LibreOffice Base) | LibreOffice Base .odb | Graceful quit → triggers `SHUTDOWN COMPACT` → `database/script` written |
| SQLite WAL mode | Zotero, KeePass, Electron apps | Graceful quit → WAL checkpointed back to `.db` file |
| H2 | Java desktop apps | Graceful quit or `SHUTDOWN` SQL → `.mv.db` consistent |
| Jet/ACE (Microsoft Access) | Microsoft Access .accdb | Graceful close → page cache flushed, `.ldb` lock file removed |

**The failure pattern** — force-kill then parse:

```bash
# WRONG: kills the app mid-operation; database/script not yet written
pkill -9 soffice.bin
sleep 2
python3 -c "import zipfile; zf = zipfile.ZipFile('/home/ga/app.odb'); print(zf.read('database/script'))"
# Returns the state from before the session — all new queries/tables are missing
# Verifier sees score=0 for a fully-completed task
```

**The correct `export_result.sh` pattern**:

```bash
# Step 1: Trigger graceful quit (app runs embedded DB shutdown procedure internally)
WINDOW_ID=$(xdotool search --class "soffice" 2>/dev/null | head -1)
if [ -n "$WINDOW_ID" ]; then
    xdotool windowfocus "$WINDOW_ID"
    sleep 0.5
    xdotool key --clearmodifiers ctrl+s   # save content first (if applicable)
    sleep 1
    xdotool key --clearmodifiers ctrl+q   # graceful quit → triggers SHUTDOWN COMPACT
fi

# Step 2: Wait for FULL process exit — not just window close
# The window disappears first; the DB shutdown runs in the remaining process time
TIMEOUT=35
for i in $(seq 1 $TIMEOUT); do
    pgrep -f "soffice.bin" > /dev/null || break
    sleep 1
done

# Step 3: Force-kill only as last resort
if pgrep -f "soffice.bin" > /dev/null; then
    pkill -9 -f "soffice.bin"
    sleep 2
    echo "WARNING: force-killed — embedded DB shutdown may be incomplete"
fi

# Step 4: Parse the on-disk file (now in a consistent state)
python3 << 'PYEOF'
import zipfile, json
with zipfile.ZipFile("/home/ga/app.odb", "r") as zf:
    script = zf.read("database/script").decode("utf-8", errors="replace")
# ... extract tables, queries, insert counts ...
PYEOF
```

**Key subtlety — wait on the process, not the window**:

The GUI window disappears when the application starts its shutdown sequence. The embedded database engine then runs its `SHUTDOWN COMPACT` / WAL checkpoint in the still-running process. Waiting on window disappearance is not enough — the process may be alive for several more seconds writing the database file.

```bash
# WRONG: window gone ≠ process done
while xdotool search --class "soffice" 2>/dev/null | grep -q .; do sleep 0.5; done
# At this point soffice.bin is still running and writing database/script

# CORRECT: process gone = database fully written
while pgrep -f "soffice.bin" > /dev/null; do sleep 1; done
```

**Baseline recording in `setup_task.sh` follows the same rule**: Parse the database file ONLY while the application is not running (before launch), not while it is open.

```bash
# Correct order:
kill_application       # 1. Kill any running instance (releases file lock)
restore_database_file  # 2. Restore fresh copy
record_baseline_json   # 3. Parse file NOW — app not running, state is consistent
launch_application     # 4. Open app (acquires lock; file is now in use)
wait_for_window        # 5. Wait for UI
```

**Applies to**: Any `export_result.sh` or `setup_task.sh` that reads a file managed by an embedded database engine. Identifiable by the presence of `database/script`, `*.db-wal`, `*.mv.db`, or `*.ldb` files in the application's data directory, or any application whose vendor documentation mentions "embedded HSQLDB", "embedded SQLite", or "in-process database".

**Rule**: For applications with embedded database engines, send a graceful quit signal and wait for the OS process to fully exit before reading the application file. The database's shutdown sequence (SHUTDOWN COMPACT, WAL checkpoint, etc.) only completes on clean exit. Do not force-kill and immediately parse — the on-disk state will be incomplete.

---

## Lesson 128: Helper Functions in task_utils.sh Are Environment-Specific — Read the File Before Calling Anything

**Category**: Setup scripting / Cross-environment portability
**Discovered in**: libreoffice_writer_env task creation (Tasks 5–9)

### What happened

When creating `setup_task.sh` for the five new `libreoffice_writer_env` tasks, the initial implementation called `take_screenshot /tmp/task_start_screenshot.png` — a helper function used in at least one other environment's `task_utils.sh`. The call silently failed because `take_screenshot` is not defined in `libreoffice_writer_env/scripts/task_utils.sh`. No error was raised (the function call was just ignored), so no screenshot was captured and the silent failure went unnoticed until evidence documentation was reviewed.

### Root cause

Each environment ships its own `scripts/task_utils.sh`. These files share a common set of low-level primitives (`wait_for_window`, `kill_application`, etc.) but differ in higher-level conveniences. A function that exists in one environment's utilities is not guaranteed to exist in any other. There is no shared base library that all environments import.

### The rule

**Before calling any helper function in `setup_task.sh`, read the target environment's `task_utils.sh` and confirm the function is defined there.** If it is not, implement the action inline using primitive shell commands.

```bash
# Before writing setup_task.sh for a new environment, always run:
grep -n "^function \|^[a-z_]*()" \
    benchmarks/cua_world/environments/<env_name>/scripts/task_utils.sh

# Then, for every helper you plan to use, verify it appears in the output.
# If it does not, implement the operation inline. Example:
#
# take_screenshot NOT defined? Use ImageMagick directly:
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true
#
# save_baseline NOT defined? Write the inline equivalent instead.
```

### Secondary pitfall: command availability under sudo

Even when a command exists on the system, it may not be available when the setup script runs under root via `sudo -E` (which is how `exec_capture` wraps commands in `QemuApptainerRunner`). Root's `PATH` is often stripped of user-only tool directories.

Concrete example: `scrot` is installed for the desktop user but is not on root's `PATH`. Calling `scrot` in a setup script via `exec_capture` silently fails or raises `command not found`.

**Rule**: Prefer system-wide tools (e.g., ImageMagick's `import`, `ffmpeg`, `python3`) over desktop-session utilities (e.g., `scrot`, `gnome-screenshot`) for operations run as root inside the VM. If you must use a desktop-session utility, test it explicitly with `sudo -E <command>` in a diagnostic step before relying on it.

### Checklist addition

When writing `setup_task.sh` for any new environment, before the first commit:

- [ ] Open `benchmarks/cua_world/environments/<env_name>/scripts/task_utils.sh` and list all defined functions
- [ ] For each function called in your `setup_task.sh`, confirm it appears in that list
- [ ] For each system command called (screenshot, audio capture, etc.), test that `sudo -E <command>` succeeds from within the VM
- [ ] If a helper or command is unavailable, implement inline using only primitives confirmed to work as root

---

## Lesson 129: Source/Output Sheet Architecture for Open-Ended Analytical Tasks

**Category**: Task design / File-based environments
**Applies to**: Any environment where the task deliverable is a structured file (spreadsheet, document, project file, statistical workbook, etc.) and the agent must perform multi-step analysis.

### The Pattern

For hard analytical tasks in file-based environments, design the starting file with two distinct categories of sheets/sections:

1. **Source sheets** (pre-filled): contain the input data the agent must analyze. These are read-only from the agent's perspective — all values are already present at task start.
2. **Output sheets** (blank with headers): contain only row/column labels. The agent must compute and fill in all values.

This separation makes the task unambiguously clear: the agent knows exactly what data is given and exactly where results must go. It also makes the do-nothing test trivially correct — output sheets are blank at start, so any verifier checking for non-empty output cells returns score=0.

```
File structure example (spreadsheet):
  Sheet "RawData"          ← pre-filled: sensor readings, financial figures, patient records
  Sheet "EPAStandards"     ← pre-filled: regulatory reference table (VLOOKUP source)
  Sheet "ComplianceReport" ← BLANK: agent computes exceedance rates, flags, totals
  Sheet "StationSummary"   ← BLANK: agent computes per-station rollups
```

**Why this matters**: If output cells are pre-filled with placeholder values (zeros, "N/A", etc.), an agent that partially completes the task may receive partial credit for values it never changed. Truly blank cells force the agent to write something meaningful to score any points.

**Instructions row pattern**: It is acceptable to include a single instructions/note row at the bottom of each output sheet (below the data area) reminding the agent of the formula logic. This does not contaminate blank-cell checks because verifiers read specific data rows, not footer rows.

### Verifier implication: flexible cell location search

When the task description specifies a layout (e.g., "put results in column E"), the verifier can check exact cell addresses. But when the task leaves layout open, or when different agents may use slightly different row counts, the verifier must **search a range** rather than assuming a fixed address.

```python
# BAD: assumes agent always puts the LDF in exactly cell B7
ldf_value = get_cell_value(workbook, sheet_name, "B7")

# GOOD: scan rows 6-10, columns B-E for a value in the expected range
def scan_for_value(workbook, sheet, row_range, col_list, lo, hi):
    for r in row_range:
        for c in col_list:
            v = get_cell_value(workbook, sheet, f"{c}{r}")
            if v is not None and isinstance(v, (int, float)) and lo <= v <= hi:
                return v
    return None

ldf_value = scan_for_value(workbook, ldf_sheet, range(6, 11), ["B","C","D","E"], 1.3, 1.6)
```

Similarly, use keyword-based sheet name matching (`_find_sheet(names, ["compliance", "report"])`) rather than hardcoding the exact sheet name, since agents may name sheets slightly differently.

**Rule**: For every value the verifier checks, ask: "Could the agent place this in a different cell or name this sheet differently and still be correct?" If yes, use range scanning and keyword matching instead of exact addresses.

---

## Lesson 130: Embed Ground Truth Constants in verifier.py for Deterministic Analytical Tasks

**Category**: Verification design / Data integrity
**Applies to**: Any task where setup_task.sh embeds fixed input data (as Python literals, CSV rows, or SQL inserts), and the expected output is a deterministic mathematical function of that data.

### The Problem

Lesson 77 (GT-in-Setup) solves the case where ground truth must be computed by running a tool (database query, simulation, algorithm) at setup time and saving the result to `/tmp/`. But for purely analytical tasks — where the agent computes ratios, aggregates, or statistical metrics from a fixed dataset — the ground truth is already implied by the embedded data constants. There is no need for a `/tmp/` file, and no risk of a "solved state" contamination.

However, if the verifier hardcodes expected values without documenting how they were derived, it becomes impossible to audit whether those values are correct — especially if the embedded data in `setup_task.sh` is ever modified.

### The Fix

Replicate the input data constants at the top of `verifier.py` and compute expected outputs using the same arithmetic the agent is supposed to perform. The verifier then becomes a self-auditing reference implementation.

```python
# verifier.py — replicate the same data constants from setup_task.sh
PATIENTS = [
    ("E001", "G1", "M", 44500),
    ("E002", "G1", "F", 41200),
    # ... same list as in setup_task.sh
]
BLS_BENCHMARKS = {"G1": 43330, "G2": 72180, "G3": 102240, "G4": 127310}

# Compute expected results from those constants
def _compute_expected_cmi(patients, weights):
    total_weight = sum(weights.get(p[1], 0) for p in patients)
    return total_weight / len(patients)

EXPECTED_CMI = _compute_expected_cmi(PATIENTS, BLS_BENCHMARKS)

# Then check:
if abs(agent_cmi - EXPECTED_CMI) / EXPECTED_CMI < 0.05:
    score += 15
```

**Benefits**:
- A future developer can verify the expected values are correct by reading verifier.py alone.
- If setup_task.sh data is updated, the single diff to verifier.py constants immediately shows whether expected outputs changed.
- The verifier never needs `/tmp/` files — it is self-contained and runnable offline.
- Prevents the class of errors where a manually hardcoded constant (e.g., `EXPECTED_IBNR = 67048`) drifts from the actual data after a data correction.

**When NOT to use this pattern**: If the ground truth requires running a live tool (database query, physics simulation, rendering engine), use the GT-in-Setup pattern (Lesson 77) instead. The constants-in-verifier pattern applies only when the expected output is a closed-form function of the input data.

---

## Lesson 131: Silent task.json Schema Failures — Copy a Working Task as Your Structural Template

**Category**: Task authoring / Framework integration
**Applies to**: Every new task in every environment

### The Problem

`task.json` is parsed as JSON by the framework. JSON parsing succeeds regardless of whether the field names are correct — there is no schema validator that errors on unrecognized or missing keys. A task.json with wrong field names loads silently and produces three distinct but equally silent failure modes:

| Wrong field | What the framework does | Symptom |
|---|---|---|
| `"instruction"` instead of `"description"` | Framework ignores it; agent receives empty prompt | Agent appears "confused" — does nothing or hallucinates a task |
| `"timeout"` at top level instead of `"init": {"timeout_sec": …}` | Framework uses its default timeout | Task may time out too early or too late; no error raised |
| `"reward_type"` at top level instead of inside `"init"` | Verifier never called; `info["verifier"]` is always `{}` | Every test reports `score=None, passed=None` (see Lesson 69) |
| Missing `"hooks"` block | `setup_task.sh` and `export_result.sh` never run | Do-nothing test passes (score=0) for wrong reason; verifier reads stale data |
| Missing `"success"` block | No verifier is registered | All tasks score 0 regardless of agent actions |
| `"env_id"` absent | Task cannot be loaded by `from_config()` | `KeyError` or `FileNotFoundError` at test time |

**Why this is uniquely dangerous**: All other silent-failure patterns in this document (bad SQL, missing chmod, wrong API fields) produce incorrect behavior for a specific task run. A wrong task.json produces silent failures for *every* run of that task, including the do-nothing validation test. The do-nothing test scoring `score=0, passed=False` looks correct even when the cause is "hooks never ran" or "verifier never called."

### The Root Cause

task.json schemas vary between framework versions and even between environments. Documentation describes the intended schema, but:
- Field names may have been renamed in a framework update
- Some environments use `"pre_task_timeout"` instead of the default; others omit it
- The nesting structure (`init` → `timeout_sec`) is not obvious from the field names alone
- The `"description"` field name is counterintuitive — one would naturally write `"instruction"` or `"prompt"` or `"task"`

### The Fix — Always Start From a Working task.json in the Same Environment

Before writing a new task.json, open an existing, *working* task.json from the **same environment directory**:

```bash
# Step 1: Find a working task in the same environment
ls benchmarks/cua_world/environments/<env_name>/tasks/

# Step 2: Read its task.json as your structural template
cat benchmarks/cua_world/environments/<env_name>/tasks/<any_working_task>/task.json
```

Then build your new task.json by **copying the structure** of the working file and changing only the content fields. Do not write task.json from memory, from documentation, or from a task.json you wrote for a *different* environment.

**Minimum required keys to check** (verify each exists at the correct nesting level):

```json
{
    "id":          "<task_name>@<version>",
    "version":     "1.0",
    "env_id":      "<env_name>@<version>",
    "description": "...",          ← NOT "instruction", "prompt", "task", "goal"
    "difficulty":  "very_hard",
    "init": {
        "timeout_sec":  <int>,      ← NOT "timeout" at top level
        "max_steps":    <int>,
        "reward_type":  "sparse"    ← NOT at top level (see Lesson 69)
    },
    "hooks": {
        "pre_task":  "/workspace/tasks/<name>/setup_task.sh",
        "post_task": "/workspace/tasks/<name>/export_result.sh"
    },
    "metadata": { ... },
    "success": {
        "mode": "program",
        "spec": { "program": "verifier.py::<verify_fn_name>" }
    }
}
```

### Fast Validation (Run Before Any Other Testing)

After writing task.json, run this one-liner before booting any VM:

```bash
python3 -c "
import json
with open('benchmarks/cua_world/environments/<env>/tasks/<task>/task.json') as f:
    d = json.load(f)
required = ['id', 'version', 'env_id', 'description', 'difficulty', 'init', 'hooks', 'success']
missing = [k for k in required if k not in d]
init_keys = ['timeout_sec', 'max_steps', 'reward_type']
missing_init = [k for k in init_keys if k not in d.get('init', {})]
hook_keys = ['pre_task', 'post_task']
missing_hooks = [k for k in hook_keys if k not in d.get('hooks', {})]
print('Missing top-level:', missing)
print('Missing init keys:', missing_init)
print('Missing hook keys:', missing_hooks)
print('reward_type value:', d.get('init', {}).get('reward_type', 'MISSING'))
"
```

All three lists must be empty and `reward_type` must be `sparse` before proceeding to any other work.

### Also Check: Verify Function Name Must Match

The `success.spec.program` value must exactly match the function name defined in `verifier.py`. A typo produces a silent `AttributeError` at verification time that may be caught and reported as score=0 rather than a framework error.

```bash
# Check the function name is correct
grep "^def verify_" benchmarks/cua_world/environments/<env>/tasks/<task>/verifier.py
# Output should match the function name in task.json success.spec.program
```

**Rule**: Never write task.json from scratch or from documentation alone. Copy the structure of a working task.json from the same environment, change content fields, and run the fast-validation script before any VM work. The `description` field is the canonical agent-visible field — no other name is recognized.

---

## Lesson 132: Read-Only Reference Apps — The Current Screen IS the Verification Artifact

Most verification patterns assume the app **writes something** as a side effect of completing the task: a database row, a file on disk, a filled-in form field, a submitted entry. For **read-only reference apps** (medical databases, calculators, documentation browsers, reference guides), this assumption breaks — the app writes nothing. The only observable signal is the **current state of the UI when the agent stops**.

### What Changes

| App type | Verification artifact | How to collect it |
|----------|-----------------------|-------------------|
| Database-write apps | Table row / JSON export | Query DB or read export file |
| File-creation apps | File on disk | `copy_from_env` to pull the file |
| Form-submit apps | Server-side confirmation | Network call or confirmation text |
| **Read-only reference apps** | **Current screen contents (accessibility tree)** | **`uiautomator dump` at post-task time** |

### Implication for export_result.sh

For read-only reference apps, `export_result.sh` is not exporting anything the app "created." It is **snapshotting the current UI state** and converting it into a structured result JSON. The script's job is:

1. Run `uiautomator dump` to capture the live accessibility tree.
2. Grep the XML for the specific text strings that indicate the correct end screen.
3. Write a result JSON with boolean flags (found / not-found) for each expected element.

```sh
#!/system/bin/sh
uiautomator dump /sdcard/task_dump.xml
sleep 2

DRUG_A=$(grep -qi "DrugName" /sdcard/task_dump.xml && echo "true" || echo "false")
SEVERITY=$(grep -qi "Do Not Co-administer" /sdcard/task_dump.xml && echo "true" || echo "false")

cat > /sdcard/task_result.json << EOF
{
  "drug_a_found": $DRUG_A,
  "severity_found": $SEVERITY
}
EOF
```

### Implication for Task Design

Because only the **final screen** is captured, the task must define a clear **target end screen** (e.g., "Interaction Details page for Drug A + Drug B"). Partial navigation — reaching a results list but not drilling into the details page — should produce a lower score than full navigation. Build this gradient into your scoring criteria.

### Relationship to Lesson 27

Lesson 27 covers apps with "no structured output" where the workaround is a **written report file** the agent creates explicitly. Read-only reference apps are different: the output IS structured, it just lives in the UI rather than on disk. Do not use the written-report workaround for reference apps; use `uiautomator dump` instead.

---

## Lesson 133: Multi-Select Feature Verification — Simultaneous Visibility Proves Batch Operation

When a task tests a **multi-select or batch-selection feature** (adding multiple items to a basket, selecting multiple filters simultaneously, queuing multiple queries at once), the verifier must check for **simultaneous presence** of all selected items in the UI at the same moment — not just that each item appeared at some point during the session.

### Why Sequential Selection Looks the Same as Multi-Select to a Naive Verifier

If your verifier only checks "was Drug A visible at some point AND was Drug B visible at some point," an agent that searched Drug A alone, noted the result, backed out, and then searched Drug B alone would pass — even though it never used the multi-select feature. This defeats the purpose of the task.

### The Fix: Check Simultaneous Presence in a Single Snapshot

```python
# In verifier.py — captures one snapshot and checks for both items together
both_simultaneously = result.get('item_a_found') and result.get('item_b_found')
```

The key is that `item_a_found` and `item_b_found` are both extracted from **the same `uiautomator dump`** captured at post-task time. If both are `True` in the same snapshot, the agent left the session with both selected simultaneously — proving multi-select usage.

### Scoring Structure for Multi-Select Tasks

Weight the simultaneous-presence criterion higher than the individual presence criteria, and make it a **superset check** (not additive). A good structure:

```
individual_item_a_visible:    20 points  (was A ever shown?)
individual_item_b_visible:    20 points  (was B ever shown?)
both_simultaneously:          20 points  (both in final snapshot — proves multi-select)
```

Set the pass threshold high enough that achieving `both_simultaneously` (40 + 20 = 60 from the two individual + simultaneous) is required for passing. This forces agents to demonstrate the batch feature, not just visit each screen sequentially.

### General Principle

Any task testing a **batch, multi-select, compare, or basket** feature should include a simultaneous-visibility criterion drawn from a **single terminal snapshot**. The criterion should be worth enough points that skipping it prevents passing.

---

## Lesson 134: Navigation Depth as a Calibrated Difficulty Lever for Hierarchical Apps

For apps organized as hierarchical menus or drill-down browsers (reference databases, settings trees, documentation systems, product catalogs), the natural difficulty axis is **navigation depth** — how many screens the agent must traverse and how much domain knowledge is needed to choose the correct path at each branch.

### Difficulty Gradient by Depth

| Difficulty | Typical depth | Agent challenge |
|------------|---------------|-----------------|
| Easy | 1–2 screens | Open the app, find the main list, tap one item |
| Medium | 2–3 screens | Navigate through a category, apply a filter, view a result |
| Hard | 3–4 screens | Multi-step search with domain-specific criteria, drill into sub-details |
| Very Hard | 4+ screens or multi-feature | Combine features (multi-select + drill-down), or require pharmacological / domain reasoning to identify the correct target |

### How to Use This When Designing Tasks

1. **Choose the target screen first**, then count how many taps from the home screen it requires. That count is a rough proxy for difficulty.
2. **Add domain reasoning as a multiplier.** If the agent must know that "enzyme induction" ≠ "enzyme inhibition" to pick the right co-medication from a list, this raises effective difficulty by a full level even if screen depth is the same.
3. **Vary the foils.** For hard tasks, include co-medications that are plausible but wrong (similar drug class, or similar mechanism name). The agent must read and reason, not just pattern-match on the first hit.
4. **Keep the path unambiguous once the right target is identified.** Hard difficulty should come from domain knowledge and multi-step navigation, not from UI ambiguity or layout inconsistency. If the UI is confusing, that is a task quality problem, not a difficulty feature.

### Implications for Scoring

Navigation depth directly maps to scoring criteria: each major navigation milestone (reached the search screen, entered the drug name, viewed the results list, drilled into the interaction details) should be a separate scored criterion. This gives partial credit to agents that made progress without completing the full path, and makes the score a meaningful measure of how far the agent got.

### When Not to Use Depth as the Lever

If the target information is available at a shallow depth but behind a non-obvious UI affordance (e.g., a hidden tap target, a gesture-only control), that is **UI discoverability difficulty**, not navigation depth difficulty. These are less reliable as difficulty levers because they depend on UI implementation details that may change across app versions, and they penalize agents unfairly when the UI is genuinely ambiguous.

---

## Lesson 135: MySQL/MariaDB `-N` Flag Outputs SQL NULL as the Literal String "NULL"

When querying a MySQL/MariaDB database with `mysql -N -e "SELECT col FROM table"`, the `-N` flag suppresses column headers but does **not** convert SQL NULL into an empty string. Instead, SQL NULL is printed as the literal four-character string `NULL`.

### Why This Breaks Bash Checks

The standard bash "is this variable empty?" check (`[ -n "$VAR" ]`) evaluates to **true** for the string `"NULL"`, so a column that contains SQL NULL will appear to have a non-empty, non-trivial value:

```bash
VAL=$(mysql -N -e "SELECT grelevance FROM lime_groups WHERE gid=5")
# VAL is now the string "NULL" — not an empty string

if [ -n "$VAL" ] && [ "$VAL" != "1" ]; then
    echo "HAS CONDITION"   # ← WRONG: fires even when DB column is NULL
fi
```

### The Fix

Always add an explicit `!= "NULL"` guard alongside every empty-string check when reading from MySQL with `-N`:

```bash
if [ -n "$VAL" ] && [ "$VAL" != "1" ] && [ "$VAL" != "NULL" ]; then
    echo "HAS CONDITION"   # ← Correct
fi
```

### General Principle

Any time you read a nullable database column into a bash variable via `mysql -N`, treat both `""` (empty string) and `"NULL"` (literal) as "not set." This applies to any MySQL/MariaDB query regardless of the application or environment.

---

## Lesson 136: Web Server HTTP Readiness ≠ Application API Readiness

When a web application starts inside Docker (or any container/service manager), the lifecycle has at least two distinct phases:

1. **Web server starts** — the HTTP port opens and returns 200/302 to simple GET requests.
2. **Application initializes** — the app runs its first-time setup (DB schema creation, cache warm-up, plugin loading, config migration). Only after this phase is the application's API usable.

A readiness check that only tests HTTP status (e.g., `curl -s -o /dev/null -w "%{http_code}" http://localhost/`) can pass during phase 1, while the application is still mid-initialization in phase 2. Any setup script that proceeds after the HTTP check may then call the application's API and receive errors or timeouts.

### Compounding Factor: APIs Disabled by Default

Many web applications (LimeSurvey, Redmine, various CMS systems) ship with their REST or RPC API **disabled by default**. Even after full initialization, API calls will fail until the feature is explicitly enabled — typically via a database write, config file edit, or admin UI toggle.

### The Fix: Test the Actual API Endpoint

Add a readiness loop that calls the real API endpoint (not just the HTTP root):

```bash
wait_for_api() {
    local timeout=600
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # Replace with the actual API health-check or authentication call
        RESULT=$(python3 - << 'PYEOF' 2>/dev/null
import json, urllib.request
try:
    data = json.dumps({"method": "get_session_key", "params": ["admin", "pass"], "id": 1}).encode()
    req = urllib.request.Request("http://localhost/api/remotecontrol", data=data,
                                  headers={"Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=10).read())
    if r.get("result") and "error" not in str(r["result"]).lower():
        print("ready")
except Exception:
    pass
PYEOF
)
        if [ "$RESULT" = "ready" ]; then
            echo "API ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: API not ready after ${timeout}s"
    return 1
}
wait_for_api || true
```

### Enable the API Explicitly Before Waiting

If the application requires the API to be enabled via configuration, do that **before** the readiness loop so the loop actually has a chance to succeed:

```bash
# Example: enable via DB (retry until schema exists)
for i in $(seq 1 12); do
    if db_client -e "INSERT INTO settings (key, val) VALUES ('api_enabled', '1') ON DUPLICATE KEY UPDATE val='1';" 2>/dev/null; then
        echo "API enabled"
        break
    fi
    sleep 5
done
```

### Where to Put This

Put the API-enable SQL and the API readiness loop in the **post_start** (environment-level) setup script, not in the per-task pre_task script. The environment should be fully operational before any task hook runs, so all tasks can rely on the API being available without duplicating the wait logic.

---

## Lesson 137: Python `sys.exit()` Inside a Bash Heredoc Is Silently Ignored Without Explicit `$?` Capture

When you run a Python script inline via a bash heredoc (`python3 << 'PYEOF' ... PYEOF`), the exit code of the Python process is available in `$?` immediately after the `PYEOF` line — but only if you capture it before the next command runs. Without `set -e`, bash **does not abort** on a non-zero exit code, so a `sys.exit(1)` inside the heredoc causes the Python process to fail without stopping the surrounding bash script.

### Symptom

The setup script prints a Python-level error message ("ERROR: API not responding") and then continues on to declare "Setup Complete" — even though the critical operation (e.g., creating a survey, importing data) never happened. The environment appears ready but is actually empty.

### The Fix

Always capture `$?` immediately after every heredoc block and gate on it:

```bash
python3 << 'PYEOF'
import sys
# ... do work ...
if not success:
    print("ERROR: setup failed")
    sys.exit(1)
PYEOF
PYTHON_EXIT=$?
if [ "$PYTHON_EXIT" -ne 0 ]; then
    echo "ERROR: Setup script failed (exit $PYTHON_EXIT)"
    exit 1
fi
```

### If the Script Uses `set -e`

With `set -e`, a non-zero heredoc exit code will abort the script automatically — **but only if the heredoc is not inside a compound command** (e.g., `if ...; then` or `|| true` suppress `set -e`). The explicit `$?` capture is safer and more readable than relying on `set -e` behavior, which can be suppressed in ways that are easy to overlook.

### General Principle

Treat every `python3 << 'PYEOF'` block as an external subprocess whose success must be verified. Never assume it succeeded just because the bash script continued past it.

---

## Lesson 138: Docker Web Application First-Time Initialization Is Not Atomic with Container Start

Docker containers for web applications (CMS, survey tools, project management systems, etc.) commonly perform **first-time initialization** — creating database schemas, running migrations, seeding default data, installing plugins — the first time the application starts. This initialization:

- Happens **after** the container process starts (so `docker-compose up` returns immediately)
- Happens **after** the web server begins accepting connections (so HTTP health checks pass)
- May take **several minutes** depending on the complexity of the schema and the speed of the database container
- Is **not reflected** in the Docker container health status until it completes (the container may show `Up (health: starting)` throughout)

### Practical Impact for Task Setup Scripts

A pre_task setup script that runs immediately after post_start completes may encounter the application in a partially initialized state:

- Database tables may not exist yet → SQL queries fail silently
- API endpoints may return 500 or malformed JSON
- Admin features (user creation, survey import, config change) may silently no-op

The result is that the script finishes with "success" output but leaves the environment in the wrong state (empty database, missing surveys, unconfigured settings).

### The Fix

In the post_start hook, add a readiness check that tests an **application-level operation** (see Lesson 136), not just HTTP connectivity. The post_start hook should not return until the application is truly usable. This protects all pre_task scripts for all tasks without each task needing its own wait logic.

### Checkpointing Consideration

If your environment uses VM checkpoints (pre_start level), first-time initialization will run from scratch every time a test boots from the checkpoint. This means the wait time is incurred on every run. Design the readiness check to be fast when initialization has already completed (e.g., the API responds immediately on a warm system) and patient when it has not (e.g., retry for up to 10 minutes on a cold first-boot).

---

## Lesson 139: Dual-Source Verification — Collect from Both SQL and REST API, Take Best in Verifier

When the target application exposes both a SQL database and a REST API, collect the verification data from **both** sources in `export_result.sh`, then take the best (max / logical-OR) in `verifier.py`. This pattern handles the common case where one source silently fails (table name wrong for this version, API auth not set up, endpoint not available) while the other succeeds.

### Pattern in `export_result.sh`

```bash
# SQL attempt — may return empty if this version uses a different table name
COUNT_SQL=$(app_db_exec "SELECT COUNT(*) FROM feature_v1 WHERE LOWER(name) LIKE '%target%';" 2>/dev/null | tr -d '[:space:]')
if [ -z "$COUNT_SQL" ]; then
    COUNT_SQL=$(app_db_exec "SELECT COUNT(*) FROM feature_v2 WHERE LOWER(name) LIKE '%target%';" 2>/dev/null | tr -d '[:space:]')
fi

# API attempt — more stable across application versions
COUNT_API=$(curl -sk -H "Authorization: Bearer $API_KEY" "https://localhost:8080/api/v3/features" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = sum(1 for f in data.get('features', []) if 'target' in f.get('name', '').lower())
print(count)
" 2>/dev/null)

# Store both — verifier picks the winner
cat > "$RESULT_FILE" << EOF
{
  "count_sql": ${COUNT_SQL:-0},
  "count_api": ${COUNT_API:-0}
}
EOF
```

### Pattern in `verifier.py`

```python
# Trust whichever source returned the higher count
count = max(data.get('count_sql', 0), data.get('count_api', 0))
found = count > 0
```

For boolean flags: `found = data.get('found_sql', False) or data.get('found_api', False)`.

### When to Apply

Any web application where (a) the database schema is not publicly documented or varies by version, and (b) the application exposes an official REST API. Examples: ManageEngine ServiceDesk, ServiceNow, Redmine, Zammad, OTRS.

**Do not apply** when you have confirmed knowledge of the exact table name from existing `task_utils.sh`, direct database exploration, or official schema documentation. Unnecessary dual-sourcing adds verbosity without benefit.

---

## Lesson 140: REST API Is the Primary Verification Source When DB Table Names Are Version-Dependent

For commercial or actively-versioned web applications, database table names for secondary features (Problem Management, Change Management, Group Configuration, Knowledge Base, Request Templates) frequently change across major and minor versions. The REST API, by contrast, is versioned explicitly and stable within a version family.

**Design rule**: Use SQL as your **primary** source only for tables you have **confirmed** exist in this deployment — by finding them in `task_utils.sh`, existing setup scripts, or direct exploration. For everything else, use the REST API as primary and SQL as a defensive fallback.

### Confirming a Table Name Safely

```bash
# Check if the table exists before querying it
TABLE_EXISTS=$(app_db_exec "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='feature_table';" 2>/dev/null | tr -d '[:space:]')
if [ "${TABLE_EXISTS:-0}" = "1" ]; then
    RESULT=$(app_db_exec "SELECT COUNT(*) FROM feature_table WHERE ...;" 2>/dev/null)
fi
```

### Multiple Candidate Table Names

When you know a feature exists but not the exact table name, try candidates in priority order:

```bash
for TABLE in table_v1 table_v2 table_legacy; do
    RESULT=$(app_db_exec "SELECT COUNT(*) FROM $TABLE WHERE ...;" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$RESULT" ] && [ "$RESULT" != "0" ]; then
        break
    fi
done
```

### Why This Matters for Verifier Robustness

If a verifier relies on a single SQL query against a wrong table name, it silently returns 0 and the agent scores 0 even though it completed the task correctly. Using the REST API as primary (or dual-sourcing per Lesson 139) prevents this class of false-negative failures.

---

## Lesson 141: Wrong-Target Gate Must Check the Enabling Prerequisite, Not a Leaf Criterion

The wrong-target gate — the early-exit that returns `score=0` before evaluating any criteria — should check for the **enabling prerequisite**: the one thing that all other scored criteria logically depend on. If you gate on a downstream "leaf" criterion, you will incorrectly zero-score agents that did meaningful partial work.

### The Problem with Leaf-Criterion Gates

Suppose a task requires: create Group → add Technician → route Ticket to Group. If you gate on "ticket routed":
- Agent creates the group but doesn't finish routing → gate fires → score=0, **wrong** — the agent should get partial credit for creating the group.

### The Correct Pattern

Gate on the enabling prerequisite — the thing that makes all other criteria possible:

```python
# CORRECT: gate on the enabling prerequisite
if not data.get('group_created'):
    return {"score": 0, "passed": False, "feedback": "Core deliverable (group) not found."}

# Now score downstream criteria with partial credit
score += 20 if data.get('technician_created') else 0
score += 10 if data.get('ticket_routed') else 0
```

### For Tasks with Independent Parallel Deliverables

When deliverables don't form a dependency chain, gate on **none of them being present**:

```python
# CORRECT: agent must have done at least one core thing
if not data.get('feature_a') and not data.get('feature_b'):
    return {"score": 0, ...}
```

This ensures do-nothing returns 0 without incorrectly penalizing partially-complete work.

### Identifying the Enabling Prerequisite

Ask: *"What is the one thing that must exist before any other criterion can be met?"*
- For hierarchical deliverables (department → category → subcategory): gate on the top-level item.
- For group-with-members tasks: gate on the group, not the members.
- For linking tasks (link incident to change): gate on the change existing, not the link.

---

## Lesson 142: For Multi-Module Web Applications, Navigation Depth Across Modules Is the Primary Difficulty Axis

In complex web applications with many distinct modules — ITSM platforms, LMS systems, CRM, ERP, project management tools — task difficulty scales primarily with the **number of distinct application sections** the agent must visit and use, not the number of individual UI actions.

| Modules visited | Typical difficulty |
|----------------|-------------------|
| 1 module, any number of actions | Easy to Medium |
| 2–3 distinct modules | Medium to Hard |
| 4+ distinct modules or admin sections | Hard to Very Hard |

A task requiring the agent to visit the Requests module, Problem Management module, and Admin > Groups panel is significantly harder than a task requiring 10 actions all within the same Requests list — even if the per-action complexity is identical. The difficulty comes from **discovery**: the agent must know that the feature exists, find where it is in the navigation, understand its UI independently, and connect it back to the original task.

### Design Implication for Very Hard Tasks

Deliberately choose deliverables from different application areas. For ITSM-style platforms: span Requests, Problems/Changes, Admin configuration (Groups, Categories, Templates), and Solutions/Knowledge Base. Don't cluster deliverables in one area.

### Verification Implication

Export scripts for multi-section tasks must query multiple places — often with different schemas and API endpoints for each section. Resist the temptation to consolidate. Each module may have completely different table names, API resources, and auth requirements.

### Contrast with Single-Module Tasks

A task like "update 10 field values on a single record" may feel like more work but is actually easier because the agent stays in one place, learns the UI once, and repeats the same action pattern. Navigation to a new section resets the agent's context and requires re-discovery. Use this asymmetry deliberately when calibrating difficulty.

---

## Lesson 143: MySQL/MariaDB Strict Mode — NOT NULL Columns Without Defaults Silently Kill ALL Inserts

**The Problem**: When inserting into a MySQL/MariaDB table, omitting a column that is `NOT NULL` with no default value causes the entire `INSERT` to fail. Because `setup_task.sh` almost always redirects stderr (`2>/dev/null`), this failure is completely invisible — the script continues past the insert and prints "Setup complete" while zero rows were created.

This is distinct from Lesson 36 (referencing a non-existent column) and from the UNIQUE constraint lesson:

| Failure mode | Which rows fail | Visible when |
|---|---|---|
| Non-existent column name (Lesson 36) | All (syntax error) | Always, unless redirected |
| UNIQUE constraint on NULL (see UNIQUE lesson) | All after the first | Only if output not redirected |
| **NOT NULL / no default (this lesson)** | **All** | **Only if output not redirected** |

**How it happens**: MySQL 5.7+ and MariaDB 10+ default to `STRICT_TRANS_TABLES` mode. In strict mode, inserting a row that omits a NOT NULL / no-default column is a hard error (`ERROR 1364: Field 'X' doesn't have a default value`). With `2>/dev/null`, this error is swallowed, and no row is written.

```bash
# This silently creates ZERO rows if matomo_site has a NOT NULL column you didn't include:
matomo_query "INSERT INTO matomo_site (name, main_url, timezone, currency ...)
              VALUES ('My Site', 'https://example.com', 'UTC', 'USD')" 2>/dev/null
# ^ prints nothing, exits 0, but the site was never created

# The invisible error (visible without 2>/dev/null):
# ERROR 1364 (HY000): Field 'excluded_referrers' doesn't have a default value
```

**How to detect**: Inspect the schema *before* writing inserts:

```bash
# MySQL/MariaDB:
docker exec my-db mysql -u user -ppass db -e "SHOW CREATE TABLE tablename\G"
# or
docker exec my-db mysql -u user -ppass db -e "DESCRIBE tablename"
# Look for: "NO" in the "Null" column AND empty string in "Default" column
# These are the columns you MUST include in every INSERT.
```

**How to verify inserts succeeded**: Always follow any INSERT block in `setup_task.sh` with a SELECT to confirm the row exists:

```bash
SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE name='My Site' LIMIT 1" 2>/dev/null)
if [ -z "$SITE_ID" ]; then
    echo "ERROR: INSERT failed — site was not created!" >&2
    exit 1
fi
echo "Site created with ID: $SITE_ID"
echo "$SITE_ID" > /tmp/my_site_id
```

**The fix**: Include every NOT NULL / no-default column in all INSERT statements, even if the value is an empty string:

```bash
# WRONG (omits excluded_referrers which is NOT NULL with no default)
INSERT INTO matomo_site (..., excluded_user_agents, `group`, ...)
VALUES (..., '', '', ...)

# CORRECT (excluded_referrers included with empty string value)
INSERT INTO matomo_site (..., excluded_user_agents, excluded_referrers, `group`, ...)
VALUES (..., '', '', '', ...)
```

**Applies to**: Any `setup_task.sh` that seeds rows into a MySQL/MariaDB application database. Especially common with web analytics, e-commerce, and CRM applications (Matomo, WordPress, Magento, OpenCart, SugarCRM) where schema versions may add new NOT NULL columns between releases. The problem is amplified by application upgrades — a column that existed with a default in version 4.x may have had its default removed or a new NOT NULL column added in version 5.x.

---

## Lesson 144: Workspace Specification Documents as a Difficulty Multiplier

**The Pattern**: For hard/very_hard tasks, place a specification or requirements document inside the task's workspace directory (e.g., `/workspace/tasks/<task_name>/spec.txt`). The task description tells the agent only that a specification exists — the agent must read it to determine exactly what to build.

```
benchmarks/cua_world/environments/<env_name>/tasks/<task_name>/
├── task.json       ← description: "Read funnel_spec.txt and implement..."
├── setup_task.sh
├── export_result.sh
├── verifier.py
└── funnel_spec.txt  ← the actual requirements the agent must implement
```

**Why this makes tasks harder**:

1. **Hides expected values from the task description** — The agent cannot shortcut by looking at `task.json` metadata or the task prompt; it must navigate to the file and read it
2. **Tests document-reading capability** — A capable agent must find, open, parse, and act on an instruction document, which is a realistic professional workflow
3. **Prevents prompt injection from task descriptions** — When the task says "read the spec", the verifier can check that the spec's values (not the description's values) were implemented
4. **Natural realism** — Real professionals work from requirements documents, tickets, specs, and briefs — not from detailed step-by-step instructions

**How to implement**:

In `task.json` description, reference the spec but do not reveal its contents:
```json
{
  "description": "Read the file at /workspace/tasks/spec_based_goals/funnel_spec.txt and implement exactly the conversion goals specified there for the SportsFit Shop site."
}
```

In `funnel_spec.txt`, write the actual requirements in natural professional language:
```
CONVERSION GOALS — SportsFit Shop

Goal 1: Product Page View
  - Match: URL contains /products/
  - Type: URL destination

Goal 2: Purchase Confirmation
  - Match: URL exactly equals /order/thank-you
  - Type: URL destination (exact match only)
```

In `verifier.py`, check the SPEC's values, not the task description:
```python
# Check against spec values — agent had to read the file to know these
expected = {
    'product_page_view': {'pattern_type': 'contains', 'pattern': '/products/'},
    'purchase_confirmation': {'pattern_type': 'exact', 'pattern': '/order/thank-you'},
}
```

**Design guidelines**:
- Keep the spec file terse and professional — not a tutorial, not step-by-step instructions. It should read like an actual requirements document, not a hint
- Include deliberate precision requirements that the agent must get right (e.g., "exact match" vs "contains") — these discriminate between careful reading and guessing
- Mount the task directory read-only in `env.json` (already the standard pattern for Matomo and similar environments), so the spec is accessible at `/workspace/tasks/<task_name>/` automatically
- The verifier does NOT need to `copy_from_env` the spec — it lives locally on the host filesystem in `benchmarks/cua_world/environments/<env_name>/tasks/<task_name>/`, so the verifier can read it directly if needed

**When to use**: Any task where the requirements can be expressed as a formal specification (conversion goals, schema definitions, configuration rules, data transformation requirements, report formats). Especially powerful for "implement from requirements" tasks where the agent's job is to translate a document into application configuration.

---

## Lesson 145: Session-Cookie Authentication for Enterprise Web Application REST APIs

**The context**: Many enterprise web applications (SIEM platforms, ITSM tools, ERP systems, network management suites) use HTML-form session authentication rather than API keys or Bearer tokens. Their internal REST APIs are only accessible after posting credentials to a login endpoint that sets a session cookie. Unlike Bearer token auth (where you embed a static token in headers), session-cookie auth requires maintaining a live cookie jar across all calls.

**Why this matters for task scripts**: `setup_task.sh` and `export_result.sh` often need to call the application's REST API to seed state or collect verification data. If the API rejects unauthenticated requests (HTTP 401/403) silently and the script doesn't detect the failure, setup appears to succeed while no state was actually created.

**The pattern**:

```bash
# In setup_task.sh or export_result.sh
COOKIE_JAR="/tmp/app_session_cookies.txt"
rm -f "$COOKIE_JAR"   # Always start with a fresh jar

# Step 1: Log in — POST credentials to the form login endpoint
# The endpoint path varies by application (j_security_check, login.do, auth/login, etc.)
LOGIN_CODE=$(curl -s \
    -c "$COOKIE_JAR" \       # Write session cookies to jar
    -b "$COOKIE_JAR" \       # Send any existing cookies (needed for CSRF token roundtrip)
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "j_username=admin&j_password=admin&Submit=Login" \
    "http://localhost:8080/app/j_security_check" \
    -o /dev/null -w "%{http_code}" 2>/dev/null)

if [ "$LOGIN_CODE" != "200" ] && [ "$LOGIN_CODE" != "302" ] && [ "$LOGIN_CODE" != "303" ]; then
    echo "WARNING: Login returned HTTP $LOGIN_CODE — API calls may fail"
fi

# Step 2: All subsequent API calls reuse the session
API_RESPONSE=$(curl -s \
    -c "$COOKIE_JAR" \
    -b "$COOKIE_JAR" \
    -H "Content-Type: application/json" \
    "http://localhost:8080/app/api/v1/resource" 2>/dev/null)

echo "$API_RESPONSE" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data)" 2>/dev/null
```

**Key rules**:

1. **Always use both `-c` and `-b` on every call**, including the initial login. Some applications set a CSRF token cookie on the first GET to the login page, then require it echoed back during the POST.

2. **Delete the cookie jar before use** (`rm -f "$COOKIE_JAR"`). A stale session from a previous test run will cause the login POST to be treated as a session refresh, which may fail silently with 403.

3. **Check the login HTTP code**. Form login responses are typically 302 (redirect to authenticated homepage) or 200 (JSON confirmation). A 200 response body of `{"error":"invalid credentials"}` is a silent failure — checking the status code alone is not sufficient for all apps. If the app returns JSON, also check the body.

4. **Use `/tmp/` for the cookie jar**. The jar must be writable inside the VM. Never hardcode a path in `/home/` that may not exist.

5. **Sessions expire**. If `setup_task.sh` runs for several minutes, re-authenticate before the export block. For short scripts (< 5 minutes), a single login at the start is sufficient.

6. **Discover the login endpoint**: check existing `task_utils.sh` for the environment first (`ela_login`, `app_login`, etc.); then try `/app/j_security_check`, `/login`, `/auth/login`, `/api/v1/auth`, or consult the application's documentation.

**How to detect silent auth failures**: After the login block, make one test API call to a known-working read endpoint (e.g., list resources) and verify the response is non-empty and non-error before proceeding with write calls. If the test call returns `{"error":"Unauthorized"}` or an HTML redirect to the login page, the session wasn't established.

**Applies to**: Any web-application environment where `setup_task.sh` or `export_result.sh` needs to call the application's internal REST API — SIEM platforms (ManageEngine, Splunk, Graylog), ITSM tools (ManageEngine ServiceDesk, Zammad, osTicket), ERP systems, network management software (SolarWinds, PRTG), and any Java EE / Jakarta EE application using `j_security_check`.

---

## Lesson 146: Record Baseline AFTER Seeding the Problem State, Not Before

**The Problem**: The phrase "record baseline before the agent starts" is sometimes misread as "record baseline at the very beginning of `setup_task.sh`." This is wrong for tasks where the setup script's job is to *create the broken or wrong state* that the agent must fix. Recording the baseline before seeding the problem state causes the seeded entities themselves to appear as "new agent work" in the verifier — and the do-nothing test then returns a non-zero score.

**The two setup archetypes**:

| Setup type | What setup does | When to record baseline |
|------------|----------------|------------------------|
| **Target seeding** | Creates the data the agent must *modify* (e.g., adds a patient record the agent must update) | Before or after creating target — target itself is the subject of the task |
| **Problem-state seeding** | Creates the *wrong/broken state* the agent must *fix* (e.g., creates overprivileged accounts, misconfigured alerts, erroneous records) | **After** all broken state is created |

**What breaks when you record baseline too early**:

```bash
# WRONG ORDER (for problem-state tasks):
INITIAL_COUNT=$(query_count)        # Records X
echo "$INITIAL_COUNT" > /tmp/initial_count

# Now create the problem state the agent must fix:
create_overprivileged_user contractor01
create_overprivileged_user it-support
# DB now has X+2 accounts

# Agent does nothing.
# export_result.sh: current_count = X+2, initial_count = X → new_count = 2
# Verifier: "2 new accounts created" → awards partial credit → score > 0
# do-nothing test FAILS
```

```bash
# CORRECT ORDER (for problem-state tasks):
# First, seed all broken state:
create_overprivileged_user contractor01
create_overprivileged_user it-support
# DB now has X+2 accounts

# Then record baseline — this captures the state the agent inherits:
INITIAL_COUNT=$(query_count)        # Records X+2
echo "$INITIAL_COUNT" > /tmp/initial_count

# Agent does nothing.
# export_result.sh: current_count = X+2, initial_count = X+2 → new_count = 0
# Verifier: "0 new accounts" → score = 0
# do-nothing test PASSES ✓
```

**The mental model**: Baseline = "the state of the world at the moment the agent gains control" = the state at the **end** of `setup_task.sh`, after ALL setup actions have completed. The baseline captures the starting line for the agent, which necessarily includes whatever problem state was seeded.

**How to identify which archetype your task uses**:

- If setup is just seeding a fresh, clean target entity and the agent must *build on it* → record baseline wherever is convenient; timing usually doesn't matter.
- If setup creates *erroneous, overprivileged, misconfigured, or wrong* state → record baseline at the **very end** of setup, after all seeding is complete.
- If setup creates BOTH clean target data AND a problem state → record baseline at the end, after both.

**Applies to**: Any task of the "remediation", "hardening", "audit and fix", "clean up after misconfiguration" type — common in SIEM, ITSM, EHR audit, security tool, and database administration environments. If the task description says things like "downgrade", "remove", "fix", "remediate", "correct", or "undo", it is almost certainly a problem-state task and this rule applies.

---

## Lesson 147: HTMX and Hypermedia Frameworks Return 200 + Custom Header — Not 3xx — After Entity Creation

**The Problem**: Modern single-page and hypermedia-driven web applications (HTMX, Turbo, PJAX, htmx.org-based frameworks) do not issue HTTP 3xx redirects after successful form POSTs. Instead, they return `HTTP 200` with a custom response header carrying the redirect URL (e.g., `HX-Redirect`, `Turbo-Location`, `X-PJAX-URL`). If your setup script creates an entity via POST and tries to extract the new entity's URL from an HTTP redirect, it will get no redirect — and the entity ID is silently lost.

**What breaks**:
```python
# WRONG: relying on HTTP 3xx Location header
resp = s.post(url, data=payload, allow_redirects=False)
entity_url = resp.headers.get("Location", "")  # empty — no 3xx issued

# Also wrong: following redirects finds nothing new
resp = s.post(url, data=payload, allow_redirects=True)
# resp.url is still the original POST URL, not the entity view URL
```

**The Fix**: After a successful entity-creation POST, check for the framework's specific redirect header:
```python
# HTMX:
entity_url = resp.headers.get("HX-Redirect", "")

# Turbo (Hotwire):
entity_url = resp.headers.get("Turbo-Location", "")

# PJAX:
entity_url = resp.headers.get("X-PJAX-URL", "")
```

The entity URL in this header is the canonical view URL for the newly created entity. Parse the entity's ID from it.

**How to discover which header your app uses**: Print `dict(resp.headers)` after a test POST from a Python session, or watch the Network tab in the browser's DevTools and look for 200 responses with non-standard headers after form submissions.

**Also note**: These frameworks may return `HTTP 422` for validation errors rather than `HTTP 400` or `HTTP 200` with an error in the body. Check `resp.status_code` and the response body to distinguish success from validation failure.

**Applies to**: Any web application built with HTMX, Hotwire/Turbo, Unpoly, PJAX, or similar hypermedia-driven frameworks. Increasingly common in modern accounting, project management, and CRM software. Always inspect actual response headers before assuming 3xx redirect behavior.

---

## Lesson 148: Web App Entity URLs May Use Opaque Binary-Encoded Keys — Never Assume UUID or Integer Format

**The Problem**: Web applications do not all use UUIDs or incrementing integers as entity identifiers in their URLs. Some (particularly newer SaaS-style apps) use opaque, binary-encoded, or hash-derived parameters that change between app versions and contain no human-readable structure. A setup or export script that uses a regex like `r'[a-f0-9]{8}-...-[a-f0-9]{12}'` (UUID pattern) or `r'\?id=(\d+)'` (integer ID pattern) to extract entity references from HTML will silently return nothing when the actual URL contains a base64-encoded binary blob.

**How this manifests**:
- Entity count functions return 0 for a page that visibly lists entities
- UUID extraction returns `None` for entities that exist
- Baselines are recorded as 0, making `new_count = current_count - 0 = current_count` a meaningless delta
- The do-nothing test score may be non-zero because the "baseline" recorded was wrong

**The correct approach**:

1. **Inspect the actual HTML first**, before writing any extraction pattern:
   ```python
   resp = s.get(f"{MANAGER_URL}/entity-list-page?{biz_key}")
   # Print a sample of links to understand the actual URL format
   import re
   links = re.findall(r'href="([^"]+)"', resp.text)
   # Look at the links — what pattern do they follow?
   print(links[:10])
   ```

2. **Use length-based or structural differentiation** when IDs are opaque: In many apps, the "new entity form" link and the "existing entity view" link share the same URL prefix but differ in length (the existing-entity link has extra encoded state). Count entity-specific links by distinguishing them from the "new" link:
   ```python
   def count_entity_links(html, form_name):
       html = html.replace('&amp;', '&')
       all_links = list(set(re.findall(rf'href="(/{form_name}\?[^"]+)"', html)))
       if len(all_links) <= 1:
           return 0
       min_len = min(len(l) for l in all_links)
       # Entity-specific links are longer than the "new form" link
       return len([l for l in all_links if len(l) > min_len])
   ```

3. **Extract entity IDs from opaque URL parameters** by decoding them:
   ```python
   import base64
   def extract_uuid_from_opaque_param(param):
       """Many apps embed a UUID inside a larger binary-encoded URL parameter."""
       try:
           padded = param + "=" * (-len(param) % 4)
           decoded = base64.urlsafe_b64decode(padded)
           # Search backwards: UUID v4 has (byte[6] & 0xF0) == 0x40
           for i in range(len(decoded) - 16, max(-1, len(decoded) - 40), -1):
               chunk = decoded[i:i+16]
               if len(chunk) == 16 and (chunk[6] & 0xF0) == 0x40:
                   return (f"{chunk[0:4].hex()}-{chunk[4:6].hex()}-"
                           f"{chunk[6:8].hex()}-{chunk[8:10].hex()}-{chunk[10:16].hex()}")
       except Exception:
           pass
       return None
   ```

**General rule**: Before writing ANY entity ID extraction logic for a web app, open the app in a browser, navigate to an entity list page, right-click an entity link, and inspect the actual href. The URL format is the ground truth — not the app's documentation, not a prior version's behavior, and not an assumption about what "most apps" do.

**Applies to**: Any web application whose setup or export scripts must extract entity identifiers from HTML. Particularly relevant for modern cloud-era applications (post-2020) that may use encoded or composite keys rather than plain UUIDs or integers.

---

## Lesson 149: For Web App HTTP POSTs via Python Requests, Verify Whether the Endpoint Expects `data=` (Form-Encoded) or `files=` (Multipart)

**The Problem**: The Python `requests` library supports two fundamentally different POST body encodings:
- `data={field: value}` → `Content-Type: application/x-www-form-urlencoded`
- `files={field: (None, value)}` → `Content-Type: multipart/form-data`

Many web application endpoints only accept one of these. Using the wrong one causes silent failures: the entity may not be created, the server may return 200 with an empty/error body, or (worst) the entity is created but the response contains no redirect header because the server handled the request on a different code path than expected.

**Common failure pattern**:
```python
# WRONG: using files= (multipart) when the endpoint expects form-encoded
resp = s.post(url, files={"data": (None, json.dumps(payload))})
# Server returns 200, entity is created, but no HX-Redirect header is returned
# → entity UUID cannot be extracted → setup script silently uses uuid=None
```

**The Fix**: Use `data=` (form-encoded) for standard HTML form endpoints unless you have verified the endpoint requires multipart:
```python
# CORRECT: form-encoded (matches what a browser submits for standard HTML forms)
resp = s.post(url, data={"fieldName": json.dumps(payload)})
```

**How to determine which format the app uses**:
1. Open the app in a browser
2. Submit the form that creates the entity
3. In DevTools → Network → find the POST request → check "Headers" → look at `Content-Type`
4. If `Content-Type: application/x-www-form-urlencoded` → use `data=`
5. If `Content-Type: multipart/form-data` → use `files=`

**Rule**: Default to `data=` for standard web app form submissions. Only switch to `files=` (multipart) when the form is known to include file uploads, or when you have confirmed the endpoint requires it. After any entity-creation POST, always assert `resp.status_code == 200` and check that the expected redirect header or confirmation is present.

**Applies to**: Any setup or export script that creates entities in a web application via Python `requests`. This issue is invisible when testing manually (browsers always use the correct encoding) but breaks programmatic scripts that guess the wrong encoding.

---

## Lesson 150: Validate HTML-Based Entity Count Functions Return Non-Zero Against a Known-Non-Empty Page Before Deploying

**The Problem**: Entity-counting functions that scan HTML for link patterns (common in web app setups where a database is not directly queryable) can silently return 0 for ALL inputs if the link pattern is wrong. This creates a critically broken baseline: `baseline = 0` always, so `new_count = current_count - 0 = current_count` always — the anti-gaming mechanism becomes meaningless, and any entities that existed before the task started will be counted as new agent work.

**Why this is hard to notice**: The baseline recording step prints `"Baseline X count: 0"` which looks plausible if the environment is expected to be clean. The bug only reveals itself during scoring when `new_count` is unexpectedly large or the do-nothing test returns `score > 0`.

**The root cause pattern**:
```python
def count_links(html, form):
    # This regex requires '&uuid=<uuid>' suffix — works in app v25, broken in app v26+
    return len(set(re.findall(rf'/{form}\?[^&"\']+&([a-f0-9-]{{36}})', html)))
    # Returns 0 for every page in v26 because URLs no longer have &uuid= suffix
```

**How to validate before deploying**:

After writing a `count_links` / `count_entities` function, always run a quick sanity check against a list page that you *know* contains entities:
```python
# Sanity check — must be done during task development, not just at test time
test_html = s.get(f"{MANAGER_URL}/known-non-empty-list?{biz_key}").text
count = count_links(test_html, "entity-form-name")
assert count > 0, (
    f"count_links returned 0 for a known non-empty page — "
    f"the link pattern does not match the app's actual URL format. "
    f"Inspect the HTML: {test_html[:500]}"
)
```

**When to run this check**: During Phase 4 of the task creation process (setup/export verification), before recording any baselines. This is analogous to Lesson 36's rule about inspecting the live schema before writing SQL — here, you must inspect the live HTML before committing to a link-counting pattern.

**The safe fallback**: If you cannot determine a reliable link pattern, use the application's own listing API (if available) rather than HTML scraping. Link patterns depend on the rendering framework version; API responses are more stable.

**Applies to**: Any setup or export script that counts entities by scanning HTML for link patterns, rather than querying a database directly. Particularly relevant for web applications accessed via HTTP where the URL format may differ from documentation or older versions.

---

### Chromium-Based Browser SQLite Timestamp Epoch (1601-01-01, Not 1970-01-01)

**The Problem**: Chrome, Edge, Brave, and all Chromium-based browsers store timestamps in their SQLite `History` database as **microseconds since January 1, 1601** (the Windows FILETIME epoch), not Unix epoch (January 1, 1970). When you query `last_visit_time` or `start_time` from Chrome's `urls` or `downloads` tables and compare the value directly against `time.time()` or `date +%s`, you are comparing numbers that are ~50 years apart in different reference frames. The result is that **every visit looks like it happened after any task start time**, and your timestamp-based "was this visit new?" check always returns True — even in the do-nothing test.

**What breaks**:
```python
# WRONG — Chrome timestamp is NOT Unix epoch
import time, sqlite3

task_start = int(time.time())          # e.g. 1700000000  (seconds since 1970)
conn = sqlite3.connect(history_tmp)
cur.execute("SELECT url, last_visit_time FROM urls WHERE url LIKE '%example.com%'")
for url, lvt in cur.fetchall():
    # lvt is e.g. 13370000000000000 (microseconds since 1601)
    # Converting: lvt // 1_000_000 ≈ 13370000000 seconds since 1601
    # That is ~year 2024 in UNIX terms only after subtracting the epoch offset
    is_new = lvt > task_start   # ALWAYS True — 13 trillion > 1.7 billion
```

This causes `is_new = True` for every URL in the database regardless of when the task started, so the do-nothing test scores non-zero. The root cause is invisible — the values look like plausible large integers.

**The Fix**: Subtract the Windows-to-Unix epoch offset before comparing:

```python
# CORRECT — convert Chrome timestamp to Unix seconds before comparing
CHROME_EPOCH_OFFSET_US = 11644473600 * 1_000_000  # microseconds between 1601-01-01 and 1970-01-01

for url, lvt in cur.fetchall():
    unix_ts = (lvt - CHROME_EPOCH_OFFSET_US) // 1_000_000  # now in Unix seconds
    is_new = int(unix_ts) > task_start                      # correct comparison
```

In **SQLite directly** (e.g., in `task_utils.sh`):
```bash
# SQLite's datetime() with the epoch offset, returning a human-readable time
sqlite3 "$db" "
  SELECT url, datetime(last_visit_time/1000000 - 11644473600, 'unixepoch') AS visit_time
  FROM urls
  ORDER BY last_visit_time DESC LIMIT 10
"
```

**Why 11644473600**: The Windows FILETIME epoch is January 1, 1601. The Unix epoch is January 1, 1970. The difference is exactly 11,644,473,600 seconds (accounting for leap years between 1601 and 1970). Chrome stores time in microseconds, so the microsecond offset is `11644473600 × 1,000,000`.

**Columns affected** in Chrome's SQLite schema:

| Table | Column | Units |
|-------|--------|-------|
| `urls` | `last_visit_time` | Microseconds since 1601-01-01 |
| `visits` | `visit_time` | Microseconds since 1601-01-01 |
| `downloads` | `start_time`, `end_time`, `opened` | Microseconds since 1601-01-01 |
| `keyword_search_terms` | (via `visits`) | Microseconds since 1601-01-01 |

**Quick diagnostic**: If your timestamp value is roughly 1.3 × 10¹⁶ (thirteen quadrillion), it is a Chrome microsecond timestamp. If it is roughly 1.7 × 10⁹ (1.7 billion), it is already a Unix second timestamp.

**Applies to**: Any `setup_task.sh` or `export_result.sh` that queries a Chromium-based browser's SQLite `History` database — Chrome, Microsoft Edge, Brave, Opera, Chromium, Vivaldi, Arc. The schema is identical across all Chromium forks.

---

### Never Hardcode Install-Time Entity IDs

**The Problem**: Many database-backed environments pre-seed entities (patients, users, accounts, records) at install time, assigning them opaque IDs — UUIDs, auto-increment primary keys, or other system-generated identifiers. If you hardcode these IDs in `setup_task.sh` or `export_result.sh`, your scripts will silently break whenever the environment's disk image is rebuilt, since new IDs are assigned on each fresh install.

**Real example**: A MedinTux EHR environment seeds patient records whose GUIDs are assigned by `/proc/sys/kernel/random/uuid` at database creation time. Hardcoding `GUID_MARTIN="0E78F6AF-..."` works until the image is regenerated — at which point every task that uses that GUID fails with `ERROR: Patient not found`.

**Symptom**: `setup_task.sh` exits with an error like `"ERROR: entity X not found"` after a disk image upgrade, even though the entity still exists under a different ID.

**The Fix**: Look up entity IDs dynamically at runtime using a stable human-readable key (full name, username, email address, slug, or other natural identifier that the application assigns and never changes):

```python
# BAD: hardcoded UUID — breaks if disk image is rebuilt
GUID_PATIENT = "0E78F6AF-9396-4000-A4C2-29FFE96C6205"

# GOOD: dynamic lookup by stable name — survives image rebuilds
cursor.execute(
    "SELECT id FROM patients WHERE first_name=%s AND last_name=%s",
    ("Sophie", "Martin")
)
row = cursor.fetchone()
if not row:
    raise RuntimeError("Required test patient Sophie Martin not found")
guid = row[0]
```

**Save the resolved ID to a seed file** so that `export_result.sh` can use the same ID without a second lookup:

```bash
# In setup_task.sh
python3 << 'PYEOF' > /tmp/task_seed_ids.json
import json, pymysql
conn = pymysql.connect(...)
cursor = conn.cursor()
cursor.execute("SELECT id FROM patients WHERE name=%s", ("Sophie Martin",))
guid = cursor.fetchone()[0]
json.dump({"guid_martin": guid}, open("/tmp/task_seed_ids.json", "w"))
PYEOF

# In export_result.sh — read the saved ID instead of hardcoding
python3 -c "import json; d=json.load(open('/tmp/task_seed_ids.json')); print(d['guid_martin'])"
```

**When hardcoding IS safe**: Some applications assign IDs deterministically — for example, a fixture system that always inserts the same three demo records with IDs 1, 2, 3 on every fresh install. In that case, hardcoding is safe but you should still add an existence check (`SELECT COUNT(*) WHERE id=1`) in `setup_task.sh` to fail loudly rather than silently if an image change breaks the assumption.

**Applies to**: Any environment whose database seed creates entities with system-generated IDs — EHR systems, CRMs, project management tools, practice management software, and any other application with an auto-seeded demo database. Especially important for applications backed by MySQL/PostgreSQL that use `UUID()` or `SERIAL`/`AUTOINCREMENT` for primary keys.

---

### Clean-Then-Reseed: Making Task Setup Idempotent

**The Problem**: Tasks for database-backed environments typically seed scenario data into pre-existing entities: add prescriptions to a patient, attach documents to an account, insert consultation notes into a record. If `setup_task.sh` only inserts data without first removing any previously inserted data, running setup a second time (e.g., re-running after a failed test) will double or triple the seeded records. This corrupts baseline counts and can cause the do-nothing test to return a non-zero score.

**Symptom**: The do-nothing test passes with `score > 0` on the second run, even though the agent did nothing. The first run was fine; the second and subsequent runs are not.

**The root cause pattern**:
```bash
# BAD: inserts without cleaning up first
python3 << 'PYEOF'
INSERT INTO prescriptions ...  # Run twice → 2 prescriptions, baseline is inflated
PYEOF

BASELINE_COUNT=$(query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=X")
echo "$BASELINE_COUNT" > /tmp/baseline_count  # 2 on second run, not 1
```

Now if the verifier checks for `new_count > baseline_count`, the second seeded prescription looks like agent work.

**The Fix — Clean-Then-Reseed pattern**: Always delete any previously seeded task-specific data for the target entities before inserting fresh scenario data. Place the cleanup step at the top of the Python block, before any inserts:

```python
# GOOD: clean then reseed — idempotent regardless of run count
conn = get_db_connection()
cursor = conn.cursor()

# Step 1: Clean — remove any previously seeded data for the target entities
for entity_id in [guid_a, guid_b, guid_c]:
    pks = get_all_records(cursor, entity_id)
    if pks:
        cursor.execute(f"DELETE FROM child_table WHERE pk IN ({placeholders})", pks)
        cursor.execute(f"DELETE FROM parent_table WHERE pk IN ({placeholders})", pks)

# Step 2: Reseed — insert fresh scenario data
insert_scenario_record(cursor, guid_a, scenario_data_a)
insert_scenario_record(cursor, guid_b, scenario_data_b)
conn.commit()

# Step 3: Record baseline AFTER seeding
baseline_pk = get_max_pk(cursor)
save_baseline(baseline_pk)  # Only agent-created records will have PK > baseline
```

The baseline is recorded **after** setup seeding completes. Any record the agent creates will have a higher PK than the baseline. Any record from the seeding step will be at or below the baseline, so it doesn't count as agent work.

**Why this matters beyond correctness**: Clean-then-reseed also makes tasks robust to interrupted runs (e.g., setup crashed midway through), multiple test iterations, and cache invalidation scenarios. A setup script that is safe to run twice is dramatically easier to debug.

---

## Lesson 151: Spreadsheet Verifiers Must Use `data_only=True` to Read Computed Formula Values

**The problem**: When a task requires the agent to enter formulas into a spreadsheet (Excel `.xlsx`, LibreOffice Calc `.ods`/`.xlsx`), the verifier reads the saved file to check the results. Without the correct flag, the verifier reads the formula *string* rather than the *computed value* — so a cell containing `=SUM(B4:B8)/SUM(B4:B8)` appears as that literal text rather than `1.4222`.

```python
# WRONG: reads formula strings, not values
wb = openpyxl.load_workbook("/tmp/result.xlsx")
ws = wb.active
val = ws["C10"].value   # returns "=SUM(numerator)/SUM(denominator)" — not 1.4222
```

```python
# CORRECT: reads cached computed values
wb = openpyxl.load_workbook("/tmp/result.xlsx", data_only=True)
ws = wb.active
val = ws["C10"].value   # returns 1.4222  (or None if never computed)
```

**Critical caveat — cached values require prior computation**: `data_only=True` reads the cached value stored in the xlsx at the time of the last save. If the agent entered a formula but the workbook was never opened and calculated by a real Excel/Calc process, the cache will be `None`. For this reason:
- The starter `.xlsx` file should already have any static cells computed (pre-save with openpyxl or xlsxwriter).
- The export step should ensure Excel/Calc computed and saved the file (for Windows environments: `Ctrl+S` in the task description; for Linux: `LibreOffice --headless --calc --infilter='Calc MS Excel 2007 XML' --convert-to xlsx`).
- If a cell returns `None` with `data_only=True`, it means the formula was never evaluated — treat it as a blank (not as a valid answer).

**When to use**: Any verifier for a task whose output is an Excel or LibreOffice Calc file with formula cells. This applies regardless of platform (Windows, Linux) and applies to both `.xlsx` and `.ods` files (for ODS, use `odfpy` or extract via `zipfile` + XML parsing).

**Applies to**: All spreadsheet environments — Microsoft Excel 2010/365, LibreOffice Calc, Google Sheets exports. If the verifier reads a spreadsheet file, `data_only=True` (or its equivalent) is almost always required.

---

## Lesson 152: Satisfying Principle 2 with Regulatory and Financial Publications — the Three-Layer Citation Chain

**The problem**: Principle 2 requires ALL task data to be real. For professional computation tasks (actuarial reserving, GHG accounting, fixed-income analytics, workforce analytics), the key inputs are often published numerical parameters — regulatory emission factors, industry loss development factors, government yield curves, published wage benchmarks. These numbers are real (they appear verbatim in government documents), but this can be hard to verify unless it is documented clearly.

**The pattern — document the source in three places**:

1. **`task.json` `metadata.dataset` field** (machine-readable, short): Identifies the source for automated review.
   ```json
   "dataset": "EPA 40 CFR Part 98 Table C-1 emission factors (NG: 53.06 kg CO2/MMBtu); EPA eGRID 2022 RFCW: 0.000380 MT CO2e/kWh; URL: https://www.epa.gov/egrid/download-data"
   ```

2. **`README.md` "Data Sources" section** (human-readable, detailed): Full table with exact values, publication names, and URLs. Anyone reviewing the task can verify each number against the cited document.
   ```markdown
   ## Data Sources
   - Natural Gas: 53.06 kg CO2/MMBtu — EPA 40 CFR Part 98, Table C-1, Natural Gas (Weighted U.S. Average)
     URL: https://www.ecfr.gov/current/title-40/chapter-I/subchapter-C/part-98/subpart-C
   ```

3. **Setup script comments** (traceability for future maintainers): Each hardcoded value in the setup script has an inline comment pointing to the source.
   ```python
   NG_FACTOR = 0.05306  # EPA 40 CFR Part 98 Table C-1: Natural Gas, 53.06 kg CO2/MMBtu
   RFCW_FACTOR = 0.000380  # EPA eGRID 2022 RFCW subregion: 0.8386 lb CO2e/kWh ÷ 2204.62 lb/MT
   ```

**When each layer matters**:
- If task.json is inspected by an automated check, the dataset field is the first signal.
- If a human reviewer questions whether data is synthetic, the README is what they look at.
- If the task needs to be updated (e.g., EPA publishes eGRID 2024), the setup script comments tell the maintainer exactly which table to update.

**Reference table of reliable free public data sources by domain** (all are real, citable, no registration required):

| Domain | Key data | Source | URL pattern |
|--------|----------|--------|-------------|
| GHG emissions | Combustion factors (gas, oil, diesel) | EPA 40 CFR Part 98, Table C-1 | ecfr.gov/...part-98/subpart-C |
| GHG emissions | Electricity emission factors by NERC subregion | EPA eGRID (annual) | epa.gov/egrid/download-data |
| Fixed income | US Treasury par yield curve (daily) | Treasury H.15 / FRED DGS* | home.treasury.gov/...interest-rates |
| Fixed income | Corporate bond OAS spreads | ICE BofA indices via FRED (BAMLC0A0CM) | fred.stlouisfed.org/series/BAMLC0A0CM |
| P&C insurance | WC/GL/auto loss development factors | NAIC Annual Statistical Bulletin | content.naic.org/...statistical-bulletin.htm |
| Agriculture | County-level crop yield/production | USDA NASS Quick Stats | quickstats.nass.usda.gov |
| Healthcare wages | Hourly wages by SOC occupation | BLS OEWS (May release, annual) | bls.gov/oes/current/oes_nat.htm |
| Healthcare wages | Hospital cost reports | CMS Provider of Services files | cms.gov/Research-Statistics.../Provider-of-Services |
| Energy consumption | Commercial building energy use | US EIA CBECS (every 4 yrs) | eia.gov/consumption/commercial |
| Labor law | FLSA OT threshold, minimum wage | US DOL WHD | dol.gov/agencies/whd/flsa |
| Municipal bonds | AAA muni yield benchmarks | MSRB/EMMA | emma.msrb.org |

**Key distinction (Principle 2)**: A number is "real" if it appears verbatim in the cited publication and can be looked up there. A number is "synthetic" if it was chosen to be "consistent with" or "representative of" a publication — even if the publication is real. When in doubt, look up the exact value in the cited document; if you cannot find the exact number there, it is synthetic.

**Applies to**: Any task in a professional software environment (financial modeling, scientific analysis, regulatory compliance, workforce management) where the meaningful inputs are numerical parameters from published standards. Especially important for: actuarial environments, GHG/sustainability tools, fixed-income tools, tax and payroll software.

---

## Lesson 153: Derive Verifier Tolerance Ranges from Real Data First — Never from Synthetic Expectations

**The problem**: When creating a task, the natural workflow is to (1) design the scenario, (2) generate test data, (3) compute expected outputs, (4) set verifier tolerance ranges around those outputs. If test data is synthetic (even "realistic-looking" synthetic data), the expected outputs and tolerance ranges reflect the synthetic data's statistics — not real-world statistics. When the task is later corrected to use real data (Principle 2), the synthetic-derived ranges may be completely wrong.

**Example**: A synthetic Iowa corn yield dataset with artificially compressed yield variation produced a weighted-average yield gap of ~17.1%, so the verifier was set to accept [16.3%, 17.9%]. Real 2022 USDA NASS Iowa county yields (a historically good crop year) produced a weighted-average gap of ~11.3% — completely outside the synthetic-calibrated range. Every correct submission would fail.

**The rule**: Always derive verifier expected values and tolerance ranges by computing them from the actual real data, before writing the verifier.

```python
# CORRECT workflow:
# 1. Load the real data file
import openpyxl
wb = openpyxl.load_workbook("data/real_data.xlsx", data_only=True)
ws = wb["Sheet1"]

# 2. Compute expected values manually from real data
actual_yields = [ws.cell(r, 3).value for r in range(2, 24)]
potential_yields = [ws.cell(r, 4).value for r in range(2, 24)]
acres = [ws.cell(r, 5).value for r in range(2, 24)]

gaps = [(p - a) / p for a, p in zip(actual_yields, potential_yields)]
weighted_avg = sum(g * a for g, a in zip(gaps, acres)) / sum(acres)

print(f"Real weighted avg gap: {weighted_avg:.4f}")  # e.g., 0.1133 = 11.33%

# 3. Set tolerance range at ±15% of real expected value
lo, hi = weighted_avg * 0.85, weighted_avg * 1.15
print(f"Verifier range: [{lo:.4f}, {hi:.4f}]")  # e.g., [0.0963, 0.1303]
```

**Tolerance width guidelines**:
- **±5%**: Use when the formula is deterministic and the only variation is floating-point precision. Example: summing a fixed set of integers.
- **±10–15%**: Use for formulas where agents may use slightly different rounding conventions, intermediate truncation, or equivalent-but-distinct algebraic forms. Example: weighted averages, LDF chains.
- **±20–30%**: Use when the task allows multiple valid methodologies that produce different results. Example: NPV with different compounding conventions.

**Also: validate tolerance ranges against at least two distinct correct implementations**. If two correct Python implementations of the formula both produce values within the range, the range is appropriate. If one falls outside, widen it.

**Applies to**: Any verifier that checks numerical outputs of formula-based tasks — spreadsheet tasks, financial modeling, scientific analysis, statistical computations. The principle generalizes: whenever a verifier checks a computed value against an expected range, the expected range must be anchored to real data, not to whatever a synthetic dataset happened to produce.

**Applies to**: Any `setup_task.sh` that inserts data into a database to create a scenario for the agent. Especially important for relational databases where child/parent tables require coordinated deletes (e.g., a rubric system with a header table and a blob/content table, or a CRM with opportunities and associated activities).

---

## Lesson 154: Immutable Default Configuration Entries — Compare Against Baseline Count, Not Absolute Zero

**The problem**: Some applications ship with default configuration entries that cannot be removed without breaking functionality (e.g., a security platform's mandatory active-response block, a required system service entry, a built-in compliance rule). If you check `current_count > 0` to detect whether the agent added something, the check fires immediately on a fresh install — before the agent does anything — because the immutable default already satisfies `> 0`. Lesson 103 advises resetting defaults in `setup_task.sh` as the primary fix. But when a default **cannot** be removed, a different approach is needed.

**Real example**: Wazuh ships with exactly one `<active-response>` block in `ossec.conf` (its default firewall-drop response). A task requiring the agent to add a custom active-response block checked `HOST_AR -gt 0` — which was always true, giving the agent free points for this criterion even without doing anything.

**The fix**: Record the baseline count in `setup_task.sh` BEFORE the task, then check `current > baseline` in the export script.

```bash
# setup_task.sh — record the immutable baseline
INITIAL_AR_COUNT=$(docker exec "${CONTAINER}" grep -c "<active-response>" \
    /var/ossec/etc/ossec.conf 2>/dev/null || echo "0")
echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count
```

```bash
# export_result.sh — compare against baseline, not against 0
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count 2>/dev/null || echo "0")
HOST_AR=$(docker exec "${CONTAINER}" grep -c "<active-response>" \
    /var/ossec/etc/ossec.conf 2>/dev/null || echo "0")

if [ "$HOST_AR" -gt "$INITIAL_AR_COUNT" ] 2>/dev/null; then
    ACTIVE_RESPONSE_CONFIGURED=1
fi
```

**Key difference from Lesson 103**: Lesson 103's fix is to *reset* the default to a non-satisfying state (e.g., disable WFS before the task starts). This lesson covers the case where the default cannot be reset — you must instead treat the baseline as the new zero-point and measure *relative* change.

**When this is necessary**:
- The default config entry is required for the application to function (removing it breaks the service)
- The entry is re-created automatically even if you delete it (the application reinstalls its defaults on restart)
- The default value is a mandatory built-in that the platform vendor requires

**Pattern to apply**: Wherever an export script checks `count > 0` for a config entry, ask: "Does the application ship with at least one of these entries by default?" If yes, switch to `count > INITIAL_COUNT`.

**Applies to**: Security platforms (SIEM, EDR, WAF) with built-in response rules; enterprise applications with mandatory compliance baselines; database servers with default users/schemas; any application that ships with a non-empty default configuration that overlaps with the task's verification criteria.

---

## Lesson 155: Format-Validity Criteria Award Free Points for Setup-Script Baselines — Gate on Content Existence

**The problem**: A common verifier pattern awards points for format validity: "Is the XML/JSON/YAML file the agent modified syntactically valid?" This seems reasonable — malformed output should not receive points. But `setup_task.sh` typically writes a well-formed *baseline* version of the file before the task starts. Since the baseline is syntactically valid, the format-validity criterion fires in the do-nothing state, awarding free points before the agent does anything.

**Real example**: A task required the agent to add a custom Wazuh decoder to `local_decoder.xml`. The verifier checked:
- (20 pts) Custom web decoder exists in the file
- (15 pts) `local_decoder.xml` is valid XML ← fires on baseline

`setup_task.sh` reset the file to a clean baseline with a placeholder decoder — syntactically valid XML. The do-nothing test scored 15 points (the XML validity criterion) even though no web decoder was present.

**The fix**: Make format-validity criteria *dependent* on the primary content criterion. Only award format points if the required content was also detected.

```python
# BAD — baseline is always valid XML, so this always fires:
if result.get('decoder_xml_valid'):
    score += 15

# GOOD — only meaningful if a web decoder was actually created:
if result.get('decoder_exists') and result.get('decoder_xml_valid'):
    score += 15
elif result.get('decoder_exists') and not result.get('decoder_xml_valid'):
    score += 0  # penalize broken XML, but only if the agent tried something
    feedback_parts.append("FAIL: XML is malformed — check decoder syntax")
# else: no decoder found — XML validity is irrelevant, skip the criterion
```

**Why this is different from Lesson 89**: Lesson 89 gates "context" criteria (is the agent on the right screen?) on "outcome" criteria (did the agent produce a result?). This lesson addresses format/quality criteria (is the output syntactically valid?) which are implicitly satisfied by whatever the setup script writes, not by navigation menus. The failure mode is distinct: the baseline file itself — not the application's default UI state — is the source of the false positive.

**The general rule**: For any criterion of the form "the file the agent modified is syntactically valid / schema-compliant / parseable", ask: "Would the baseline version of this file that setup_task.sh writes already satisfy this criterion?" If yes, gate the validity criterion on the primary content/existence criterion. The validity check is only meaningful when there is *something new to validate*.

**Applies to**: XML configuration files, JSON output files, YAML policy files, INI/TOML config files, and any structured format that is pre-populated with a valid skeleton by the setup script. Also applies to schema-compliance criteria ("file matches expected schema") and encoding criteria ("file is valid UTF-8").

---

## Lesson 156: Live External Feed Data Quantity Is Variable — Use Conservative Thresholds in Setup and Verifier

**The problem**: Some tasks download real data from a live external feed (threat intelligence blocklists, CVE databases, vulnerability feeds, public APIs) as part of `setup_task.sh`. When writing the task, you sample the feed and observe N entries — so you set a threshold of N in both `setup_task.sh` (to verify the download succeeded) and the verifier (to award full credit). Later, the feed shrinks or has fewer entries than at the time of writing. Now the download always fails the threshold check, setup exits early (missing baseline files), and agents cannot be evaluated.

**Real example**: A task downloaded the Feodo Tracker C2 IP blocklist and required `IP_COUNT >= 5` to proceed. At the time of testing, the live feed had only 3 IPs. Every run of `setup_task.sh` exited early, leaving no baseline files and breaking the pipeline.

**The fix — two-part**:

**Part 1 — Use >= 1 (non-empty) as the setup gate, not an observed-N gate**:
```bash
# BAD: assumes feed size is stable
IP_COUNT=$(wc -l < /tmp/feed.txt)
if [ "$IP_COUNT" -lt 5 ]; then
    echo "ERROR: Feed too small ($IP_COUNT entries). Aborting."
    exit 1
fi

# GOOD: verify feed is non-empty (download succeeded and produced data)
IP_COUNT=$(grep -v "^#\|^$" /tmp/feed.txt | wc -l)
if [ "$IP_COUNT" -lt 1 ]; then
    echo "ERROR: Feed is empty — download may have failed."
    exit 1
fi
```

**Part 2 — Verifier uses >= 1 for full credit; report the actual count in feedback**:
```python
# BAD: calibrated to a snapshot observation
if count >= 5:
    score += 35
elif count >= 1:
    score += 15  # partial credit only

# GOOD: any non-empty real dataset earns full credit
if count >= 1:
    score += 35
    feedback_parts.append(f"CDB threat intel list contains {count} real entries from live feed")
```

**When NOT to use >= 1**: If the task requires the agent to curate a *minimum number* of entries (e.g., "add at least 10 firewall rules"), then the threshold is about the *agent's output*, not about a live feed. Use the agent-output threshold directly. This lesson only applies to thresholds that gate on downloaded *input* data.

**Design principle**: The number of entries in a live external feed at the time you wrote the task is an unreliable constant. For gates that exist to verify "did the download succeed and produce usable data?", non-emptiness (>= 1) is the correct gate. For gates that award credit for the agent's work, base the threshold on what a reasonable agent should produce, not on the feed size.

**Also note**: Document in `task.json`'s `metadata` field which live feed the task depends on, so future maintainers know where to look if the feed changes URLs or format:
```json
"dataset": "Feodo Tracker C2 blocklist (https://feodotracker.abuse.ch/downloads/ipblocklist.txt) — non-empty IP list required"
```

**Applies to**: Any task whose setup downloads live threat intelligence feeds, CVE/NVD databases, public financial data APIs, open government datasets, or any other external source whose size varies over time.

---

## Lesson 157: For Programming / Configuration Creation Tasks, the Difficulty Axis Is Technical Complexity — Not Discovery Burden

**The problem**: The core principles document frames difficulty primarily around *discovery burden* (how much the agent must find on its own) and *UI navigation depth* (how many menus/screens to traverse). This model works well for repair tasks and GUI-heavy applications. It does not describe the difficulty of *creation tasks* in programming or configuration environments — tasks where the agent writes code, SQL, scripts, or configuration files from scratch.

For these environments, the difficulty axis is **technical complexity of the implementation**: the agent knows exactly what to build (the goal is stated clearly), but building it correctly requires deep domain knowledge — e.g., writing a recursive CTE, implementing certificate-based encryption, constructing a multi-table aggregate query with window functions, or configuring a certificate chain.

**Why this matters for task design**: If you apply the repair-task difficulty model to creation tasks, you will either:
- Make descriptions intentionally vague (trying to add "discovery burden") when the task is actually a specification-driven implementation task. Vagueness in a creation task does not add difficulty — it just makes the success criterion ambiguous.
- Misjudge difficulty as "easy" because the goal is clearly stated, when in reality the implementation requires sophisticated techniques that many agents cannot produce.

**The right model for creation tasks**:

| Difficulty Level | What it means for creation tasks |
|---|---|
| Easy | Single operation: create one simple object (one table, one file, one function) with no complex logic |
| Medium | 2–3 objects with straightforward implementation; agent must understand the tool/language to proceed |
| Hard | Multiple interdependent objects with moderate technical complexity; agent must know intermediate features (joins, aggregations, basic window functions) |
| Very Hard | Multiple interdependent objects where each individually requires advanced technique (recursive CTEs, symmetric encryption, trigger + procedure interaction, complex window function compositions) — failure in any one object causes cascading failure |

**Self-check questions for calibrating creation task difficulty**:
- Can the implementation be completed by someone who has only done basic tutorials for this tool/language?
- Does correct completion require combining 3+ advanced features of the tool (not just using the tool at all)?
- Is there a non-obvious ordering constraint between objects? (e.g., must create schema before table before index before procedure)
- Does the correct implementation require handling a non-obvious edge case (NULL propagation, deduplication via window function, object dependency ordering)?

If the answer to all but the first is yes, the task is genuinely hard/very_hard even though the agent is told exactly what to build.

**Applies to**: SQL environments (database creation, view/procedure/trigger implementations), scripting environments (shell scripting, Python automation), infrastructure/config environments (network policy, certificate management, CI/CD pipeline configuration), and any environment where the agent produces code or configuration artifacts.

---

## Lesson 158: Object Names Must Appear in Very_Hard Creation Task Descriptions — This Does NOT Violate the "Goal Only" Principle

**The problem**: The core principles state that *very_hard* task descriptions should contain "the high-level goal only — no expected values." A literal reading of this seems to prohibit specifying names like `Analytics.VendorPerformance` or `audit.usp_InsertSensitiveRecord` in the description. But verifiers for creation tasks need specific object names to verify. How do you resolve this?

**The resolution**: The "no expected values" principle targets *repair tasks* — tasks where the correct value of a field is something the agent must derive from domain context (the right blood pressure value, the correct medication dosage, the right patient ID). For those tasks, giving the agent the answer trivializes the discovery component.

Creation tasks are structurally different: the object name is not a *value to discover* but a *deliverable specification* — like a real software engineering spec that says "the endpoint must be named `/api/v1/orders`." The difficulty is not in guessing the name; it is in correctly implementing the object with that name.

**Rule of thumb**: For creation tasks, include object names and structural requirements in the description. Omit implementation details:

| Include in very_hard creation task description | Omit from very_hard creation task description |
|---|---|
| Object names (table name, procedure name, schema name) | Exact DDL syntax (`CREATE TABLE ... WITH (...)`) |
| Required business metrics to compute | Exact SQL expressions (`SUM(CASE WHEN x >= y THEN 1 ELSE 0 END)`) |
| Expected row counts / size of output | Which joins to use and in what order |
| Structural constraints (e.g., "SSN must be stored encrypted as VARBINARY") | Which specific SQL function to call (`ENCRYPTBYKEY`, `DENSE_RANK`) |
| End state (what must exist and what data it must contain) | Step-by-step numbered implementation instructions |

**Practical test**: After writing the description, ask: "Does this description tell the agent HOW to implement it, or just WHAT to build?" If the answer is "what to build," you are within the principle. If it reads like a tutorial or a recipe, you have over-specified.

**Applies to**: Any task in a programming, scripting, database, or configuration environment where the agent must produce named artifacts (files at specific paths, database objects, API endpoints, configuration sections) and the verifier checks for those specific names.

---

## Lesson 159: Internal Consistency of Derived Metrics Is a Stronger Verification Signal Than Range Checks Alone

**The problem**: Tasks that require computing derived or aggregated metrics (ratios, counts broken down by category, percentages) are often verified by checking that each metric is individually in a plausible range. This catches obviously wrong values but misses silently incorrect implementations — e.g., a query that double-counts rows, uses the wrong filter, or sums a column from the wrong join.

**The insight**: For any set of metrics where a mathematical relationship must hold between them, verifying that relationship is a stronger signal than checking each metric individually. If the relationship holds, the derived metrics are almost certainly computed correctly. If it fails, the implementation has a structural error even if each individual value looks plausible.

**Common relationships to check**:

| Metric type | Relationship to verify |
|---|---|
| Category breakdown | `SUM(category_counts) == total_count` |
| Percentage of total | `SUM(percentages) ≈ 100` (within floating point tolerance) |
| DENSE_RANK | `MIN(rank) == 1` AND `MAX(rank) == COUNT(DISTINCT rank)` |
| LAG/LEAD window | Non-null previous-period values exist (> 0 rows where lag IS NOT NULL) |
| Rate/fraction | Value is in [0.0, 1.0] AND numerator <= denominator |
| Subtotal check | `parent_total == SUM(child_totals)` for hierarchical data |

**Example — gender breakdown in a workforce summary**:
```python
# Weak check: each value individually looks plausible
if female_count > 0 and female_count < 500:
    score += 5  # Could still be double-counted or from wrong table

# Strong check: the relationship must hold
rows_where_gender_sums_match = result.get("rows_where_gender_adds_up", 0)
total_rows = result.get("table_row_count", 0)
if rows_where_gender_sums_match == total_rows and total_rows > 0:
    score += 10  # Conditional aggregation is definitely correct
```

**Implementation pattern in export_result.sh**:
```bash
# Instead of querying each column separately, query the relationship
GENDER_CONSISTENT=$(mssql_query "
    SELECT COUNT(*) FROM HumanResources.WorkforceSummary
    WHERE (FemaleCount + MaleCount) = ActiveEmployeeCount
" "db" | tr -d ' \r\n')
# If GENDER_CONSISTENT == TABLE_ROW_COUNT, the aggregation is correct
```

**When to use**: Any task where the agent computes a breakdown of a total (by category, by status, by attribute), computes a running total or moving average (LAG/LEAD), computes a rank (DENSE_RANK/RANK), or computes a rate/fraction. Do not over-use — only add this check when a genuine mathematical relationship exists between the computed columns.

**When NOT to use**: If the metrics are independently computed (e.g., average salary and total headcount have no required mathematical relationship), a consistency check adds nothing. Only apply where a relationship genuinely must hold.

**Applies to**: SQL/database tasks, analytical reporting tasks, spreadsheet tasks, and any task where the agent computes aggregated or derived metrics that have known mathematical relationships.

---

### Avoid `set -euo pipefail` in Setup Scripts with Embedded Interpreter Blocks

**The Problem**: `set -euo pipefail` at the top of a `setup_task.sh` is a common defensive pattern, but it is incompatible with scripts that embed another interpreter (PHP, Python, Ruby, etc.) via heredoc. Any non-zero exit from the embedded block — including non-fatal PHP warnings or Python print-and-continue paths — causes the entire bash script to abort immediately. Because the abort is silent (no "setup failed" message, just no output), the `pre_task` hook appears to finish successfully while leaving zero setup state: no `/tmp/` baseline files, no data seeded.

**What breaks**:
```bash
#!/bin/bash
set -euo pipefail   # ← kills the script on any non-zero subcommand

sudo -u www-data php << 'PHPEOF'
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');

// PHP emits a warning here → exits with non-zero
$cat = $DB->get_record('course_categories', ['idnumber' => 'NONEXISTENT']);

// Everything below this line never runs
echo "SETUP_COMPLETE\n";
PHPEOF
# ← bash sees PHP's non-zero exit, aborts here
# /tmp baseline files are never written
```

The export script then runs and finds an empty environment. The do-nothing test sees all-empty fields, which may or may not result in score=0 depending on how the verifier handles missing state. The setup appears to succeed but the task is unsolvable.

**The Fix**: Remove `set -euo pipefail` from any setup script that embeds another interpreter. Instead, check for specific failure conditions explicitly:

```bash
#!/bin/bash
# Do NOT use set -euo pipefail when embedding PHP/Python/Ruby via heredoc

sudo -u www-data php << 'PHPEOF'
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
// ... setup logic ...
echo "SETUP_COMPLETE\n";
PHPEOF

PHP_EXIT=$?
if [ $PHP_EXIT -ne 0 ]; then
    echo "WARNING: PHP setup exited with code $PHP_EXIT"
fi

# Check for the sentinel rather than trusting exit code
if ! grep -q "SETUP_COMPLETE" /tmp/some_signal_file 2>/dev/null; then
    echo "ERROR: PHP setup did not complete"
    exit 1
fi
```

**Why this happens**: PHP, Python, and other interpreters routinely exit non-zero for warnings, deprecation notices, or partial failures — all of which are non-fatal from the application's perspective. `set -euo pipefail` treats every non-zero exit as fatal for the parent bash script.

**Alternative**: Wrap the interpreter call with `|| true` if you want to keep `set -euo pipefail` for the rest of the script:
```bash
sudo -u www-data php << 'PHPEOF'
...
PHPEOF
true  # suppress exit code so pipefail doesn't trigger
```

**Applies to**: Any `setup_task.sh` that embeds PHP (`sudo php << 'PHPEOF'`), Python (`python3 << 'PYEOF'`), Ruby, Perl, or any other interpreter via heredoc. Web application environments (Moodle, WordPress, Drupal, Django, Rails) are the primary cases, but the problem is language-agnostic.

---

### Framework CLI Bootstrap APIs: Object Mutation Trap in Try/Catch Fallback

**The Problem**: Many web frameworks (Moodle, WordPress, Drupal, Django, etc.) support CLI execution via a bootstrap script. This lets `setup_task.sh` call the framework's high-level module APIs (`assign_add_instance()`, `wp_insert_post()`, `quiz_add_instance()`, etc.) directly from a PHP/Python CLI script. However, these "create" APIs frequently fail in CLI context because they depend on components only available in a full HTTP request lifecycle:

- File upload handling (e.g., `page_add_instance()` calls `page_set_mainfile()`)
- Active web session or `$_POST` form data
- Event system hooks that fire during web requests
- Grade calculation callbacks that require a logged-in user context

The instinctive fix is a `try/catch` with a direct database fallback (`$DB->insert_record('table', $obj)`). This works correctly for simple objects — but there is a **subtle trap**: the failing API may partially mutate the data object before throwing its exception. For example, `quiz_add_instance($quiz)` in Moodle calls an internal callback that adds a `reviewmaxmarks` property to `$quiz` — a column that does not exist in the `mdl_quiz` database table. When the catch block then tries `$DB->insert_record('quiz', $quiz)`, the Moodle DML layer reads ALL properties from `$quiz`, generates an INSERT with `reviewmaxmarks` as a column, and fails with "Error writing to database" — a completely different error from the original one, with no clear diagnosis.

**What breaks**:
```php
// BROKEN: $quiz gets mutated by quiz_add_instance before it throws
$quiz->id = 0;
try {
    $quiz->id = quiz_add_instance($quiz, null);  // adds $quiz->reviewmaxmarks!
} catch (Throwable $e) {
    // $quiz is now contaminated with extra properties
    $quiz->id = $DB->insert_record('quiz', $quiz);  // ALSO fails: unknown column
}
// Result: quiz is never created; caught exception gives misleading message
```

**The Fix**: Create a clean copy of all known-safe fields BEFORE calling the API. Use the clean copy (not the potentially-mutated original) in the fallback insert:

```php
// CORRECT: prepare clean object before API call
$quiz_clean = new stdClass();
$quiz_clean->course = $quiz->course;
$quiz_clean->name = $quiz->name;
$quiz_clean->intro = $quiz->intro;
// ... copy all fields you know belong to the DB table ...
$quiz_clean->reviewoverallfeedback = 0;  // include any easy-to-miss NOT NULL fields
$quiz_clean->attemptonlast = 0;

$quiz->id = 0;
try {
    $quiz->id = framework_add_instance($quiz, null);   // may mutate $quiz
    echo "Created via API\n";
} catch (Throwable $e) {
    echo "API failed: " . $e->getMessage() . "\n";
    try {
        $quiz->id = $DB->insert_record('quiz', $quiz_clean);  // use clean copy
        echo "Created via direct insert\n";
    } catch (Throwable $e2) {
        echo "Direct insert also failed: " . $e2->getMessage() . "\n";
    }
}
if ($quiz->id) {
    // proceed with course_module setup
} else {
    echo "WARNING: Creation failed entirely\n";
}
```

**How to discover which fields are contaminating the object**: Add debug output in the inner catch:
```php
if (property_exists($e2, 'debuginfo')) { echo "SQL attempted: " . $e2->debuginfo . "\n"; }
```
The printed SQL will show the exact column list being inserted, revealing which extra properties were added by the failed API call.

**Diagnosing missing NOT NULL fields**: If the direct insert fails with "Error writing to database" even with a clean copy, run a diagnostic to find required fields:
```bash
# In the live VM, check for NOT NULL columns without defaults
mysql -u moodleuser -pmoodlepass moodle -e "DESCRIBE mdl_quiz" 2>/dev/null | awk '$4=="NO" && $5=="" {print $1}'
```
Any column listed must be explicitly included in `$quiz_clean`.

**Applies to**: Any `setup_task.sh` for a web application framework that supports CLI bootstrapping. Moodle, WordPress, Drupal, Magento, and similar PHP applications all exhibit this pattern. Python frameworks (Django `manage.py shell`, Flask with app context) have the same structure but object mutation is less common because Python's duck-typing makes it easier to pass clean dicts.

---

### Do Not Score Verifier Criteria for State That Setup Creates

**The Problem**: `setup_task.sh` creates the task's "problem state" — a broken gradebook, empty question categories, a course with no completion configured, etc. If any verifier scoring criterion checks for the EXISTENCE of something that `setup_task.sh` creates (categories, courses, users, configuration settings, enabled features), the do-nothing test returns a non-zero score. This is wrong: the agent did nothing, but the verifier rewards the setup work.

**Classic mistake**: A `build_question_bank_and_quiz` task where:
- `setup_task.sh` creates "Probability Basics" and "Descriptive Statistics" question categories
- Verifier Criterion 1: "Probability Basics category exists → 5 pts; Descriptive Statistics category exists → 5 pts"
- Do-nothing result: score=10 (wrong — agent did nothing)

The verifier is rewarding the setup, not the agent.

**Why this is different from Pattern 1 (Baseline Recording)**: Pattern 1 says "track changes from baseline, not absolute state." This lesson is a sharper version: if the thing being scored was created BY the setup script AS THE STARTING CONDITION, it is a prerequisite, not an achievement. Do not score prerequisites.

**The Fix**: Treat setup-created state as a prerequisite check (informational, 0 points). Only award points for what the agent builds ON TOP OF the setup state:

```python
# BAD: awards points for what setup created
prob_cat_found = result.get('prob_cat_found', False)
if prob_cat_found:
    score += 5   # setup created this — free points

# GOOD: category existence is a prerequisite, not an achievement
prob_cat_found = result.get('prob_cat_found', False)
if not prob_cat_found:
    feedback_parts.append("Probability Basics category NOT found (setup error)")
    # May skip further checking for this category
else:
    feedback_parts.append("Probability Basics category found (pre-existing setup)")
    # Score is 0 for this; only score what the agent adds to the category:
    if result.get('prob_question_count', 0) >= 3:
        score += 20   # agent added questions — this IS an achievement
```

**Quick audit**: For every scoring criterion in a verifier, ask: "Would this criterion give points in the do-nothing test?" If yes, either (a) make it 0 points and informational-only, or (b) gate it on something the agent must do (e.g., not just "category exists" but "category has questions that agent added").

**The test**: After writing any verifier, always run the do-nothing test and confirm `score == 0`. If `score > 0`, work backward through the criteria to find which one is rewarding pre-existing setup state.

**Applies to**: Any task where setup_task.sh creates entities the agent is expected to work with — question categories, course structures, user accounts, enabled features, template files. The rule: if setup creates it as the starting condition, the verifier must not score its existence.

---

### Container Port Scope Must Cover All Task Ports at Environment Startup

**The Problem**: When an environment uses containerized services (Docker, Podman, etc.) started by a hook script (`setup_<env>.sh`), the port mappings are fixed at container startup time via `-p host_port:container_port` flags. If you later create new tasks that need additional ports not in the original mapping, the environment setup script must be updated — but this is easy to forget because the new task's own `setup_task.sh` has no mechanism to change the container's port bindings after it is already running.

**Classic mistake**: An environment starts a container with `-p 6661:6661 -p 6662:6662 -p 6663:6663` because the first three tasks use those ports. A fourth task is created that needs port 6664. The task works perfectly in isolation when the container is re-launched, but fails silently in the CI pipeline because the deployed container was started with the old port list.

**The Fix**: When adding a new task to an existing containerized environment, always check the environment's startup script (`setup_<env>.sh` or the equivalent `docker run` command) and add the new task's port(s) before the new task goes live:

```bash
# In setup_<env>.sh — maintain a cumulative port list covering ALL tasks
docker run -d \
  -p 6661:6661 \   # Task 1
  -p 6662:6662 \   # Task 2
  -p 6663:6663 \   # Task 3
  -p 6664:6664 \   # Task 4 (added when Task 4 was created)
  -p 6665:6665 \   # Task 5 (added when Task 5 was created)
  ...
  my-service-image
```

**Why this is easy to miss**: Task creation is usually focused on `task.json`, `setup_task.sh`, `export_result.sh`, and `verifier.py` — all inside the task's own directory. The environment-level startup script lives in a different location and is easy to overlook. The failure mode is also subtle: the container starts and appears healthy, but connections to the new port are refused with `Connection refused` rather than any environment-level error.

**Checklist item to add**: After writing `task.json` and identifying the task's port(s), immediately check the environment startup script and confirm those ports are already in the `-p` mapping. If they are not, add them before proceeding.

**Applies to**: Any task environment where services are started in Docker or Podman containers with explicit port mappings at container launch time — HL7 integration engines, database containers with exposed ports, message brokers, REST API servers, or any service where agent access goes through a host-side port binding. Does not apply to environments where tasks access services via internal container networks or DNS names without host-side port exposure.

---

### Multi-Component Dependency Order Must Be Documented in Task Descriptions

**The Problem**: Some tasks require the agent to create or deploy multiple interdependent components where component A's configuration must reference component B's runtime-generated identifier (UUID, internal ID, auto-assigned URL, registration key, etc.). If the task description does not explicitly state the required creation order, the agent may attempt to configure A before B exists, encounter a cryptic error or create a broken reference, and struggle to diagnose the root cause.

**Examples of this pattern across different domains**:
- *Integration engines*: A facade channel must route to a downstream channel via the downstream channel's UUID — the downstream channel must be deployed first so its UUID is available.
- *Microservices / API gateways*: A gateway route must reference a backend service's registered service ID — the service must be registered before the route can be created.
- *OAuth / SSO*: A client application must reference an OAuth server's issuer URL or client secret that is only assigned after the server resource is created.
- *Container orchestration*: A Kubernetes ConfigMap must reference a Secret's name, and the Secret must exist before the ConfigMap is applied.
- *CI/CD pipelines*: A pipeline trigger must reference a webhook's auto-generated token, which is only issued when the webhook is registered.

**The Fix**: In the task description (`task.json` or README.md), state the dependency order explicitly:

```
Architecture note: Two-channel design. Channel B (downstream processor) must be
deployed FIRST to obtain its UUID. Channel A (intake router) then references
Channel B's UUID in its Channel Writer destination. Attempting to deploy A first
will result in an unresolvable channel reference.
```

This applies equally to `README.md` "Edge Cases" sections:
```markdown
## Edge Cases
- **Deployment order matters**: Deploy the downstream channel (Channel B) before
  the upstream router (Channel A). Channel A's configuration requires Channel B's
  UUID, which is only available after Channel B is deployed.
```

**Why this is a task design responsibility, not an agent responsibility**: The dependency order is an architectural fact that the task creator knows and the agent must discover — often through trial and error, which wastes steps. Documenting it is not "giving away the answer": the agent still must understand how to look up the UUID, how to reference it correctly, and how to configure both components. The order hint removes a roadblock that adds no real difficulty.

**Verify your own documentation**: After writing the task, ask yourself: "Can the agent create all required components in any order and still succeed?" If the answer is no, the documentation must state the correct order.

**Applies to**: Any multi-component task where component A's configuration must reference a runtime-generated identifier from component B. Particularly common in integration engines, API management platforms, microservice orchestration, identity/auth systems, and any task where inter-component references use opaque system-generated IDs rather than human-readable names chosen by the agent.

---

### DDL Dependency Ordering in Relational Databases: Drop Dependents Before the Object

**The Problem**: In relational databases (MySQL, PostgreSQL, Oracle, SQL Server), DDL statements that remove an object — `DROP INDEX`, `DROP TABLE`, `DROP COLUMN` — fail silently when another object depends on the one you want to remove. The most common case in MySQL is `DROP INDEX` on an index that backs a `FOREIGN KEY` constraint: MySQL refuses to drop the index because removing it would leave the FK without enforcement support. When the error is suppressed with `2>/dev/null`, the script continues as if the drop succeeded — but the index is still there.

**What breaks**:
```bash
# WRONG — silently fails if idx_fk_customer_id backs a FK constraint
mysql -u root -p'password' mydb -e "DROP INDEX idx_fk_customer_id ON rental;" 2>/dev/null
# Script continues, prints "Setup complete", but the index is NOT gone.
# Do-nothing test then finds the index and awards points → score > 0 when it should be 0.
```

**The Fix**: Always drop dependent objects before the object they protect, in the correct order. For MySQL FK-backed indexes:
1. Find the FK constraint name dynamically from `information_schema.KEY_COLUMN_USAGE`
2. Drop the FK constraint with `ALTER TABLE ... DROP FOREIGN KEY`
3. Then drop the index with `DROP INDEX`

```bash
drop_fk_and_index() {
    local table=$1
    local column=$2

    # Step 1: Find the FK name dynamically (don't hardcode it — it varies by MySQL version)
    local fk_name
    fk_name=$(mysql -u root -p'password' information_schema -N -e "
        SELECT CONSTRAINT_NAME FROM KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA='mydb' AND TABLE_NAME='${table}'
          AND COLUMN_NAME='${column}' AND REFERENCED_TABLE_NAME IS NOT NULL
        LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    # Step 2: Drop the FK first
    if [ -n "$fk_name" ]; then
        mysql -u root -p'password' mydb -e "
            ALTER TABLE ${table} DROP FOREIGN KEY \`${fk_name}\`;
        " 2>/dev/null && echo "Dropped FK: ${fk_name}" || true
    fi

    # Step 3: Now safe to drop the index
    local idx_name
    idx_name=$(mysql -u root -p'password' information_schema -N -e "
        SELECT INDEX_NAME FROM STATISTICS
        WHERE TABLE_SCHEMA='mydb' AND TABLE_NAME='${table}'
          AND COLUMN_NAME='${column}' AND SEQ_IN_INDEX=1
          AND INDEX_NAME != 'PRIMARY'
        LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    if [ -n "$idx_name" ]; then
        mysql -u root -p'password' mydb -e "
            DROP INDEX \`${idx_name}\` ON ${table};
        " 2>/dev/null && echo "Dropped index: ${idx_name}" || true
    fi
}
```

**Generalizes beyond MySQL**: The same principle applies to:
- PostgreSQL: `DROP TABLE` fails if other tables have FK references to it — drop the referencing tables first
- SQL Server: `DROP COLUMN` fails if the column participates in an index — drop the index first
- Oracle: `DROP CONSTRAINT` order matters when constraints reference each other
- Any database: always inspect the dependency tree before issuing DDL that removes a schema object

**Verification is mandatory**: Never trust `2>/dev/null` DDL. After any schema-modification block, re-query `information_schema` (or equivalent) to confirm the object was actually removed. A count of "remaining objects" should equal zero if all drops succeeded.

**Always use dynamic lookup, not hardcoded names**: FK constraint names and index names are assigned by the database engine at creation time and may differ across MySQL versions, installations, or after a schema reload. Query `information_schema` to get the current name rather than hardcoding a name you read from documentation.

**Applies to**: Any `setup_task.sh` that uses DDL to drop indexes, constraints, or tables as part of creating the degraded starting state for a task. Particularly critical in database performance/optimization tasks where dropping indexes is the core setup action.

---

### Reset Sample Databases to a Known Baseline Before Injecting Data Quality Issues

**The Problem**: Standard sample databases (MySQL's Sakila and World, Chinook, Northwind, AdventureWorks, etc.) may contain pre-existing data quality issues — duplicate records, null values, orphaned rows — from prior use, prior task runs, or from the database's original design. When your task requires injecting a **specific count** of data quality issues (e.g., "inject 3 duplicate city records"), any pre-existing issues of the same type add to your count, making the task's expected state unpredictable.

**What breaks**:
```bash
# You inject 3 duplicate cities expecting total duplicates = 3
mysql mydb -e "INSERT INTO city VALUES (5000, 'London', 'GBR', 'England', 7000000);"
mysql mydb -e "INSERT INTO city VALUES (5001, 'Paris',  'FRA', 'Île-de-France', 2200000);"
mysql mydb -e "INSERT INTO city VALUES (5002, 'Berlin', 'DEU', 'Berlin', 3500000);"

# But the world DB already had 1 pre-existing duplicate → total is 4, not 3
DUPE_COUNT=$(mysql -N -e "SELECT COUNT(*) - COUNT(DISTINCT Name, CountryCode, District) FROM city;")
# DUPE_COUNT=4 (expected 3) → wrong threshold → task difficulty changes unpredictably
```

**The Fix**: Before injecting issues, clean the specific data quality dimension you're testing down to zero, then inject your controlled set:

```bash
# Step 1: Remove all pre-existing duplicates (keep the record with the lowest ID)
mysql -u root -p'password' world -e "
    DELETE FROM city WHERE ID NOT IN (
        SELECT minid FROM (
            SELECT MIN(ID) AS minid
            FROM city
            GROUP BY Name, CountryCode, District
        ) t
    );
" 2>/dev/null || true

# Step 2: Now inject exactly 3 duplicates — total will be exactly 3
mysql world -e "INSERT INTO city VALUES (5000, 'London', 'GBR', 'England', 7000000);"
mysql world -e "INSERT INTO city VALUES (5001, 'Paris',  'FRA', 'Île-de-France', 2200000);"
mysql world -e "INSERT INTO city VALUES (5002, 'Berlin', 'DEU', 'Berlin', 3500000);"
```

**When to clean vs. when to record baseline**: Use baseline recording (Lesson 1 / "Record baseline counts") when the pre-existing values are stable and your verifier can subtract them. Use cleanup when the pre-existing values are variable (e.g., depend on prior task runs) or when you need an exact count for threshold logic.

**This applies to all data quality dimensions**:
- NULL values: `UPDATE table SET col = 'placeholder' WHERE col IS NULL` before injecting your own NULLs
- Orphan records: delete orphans before creating your controlled set of orphans
- Invalid values: fix all out-of-range values before injecting your N out-of-range values
- Duplicate rows: deduplicate before inserting your controlled duplicates

**How to discover pre-existing issues**: During Phase 4 testing, run the same diagnostic query your export script uses *before* injection, and check if the count is already non-zero. If it is, add a cleanup step to the setup script before injection.

**Applies to**: Any `setup_task.sh` that injects data quality issues (nulls, duplicates, invalid values, orphan records) into a shared or reused database. Critical for data cleanup/migration tasks where the exact count of issues is part of the verification logic.

---

### SQL Metadata Queries for Indexes Must Filter by Column Position, Not Just Column Name

**The Problem**: In MySQL/MariaDB, querying `INFORMATION_SCHEMA.STATISTICS WHERE COLUMN_NAME='col'` returns a row for **every index that includes that column** — including composite (multi-column) indexes where the column appears as the second, third, or later component. This means a check for "does a standalone index on `customer_id` exist?" returns `true` even when only a composite UNIQUE index like `(rental_date, inventory_id, customer_id)` is present. The false positive causes `export_result.sh` to award points for indexes the agent never created.

**What breaks**:
```bash
# WRONG — counts any index that happens to contain customer_id as any component
IDX_COUNT=$(mysql information_schema -N -e "
    SELECT COUNT(DISTINCT INDEX_NAME) FROM STATISTICS
    WHERE TABLE_SCHEMA='mydb' AND TABLE_NAME='rental'
      AND COLUMN_NAME='customer_id' AND INDEX_NAME != 'PRIMARY'
" 2>/dev/null)
# Returns 1 due to the composite UNIQUE KEY (rental_date, inventory_id, customer_id)
# even when the standalone index on customer_id alone was never created → score > 0
```

**The Fix**: Add two conditions to select only standalone, single-column indexes:
1. `SEQ_IN_INDEX = 1` — the column must be the leading (first) component of the index
2. A subquery checking that the index has exactly one column total (count of all components = 1)

```bash
# CORRECT — counts only standalone single-column indexes on customer_id
count_standalone_index() {
    local tbl=$1
    local col=$2
    mysql -u root -p'password' information_schema -N -e "
        SELECT COUNT(DISTINCT s1.INDEX_NAME)
        FROM STATISTICS s1
        WHERE s1.TABLE_SCHEMA='mydb' AND s1.TABLE_NAME='${tbl}'
          AND s1.COLUMN_NAME='${col}' AND s1.SEQ_IN_INDEX=1
          AND s1.INDEX_NAME != 'PRIMARY'
          AND (
            SELECT COUNT(*) FROM STATISTICS s2
            WHERE s2.TABLE_SCHEMA='mydb' AND s2.TABLE_NAME='${tbl}'
              AND s2.INDEX_NAME = s1.INDEX_NAME
          ) = 1
    " 2>/dev/null | tr -d '[:space:]'
}
```

**The same issue applies to setup scripts**: When `setup_task.sh` queries `STATISTICS` to verify that an index was successfully dropped, it must use the same two-condition filter. Otherwise, the composite index that shares the column name will make the drop look like it failed.

**Generalizes to other catalog queries**: The principle is: *catalog/metadata tables are more permissive than they appear*. Whenever you query a metadata catalog to verify the presence or absence of a schema object, understand the exact semantics of each condition you're filtering on:
- PostgreSQL `pg_index`: check `indkey` array position or use `pg_attribute` join with `attnum`
- SQL Server `sys.index_columns`: check `key_ordinal = 1` and `column_id` count per index
- Any DB: verify that your filter conditions produce exactly the set of objects you intend — test with a known schema before relying on it in production

**How to discover you have this problem**: During do-nothing testing, if `export_result.sh` reports a non-zero count for an index that was supposedly dropped (and the drop appeared to succeed), query `INFORMATION_SCHEMA.STATISTICS` directly and check `SEQ_IN_INDEX` values for all rows matching your column name. If you see rows with `SEQ_IN_INDEX > 1`, a composite index is causing the false positive.

**Applies to**: Any `setup_task.sh` or `export_result.sh` that queries `INFORMATION_SCHEMA.STATISTICS` (MySQL/MariaDB) or equivalent catalog tables to verify the presence or absence of indexes on specific columns. Most common in database performance optimization tasks where adding/removing specific indexes is the core deliverable.

---

## Lesson 160: Use an Authenticated API Call — Not an HTTP Probe — as the Service Readiness Check for Web-App Environments

**The Problem**: Lesson 57 recommends polling a service health endpoint until it returns HTTP 200 before recording baselines. This is correct for many environments. But for environments where `setup_task.sh` authenticates to an API (XML-RPC, REST JSON-API, GraphQL, JSON-RPC) before creating task data, polling for HTTP 200 is **not sufficient**. Many web application servers return HTTP 200 from a loading-spinner page, a "database not yet initialized" page, or a maintenance-mode redirect — all long before the underlying application is ready to serve authenticated requests.

**Concrete failure mode**:
```bash
# Appears to confirm Odoo is ready — but doesn't
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null && break
    sleep 3
done

python3 << 'PYEOF'
import xmlrpc.client
common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
uid = common.authenticate('mydb', 'admin@example.com', 'admin', {})
# Returns False (uid=0) because Odoo's database is still loading demo data
# even though the HTTP probe above succeeded
if not uid:
    sys.exit(1)   # setup fails silently
PYEOF
```

The curl to `/xmlrpc/2/common` returns HTTP 200 from Odoo's static routing layer. The database initialization (including demo data import for ERP systems) is still running in the background. The `authenticate()` call returns `False` immediately, the setup script exits 1, and no task data is created.

**The Fix**: Replace the HTTP probe with the actual authentication call as the readiness check. Retry until authentication *succeeds*, not until the endpoint returns HTTP 200:

```bash
echo "Waiting for authenticated API access..."
MAX_WAIT=120
INTERVAL=5
ELAPSED=0
READY=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    AUTH_RESULT=$(python3 -c "
import xmlrpc.client, sys
try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate('odoo_demo', 'admin@example.com', 'admin', {})
    print('ok' if uid else 'auth_failed')
except Exception as e:
    print('error')
" 2>/dev/null)

    if [ "$AUTH_RESULT" = "ok" ]; then
        echo "API authentication succeeded after ${ELAPSED}s"
        READY=1
        break
    fi
    echo "  Not ready yet (${AUTH_RESULT}), waiting... ${ELAPSED}s"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $READY -eq 0 ]; then
    echo "ERROR: Could not authenticate to API after ${MAX_WAIT}s"
    exit 1
fi

# NOW run the rest of setup — the API is confirmed ready
```

**Why this matters beyond service startup**: Applications that initialize a database with demo data (ERP systems, CRM platforms, business intelligence tools) perform that initialization asynchronously. The web server becomes accessible long before the database is usable. If the post_start hook snaps a QEMU checkpoint immediately after the web server starts responding, the restored checkpoint may still have an incomplete database. Retrying authentication until it succeeds ensures the checkpoint is taken (or the pre_task hook runs) only when the application is genuinely ready.

**Rule**: For any web-app environment where `setup_task.sh` connects to an application API using credentials, replace the HTTP-200 health probe with a test authentication call. Retry the full auth call until it succeeds or times out. Only then proceed with task data creation.

**Applies to**: Any environment where setup scripts programmatically call a web application API that requires authentication — Odoo XML-RPC, SuiteCRM REST, LibreHealth FHIR, OpenEMR API, Moodle web services, Jenkins REST, GitLab API, JIRA REST, Redmine API, ManageEngine API, and similar. Does NOT apply to database-direct environments (MySQL, PostgreSQL) where the health check is `mysql -e "SELECT 1"`.

---

## Lesson 161: For ERP, CRM, and Business-Process Software, the Bundled Demo Database Is Your Primary Real-Data Source

**The Problem**: Principle 2 ("Real Data — No Exceptions") prohibits creating synthetic records with scripts. For scientific or creative software, "real data" means using sample datasets from `File > Open Samples` or from public repositories (Lesson 14, Lesson 57 context). For ERP, CRM, accounting, and business-process software, the equivalent is the **bundled demo database** — a curated set of realistic companies, contacts, products, invoices, purchase orders, employees, and transactions that ships with the application.

Task creators sometimes misread Principle 2 to mean they must find a real external business dataset and import it. In practice, ERP demo databases (Odoo demo data, SuiteCRM demo data, Dolibarr demo data) ARE real data — they were constructed by domain experts to reflect realistic business operations. Using them fully satisfies Principle 2.

**What ERP demo databases typically contain (use this for task design)**:

| Record type | Examples from Odoo demo data |
|---|---|
| Companies & contacts | Existing vendors, customers, partner companies |
| Products | Products with real prices, categories, units of measure |
| Accounting | Chart of accounts, journals, tax definitions |
| Inventory | Warehouses, locations, product stock levels |
| Sales/Purchasing | Historical orders, confirmed POs, draft quotes |
| CRM | Pipeline stages, existing leads and opportunities |
| HR | Employees, departments, job positions |

**The correct pattern for ERP task setup**:

```python
import xmlrpc.client

# Step 1: Search the demo database for suitable records
vendors = models.execute_kw(DB, uid, PASSWORD, 'res.partner', 'search_read',
    [[['supplier_rank', '>', 0], ['is_company', '=', True]]],
    {'fields': ['id', 'name'], 'limit': 5})

# Step 2: Use the first real vendor found
if vendors:
    vendor_id = vendors[0]['id']   # ← REAL demo data record
    vendor_name = vendors[0]['name']
else:
    # Only create a new record if the demo data truly has none
    vendor_id = models.execute_kw(DB, uid, PASSWORD, 'res.partner', 'create',
        [{'name': 'Northgate Industrial Supplies', 'is_company': True, 'supplier_rank': 1}])
```

**The key distinction from Principle 2**: Creating a vendor named "Test Vendor" with a random phone number is fabricating data. Using `vendors[0]` from the demo database is using real (bundled) data. Creating a named vendor that represents a realistic business entity — not from the demo set, but with a specific real address, industry, and role that makes the task scenario coherent — is acceptable under the "aggregate statistics from published sources" special case only if every field comes from a verifiable source.

**When the demo database must be supplemented**: Some tasks require a scenario-specific setup that cannot be constructed purely from demo data:
- A vendor bill with a specific overcharge percentage (the overcharge is the task-specific scenario)
- An inventory count file with specific discrepancies (the discrepancies are the task-specific scenario)
- An employee expense sheet for a specific named employee (the employee name orients the agent)

In these cases, use demo records as the base (real vendor, real product from demo) and layer task-specific state on top (inflated price, specific count discrepancy). The task-specific parameters are the scenario, not the underlying business entities.

**Practical implication for task design**: Before brainstorming a task for an ERP environment, first query the demo database to understand what's there. Run searches via the API for vendors, customers, products, employees, existing orders. Design tasks around what actually exists — not what you imagine should exist. This also ensures the task is testable, since the environment always starts from the same demo data state.

**Rule**: For ERP, CRM, and business-process environments, always search the bundled demo database first. Use existing demo records wherever possible. Only create new records when the task scenario genuinely requires an entity that the demo database does not have — and in that case, give the entity a specific realistic identity (not "Test Company" or "Sample Product") and document why demo data was insufficient.

**Applies to**: Odoo, SuiteCRM, Dolibarr, Vtiger, EspoCRM, ERPNext, Tryton, Metabase, Redash, and any other business-process application that ships a demo database with realistic sample records.

---

## Lesson 162: Section-Level Wrong-Target Gates for Multi-Entity Tasks

**The problem with global wrong-target gates**: Pattern 2 in `03_verification_patterns.md` returns `score=0` immediately when the wrong entity is detected. This is correct when the *entire* task concerns one entity (e.g., "update patient X's allergy list"). But for tasks that have **independent subtasks each involving potentially different entities**, a global zero disproportionately punishes an agent that performed most of the task correctly.

**The scenario**: A task requires three independent actions:
1. Create a dispatch call at intersection A (no target person)
2. Issue a citation to **person A** for a specific offense
3. File a BOLO for an unrelated suspect (no specific person required)

An agent that creates the call perfectly, issues the citation to **person B** by mistake, and creates the BOLO correctly has done 2 of 3 subtasks correctly. A global wrong-target gate would score this at 0. A section-level wrong-target gate scores it at (call pts) + 0 + (BOLO pts) — a fair partial score.

**Global gate vs. section-level gate — when to use each**:

| Situation | Correct gate type |
|-----------|------------------|
| Entire task centers on one entity (update this patient, modify this record) | **Global** — wrong entity → score=0 |
| Task has independent subtasks with different target entities | **Section-level** — wrong entity in subtask K → section K score=0, other sections unaffected |
| Primary subtask is a gate (no call → nothing else matters) | **Global gate for the primary subtask**, section-level for secondary subtasks |

**Implementation pattern** (section-level, not global):

```python
# SECTION 2: Citation for Person A (45 pts)
# Wrong-target gate: zeros ONLY this section, not the whole task
if not result.get('citation_found'):
    feedback_parts.append("No citation found")
else:
    if not result.get('person_a_citation_found'):
        # Zero this section — but DO NOT return early
        citation_name_id = result.get('citation', {}).get('name_id', '?')
        feedback_parts.append(
            f"Citation for wrong person (name_id={citation_name_id}, "
            f"expected Person A name_id=2) — citation section zeroed"
        )
        # score unchanged — other sections still scored below
    else:
        citation = result.get('citation', {})
        score += 10   # confirmed correct person
        # ... rest of citation criteria

# SECTION 3: BOLO (20 pts) — proceeds regardless of section 2 outcome
if not result.get('bolo_found'):
    feedback_parts.append("No BOLO found")
else:
    score += 20
    feedback_parts.append("BOLO created")
```

**Contrast with global gate** (keep for the primary entity-discovery gate):

```python
# SECTION 1 — PRIMARY GATE: If no call exists, nothing else matters
if not result.get('call_found'):
    return {"passed": False, "score": 0, "feedback": "No dispatch call found"}
# Only reaches here if a call was created
```

**Structuring the export JSON for section-level gates**: The export script must produce per-section boolean flags, not just a single `target_found`. For example:

```bash
# export_result.sh — separate flags per subtask entity
PERSON_A_CITATION_FOUND=false
PERSON_B_WARRANT_FOUND=false

if [ -n "$CITATION_RESULT" ]; then
    CITATION_NAME_ID=$(echo "$CITATION_RESULT" | cut -f1)
    if [ "$CITATION_NAME_ID" = "2" ]; then PERSON_A_CITATION_FOUND=true; fi
fi
```

**Validating section-level gates in offline mock tests**: The wrong-target mock test must verify **both** that the wrong section scores 0 AND that other sections still score normally. Inject a result where one section has the wrong entity but other sections are correct, then check:

```python
# Wrong-target for citation section only
wrong_target_result = {
    "call_found": True,
    "call": {"type": "10-38", "street1": "Forum Drive", "street2": "Strawberry Ave"},
    "citation_found": True,
    "person_a_citation_found": False,   # ← wrong person
    "citation": {"name_id": 99},
    "bolo_found": True,                 # ← correct BOLO
    "bolo": {"description": "gray hoodie, athletic build"}
}
result = verify_fn([], mock_env(wrong_target_result), task_info)

# Expected: call pts + 0 (citation zeroed) + bolo pts = 35 + 0 + 20 = 55
assert result['score'] == 55, f"Expected 55, got {result['score']}"
assert result['passed'] == False
```

**Why this matters for task difficulty**: Section-level gates allow tasks to have multiple independent, verifiable subtasks without the all-or-nothing fragility of global wrong-target gates. This makes scoring fairer for partially-correct agents and gives more informative signal about which subtasks were handled correctly. It also enables genuinely harder tasks where the agent must correctly handle multiple distinct entities — without making any single misidentification catastrophically penalize the entire score.

**Applies to**: Any multi-subtask task where the subtasks involve different target entities — CAD/dispatch systems (call + citation + BOLO), EHR (create patient + schedule appointment + add prescription for the patient), CRM (create account + create contact for different company + create opportunity), ticketing (create ticket + assign to person A + link to project B). Use a global gate only when the task has a single central entity or when identifying the wrong entity in any subtask makes ALL other work meaningless.

---

### 41. Search Multiple Directories for Agent Output Files

**The Problem**: Tasks that require the agent to export or save a result file cannot always dictate the exact save path. Different agents have different behaviors: one might save to the app's default export folder, another to the Desktop, another to the home directory, another to `/tmp`. If `export_result.sh` only checks one specific path, it misses files saved elsewhere and reports a false negative — the task appears failed even though the agent did the right work.

**The Pattern**: Search a prioritized list of likely directories using mtime-based filtering. Try each candidate file, accept the first one created after the task started:

```bash
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_FILE=""
RESULT_FILE_SIZE=0

# Search in order: task-specific folder, Desktop, home dir, /tmp
for search_dir in "/home/ga/app_results" "/home/ga/Desktop" "/home/ga" "/tmp"; do
    for candidate in "$search_dir"/*.csv "$search_dir"/*.xlsx "$search_dir"/*.txt; do
        [ -f "$candidate" ] || continue
        FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            RESULT_FILE="$candidate"
            RESULT_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
            break 2
        fi
    done
done
```

**Why this is robust**:
- The `mtime > task_start` filter ensures only files created by the agent are considered, not pre-existing files with similar names
- The prioritized directory order means the task-specific folder wins if the agent followed instructions, but the search degrades gracefully if it didn't
- Works regardless of what the agent names the file

**Important**: Use integer comparison throughout. `stat -c %Y` returns an integer (seconds since epoch), same as `date +%s`. Do NOT use `os.path.getmtime()` in Python for this comparison without casting to `int` first (see Lesson 15).

**When NOT to use this**: If the task requires the agent to save to a *specific named path* as part of the task deliverable (e.g., "save as `/home/ga/report.csv`"), check only that exact path. The multi-directory search is for tasks where the output path is unspecified or flexible.

**Applies to**: Any `export_result.sh` for a file-creation task where the agent is not given a mandatory save path. Especially common in desktop analysis tools (LCA software, GIS tools, data analysis apps) and creative applications that have their own default export locations.

---

### 42. Capture UI State Before Closing the Application

**The Problem**: Many export scripts need to close the running application before querying its database (Lesson 28, Lesson 35). A common mistake is closing the application at the top of the script and then trying to check window titles or log evidence. Once the application process exits, its window entry disappears from the window manager — `wmctrl -l` will no longer show it, and any in-memory state is gone. This means "application ran and showed results" evidence is permanently lost.

**What breaks**:
```bash
# BAD ORDER: close first, then try to read UI state
close_openlca          # ← app exits here
sleep 3
WINDOWS=$(DISPLAY=:1 wmctrl -l)
# WINDOWS is now empty — the app's window is gone!
echo "$WINDOWS" | grep -qi "result\|lcia" && RESULTS_VISIBLE="true"
# ↑ always false, even if the agent was looking at results
```

**The Correct Order**:
```bash
# GOOD ORDER: capture all UI evidence FIRST, then close
# Step 1: Screenshot (while app may be running)
take_screenshot /tmp/task_end_screenshot.png

# Step 2: Window title evidence (while app is running)
WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "$WINDOWS" | grep -qi "result\|lcia" && RESULTS_VISIBLE="true"

# Step 3: Log file evidence (still accessible after close)
grep -qi "calculat\|LCIA" /tmp/app.log 2>/dev/null && CALC_IN_LOG="true"

# Step 4: NOW close the application
close_openlca
sleep 3

# Step 5: Query database (safe now that app is closed)
PS_COUNT=$(derby_count "$DB_PATH" "PRODUCT_SYSTEMS" 2>/dev/null)
```

**Why log files are different**: Application log files written to disk (e.g., `/tmp/app.log`, `/home/ga/.app/app.log`) persist after the app closes and can be read at any point. Window titles and in-memory state do not persist. Screenshot captures are also safe to take at any time (they capture the current display state), but for the best result, take them before the app window closes.

**Rule**: In any `export_result.sh` that calls `close_app` (or `pkill`), the order must always be: (1) screenshot, (2) window/UI checks, (3) in-memory log/state checks, (4) close app, (5) database queries.

**Applies to**: Any environment where `export_result.sh` both queries an app's database AND checks the app's window state as a verification signal. Includes all desktop apps that use embedded databases (Derby, SQLite, H2) and any app where `wmctrl -l` window titles provide evidence of what the agent was doing.

---

### 43. Read Existing Tasks Before Creating New Ones for the Same Environment

**The Problem**: The checklist template (and this document's patterns) are generic starting points. Every environment has developed its own conventions over time — result file paths, JSON field names, utility function signatures, scoring weight ranges — that may differ from the template. Creating new tasks from templates alone without reading existing tasks in the same environment produces inconsistencies: different result file paths, mismatched utility function calls, incompatible JSON structures.

**Classic examples**:
- Template says result file is `/tmp/<task_name>_result.json`; actual environment uses a shared `/tmp/task_result.json` for all tasks
- Template shows `source /workspace/scripts/task_utils.sh`; actual environment uses `/workspace/scripts/task_utils.sh` with a different function signature
- Template uses `copy_from_env("/tmp/result.json", ...)` in the verifier; existing tasks use `copy_from_env("/tmp/task_result.json", ...)`
- Template uses `db_query()` helper; existing environment uses `derby_count()` with a specific argument convention

**The Fix**: Before writing any new task file, read at least one complete existing task:

```bash
# Read before writing — for any new task in environment X:
cat benchmarks/cua_world/environments/<env_name>/tasks/<existing_task>/export_result.sh
cat benchmarks/cua_world/environments/<env_name>/tasks/<existing_task>/verifier.py
cat benchmarks/cua_world/environments/<env_name>/scripts/task_utils.sh
```

Look specifically for:
1. **Result file path**: What path does `export_result.sh` write to? What path does `verifier.py` copy from?
2. **Utility function names and signatures**: What functions does `task_utils.sh` export, and how are they called?
3. **JSON field naming conventions**: Are booleans stored as `0`/`1` integers or `true`/`false` strings?
4. **VLM integration pattern**: How does the existing verifier call `query_vlm`, `sample_trajectory_frames`, `get_final_screenshot`?
5. **Scoring weight norms**: What point values do existing tasks use for common criteria (DB import, file export, content quality)?

**Rule**: The authoritative reference for any environment's conventions is its existing task code, not the generic template. Templates are a starting point; existing tasks are ground truth. Always reconcile new tasks against at least one complete existing task before testing.

**Exception**: For a brand-new environment with no existing tasks, the generic template IS the convention. Document your choices in the first task as the convention for all subsequent tasks in that environment.

**Applies to**: Every new task added to an existing environment. The cost of 5 minutes of reading is far less than the cost of debugging mysterious `FileNotFoundError` or `KeyError` failures caused by a mismatched result file path.

---

### 44. `exec_in_env` Is a Valid Primary Verification Strategy for SQL-Backed Web Apps

**The Problem**: The standard verification pipeline — `export_result.sh` writes a JSON file, verifier calls `copy_from_env` to retrieve it, then parses fields — works well for file-output tasks and desktop applications. But for web applications backed by a SQL database where `exec_in_env` is available, this pipeline adds unnecessary complexity: the export script must correctly escape shell-within-SQL strings, bash heredocs can silently corrupt multi-line output, and the JSON-generation step is a source of bugs (missing quotes, unescaped characters, boolean capitalization mismatches).

**The Better Approach for DB-Backed Web Apps**: When `exec_in_env` is available, the verifier can query the database **directly**, skipping the export-JSON intermediary entirely:

```python
def verify_task(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env')
    if not exec_in_env:
        # Fall back to copy_from_env pattern or VLM
        ...

    # Query the DB directly — no export JSON needed
    result = exec_in_env(
        "mysql -u app_user -p'app_pass' mydb "
        "-e \"SELECT col1, col2 FROM table WHERE id=X\" 2>/dev/null"
    )
    # Parse tab-separated output: first line = headers, subsequent = values
    lines = result.strip().split('\n')
    if len(lines) >= 2:
        headers = lines[0].split('\t')
        values  = lines[1].split('\t')
        row = dict(zip(headers, values))
```

**Why this is better**:
1. **Tamper-resistant**: The export script runs inside the VM where a sophisticated agent could modify it. `exec_in_env` queries are issued from outside the VM by the verifier — the agent cannot intercept or manipulate them.
2. **Simpler export scripts**: `export_result.sh` only needs to capture a screenshot and record basic state. The verification logic lives entirely in `verifier.py`.
3. **Ad-hoc flexibility**: The verifier can issue different queries for different criteria without redesigning the export format.
4. **No shell-escaping bugs**: Complex SQL JOINs with multi-field WHERE clauses are error-prone to embed in bash heredocs. Python f-strings are cleaner.

**When `export_result.sh` is still needed**: Always run it to capture a screenshot and record a visible end-state. Even if the verifier queries the DB directly, the screenshot provides audit evidence and the export hook must exist in `task.json`. Just keep it lightweight — screenshot + basic DB state dump as text, no JSON serialization required.

**The VLM fallback pattern still applies**: If `exec_in_env` is `None` (e.g., test harness doesn't inject it), fall back to `copy_from_env` + JSON or VLM screenshot analysis. Always guard with `if exec_in_env:`.

**Applies to**: Any environment where the application writes its data to a SQL database accessible via command-line tools (MySQL, PostgreSQL, SQLite), and where `exec_in_env` is injected into `env_info`. Confirmed working for MariaDB/MySQL environments. Does NOT apply to NoSQL backends, file-based state, or environments where only `copy_from_env` is available.

---

### 45. CRUD-Dominant Software: Difficulty Comes from Entity-Linking, Not Discovery

**The Problem**: The standard difficulty framework (Lesson in `01_core_principles.md`) defines task hardness primarily by **discovery burden** — does the agent need to find which records are wrong, or are they given explicitly? This model is calibrated for analytical and repair/fix workflows (EHR correction, data quality remediation, configuration audits). For Student Information Systems, CRM platforms, ERP systems, and other CRUD-dominant applications, this model misapplies: these systems are inherently creation-oriented, and every realistic task necessarily specifies what to create. You cannot ask an agent to "discover which student to enroll" — enrollment IS the task.

**The Correct Difficulty Axis for CRUD Software**: For SIS/CRM/ERP systems, difficulty should be calibrated by **entity-linking complexity across UI modules**:

| Factor | Low Difficulty | High Difficulty |
|--------|---------------|-----------------|
| Number of UI modules required | 1 (e.g., enter a grade) | 3+ (e.g., create staff → create course → enter grades) |
| Entity relationships | Single entity, no FK deps | Multi-entity with foreign key links (student → course → grade) |
| Whether agents are given UI path | Step-by-step navigation spelled out | Goal stated, agent must discover navigation |
| Error tolerance | One field to fill | Multiple forms, each with multiple fields |
| Dependency ordering | No dependencies | Subtask A must complete before B can reference it |

**Key implication**: A "hard" task for a SIS that spans **3+ linked UI modules with no navigation hints** is genuinely harder than a "very_hard" single-module repair task in the same system, because the agent must:
1. Discover the right UI section for each entity type independently
2. Complete each form correctly (often 5–10 fields each)
3. Navigate back to a different section to link the entities
4. Repeat for each dependent entity in the correct FK order

**Do not downgrade difficulty because values are explicit**: Providing the agent with "create course BIO401, subject: Science, grade 12, credits 1.0" is not a difficulty reduction — it is the specification of ground truth needed for verification. The agent still has no idea which menu to use, which form to fill, or how to link the course to a grade entry. Explicit target values are required for creation tasks to be verifiable at all.

**Practical guidance for task design in CRUD software**:
- **"Hard"** in CRUD software = create 1 entity with correct fields, no UI path given
- **"Very hard"** in CRUD software = create 3+ linked entities across separate modules, no UI path given, entities must be correctly associated via FK relationships in the application
- The "discovery" criterion from `01_core_principles.md` applies to analytical/repair software; substitute "entity-linking complexity" for CRUD software

**Applies to**: Student Information Systems (SIS), Customer Relationship Management (CRM), Enterprise Resource Planning (ERP), Practice Management Systems, Learning Management Systems (LMS), and any other software where the primary workflows are data entry and record creation rather than data analysis or error correction.

---

### 46. A Product Row in `master_dataset.csv` With All Empty Fields Is Equivalent to "Not Found"

**The Problem**: The occupation lookup step (Step 0 in `07_agent_prompt_template.md`) says: *"If the product is not found in `selected_products.csv` or `master_dataset.csv`, skip this step and rely on your own knowledge of the software."* This covers the case where no row exists for the product. But there is a second, easily missed case: the product **is** found (a row exists with a matching `product` column) but every occupation-level field (`onetsoc`, `occupation_title`, `onet_importance`, `product_gdp_usd`, `category_rationale`, etc.) is empty or null. This happens for niche or newly-added products that have not yet been linked to O*NET occupation data.

**Example**: OpenICE (`Medical device interfaces`) has a row in `master_dataset.csv` with `product: "OpenICE"` but all occupation columns are blank — the row only carries `category`, `category_total_gdp_usd`, `os_platforms`, and a handful of metadata fields.

**What happens if you don't handle it**: You find the row, iterate over it expecting occupation data, and silently proceed with `occupation_title = ""`, `product_gdp_usd = 0.0` for every "occupation." Sorting by GDP and taking the top-5 gives you five identical empty rows. Any tasks derived from this would not reflect real professional workflows.

**The Fix**: After the lookup loop, check whether any row actually has occupation data before using it:

```python
rows = [r for r in csv.DictReader(f)
        if r["product"].strip().lower() == product_name.lower()]
rows = [r for r in rows if r.get("occupation_title", "").strip()]  # filter empty rows
rows.sort(key=lambda r: float(r["product_gdp_usd"] or 0), reverse=True)

if not rows:
    # Treat as "not found" — rely on domain knowledge
    print("No occupation data found. Proceeding with domain knowledge.")
else:
    for r in rows[:5]:
        print(r["occupation_title"], r["category_rationale"])
```

**Rule**: "Product found with empty rows" = "product not found." In both cases, skip the data-driven occupation step and design tasks using your own knowledge of the software's industry context. Do not use empty-row data as if it were real occupation information — it contains no signal.

**Applies to**: Any task creation session where the occupation lookup finds the product name but returns rows with blank `occupation_title` / `product_gdp_usd` / `category_rationale` fields. Common for niche professional tools, medical software, and recently-added products.

---

### 47. Bidirectional Export↔Verifier Field Audit Catches Mismatches Before Any Testing

**The Problem**: `export_result.sh` writes a JSON file; `verifier.py` reads that JSON file. These two files are written separately and can silently drift out of sync:

- **Missing field** (critical): verifier calls `result.get('field_x', 0)`, but export never sets `field_x`. The verifier silently receives 0, giving the criterion 0 points in all scenarios — including full-completion scenarios where the agent did everything correctly. The task is unverifiable without realizing it.
- **Extra field** (harmless but signals drift): export writes `field_y` but verifier never reads it. Wasted bytes, but more importantly, may indicate the verifier was supposed to check something it doesn't.

Lesson 26 addresses one direction: derive mock test field names by grepping `result.get(` from the verifier. But it doesn't describe auditing the **reverse** direction: checking that what the export produces is actually read by the verifier.

**The Fix**: After writing both files, run this two-command audit before any testing:

```bash
# Direction 1: Fields the VERIFIER reads — must all be present in export JSON
grep "result.get(" benchmarks/cua_world/environments/<env>/tasks/<task>/verifier.py \
  | sed "s/.*result.get('\([^']*\)'.*/\1/" | sort > /tmp/verifier_fields.txt

# Direction 2: Fields the EXPORT writes — check which are unused by verifier
grep '".*": \$' benchmarks/cua_world/environments/<env>/tasks/<task>/export_result.sh \
  | sed 's/.*"\(.*\)": .*/\1/' | sort > /tmp/export_fields.txt

# Show what verifier reads but export doesn't write (CRITICAL — fix these):
comm -23 /tmp/verifier_fields.txt /tmp/export_fields.txt

# Show what export writes but verifier doesn't read (informational — review these):
comm -13 /tmp/verifier_fields.txt /tmp/export_fields.txt
```

Any output from the first `comm` is a **critical bug**: the verifier is reading a field that the export never sets, so that criterion will always return 0. Fix by adding the missing field to `export_result.sh`.

Output from the second `comm` is informational: exported but unused fields. These are harmless, but if there are many, check whether the verifier was supposed to use them and doesn't.

**When to run**: After writing the initial versions of `export_result.sh` and `verifier.py`, before any mock or live testing. Takes 30 seconds and prevents silent zero-scoring criteria that would only manifest as confusing verifier output after extensive testing.

**Applies to**: Every task where verification uses the export-JSON pipeline (`export_result.sh` → JSON → `copy_from_env` → `verifier.py`). Not needed for `exec_in_env`-based verifiers (see Lesson 44) which bypass the export JSON entirely.

---

### 48. Pre-Configured App State Invalidates "App State Changed" GUI Signals

**The Problem**: GUI evidence functions often include signals that compare the application's *current* state to its *default startup* state. For example, a signal might check whether the window title has moved past the "Welcome / Start Page" (indicating the user navigated away and started working), or whether a "recent connections" list is populated (indicating connections were used).

These signals are designed for tasks where the agent must navigate the app from a cold start. But if `setup_task.sh` pre-configures the application state — writing a `connections.json`, loading a specific project, or otherwise bypassing the default startup screen — then that signal becomes **always True** even before the agent does anything. The do-nothing test will return a non-zero GUI score, violating the Phase 5 requirement.

**Concrete example**: An Oracle SQL Developer task that calls `ensure_hr_connection()` in setup writes the `connections.json` file. SQL Developer then starts showing the Connections panel (not the Welcome Page). A `window_title_changed` signal that fires when the title is not "Welcome Page" is now unconditionally True at task start.

**How to identify these signals**: After writing your GUI evidence check, ask: "Would this signal be True immediately after `setup_task.sh` runs, before the agent does anything?" If yes, it is a setup-contaminated signal.

**The Fix — Use only action-requiring signals**:
- **Safe signals** (require explicit agent action): SQL/command history written to disk since task start, active database sessions opened *after* task start, recently modified/created output files, log entries written since task start, undo history count > 0
- **Unsafe signals** (can be True from setup pre-configuration alone): window title not matching default, recent-files list populated, application is running, connection list non-empty

```python
def _check_gui_usage(gui_evidence):
    # ONLY count signals that require explicit user action
    signals = 0
    if gui_evidence.get('sql_history_count', 0) > 0:   # queries executed since task start
        signals += 1
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:  # active DB sessions
        signals += 1
    if gui_evidence.get('mru_connection_count', 0) > 0:    # connections opened (only if MRU
        signals += 1                                        # is empty at setup time)
    # DO NOT count window_title_changed or similar "app is not at default screen"
    # signals if setup pre-configures the app away from its default screen
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), ...
```

**Rule**: After writing your GUI evidence check, run the do-nothing test. If the GUI score is non-zero, trace which signal fired and check whether `setup_task.sh` could have caused it. Remove any signal that fires due to setup actions.

---

### 49. Shell Utility Functions That Return Full JSON Key-Value Pairs — Embedding Trap

**The Problem**: When a shared utility function (e.g., `collect_gui_evidence()`) returns a *complete JSON key-value fragment* including the key name:

```
"gui_evidence": {
    "sql_history_count": 0,
    "mru_connection_count": 0,
    ...
}
```

And you then embed the variable in a heredoc JSON block with an *explicit key name*:

```bash
GUI_JSON=$(collect_gui_evidence)

cat > /tmp/result.json << EOF
{
  "some_field": true,
  "gui_evidence": $GUI_JSON    # BUG: "gui_evidence": "gui_evidence": {...}
}
EOF
```

The resulting JSON is **malformed** because the key appears twice: `"gui_evidence": "gui_evidence": {`. This silently breaks JSON parsing in the verifier (`json.JSONDecodeError`), making the verifier return score=-1 or None instead of a real score. The export script itself completes without errors, making the bug hard to spot.

**The Fix**: Match the embedding style to what the function returns.

If the function returns the full `"key": value` pair, embed it **without** repeating the key:

```bash
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {...fallback...}')

cat > /tmp/result.json << EOF
{
  "some_field": true,
  $GUI_EVIDENCE           # Correct: expands to "gui_evidence": {...}
}
EOF
```

If the function returns only the *value* (e.g., a JSON object without its key), embed it with the key:

```bash
GUI_OBJ=$(get_gui_object)   # returns just {...}

cat > /tmp/result.json << EOF
{
  "gui_evidence": $GUI_OBJ  # Correct: key + value
}
EOF
```

**How to know which pattern to use**: Read the function source and check whether its output starts with `"` (a quoted key name, indicating it includes the key) or with `{` (indicating it returns only the object value).

**Prevention**: When writing any utility function whose output will be embedded in JSON, document in a comment whether the output includes the key name or just the value:

```bash
# Output: the full "gui_evidence": {...} key-value fragment (use as $VAR without key prefix)
collect_gui_evidence() { ... }
```

**When to check**: After writing `export_result.sh`, validate the output JSON with `python3 -m json.tool /tmp/<task>_result.json` before writing the verifier. Any parse error reveals this problem immediately.

---

## Lesson 163: `/workspace/tasks/` Is Agent-Accessible — Do Not Put Discovery Hints in `task.json` Metadata for Very_Hard Tasks

**The Problem**: The `tasks/` directory is mounted inside the QEMU VM at `/workspace/tasks/` (configured in `env.json` mounts). Any agent with terminal access can therefore read the full contents of `/workspace/tasks/<task_name>/task.json` — including the `metadata` field. For most tasks this is harmless: `metadata` contains only verification identifiers (target IDs, names) that the task description already reveals. But for **very_hard** tasks where the agent must *discover* what is wrong or what to compute, putting the answer in `metadata` hands it to any agent that thinks to look:

```json
// BAD: an agent runs "cat /workspace/tasks/my_task/task.json" and learns:
"metadata": {
    "wrong_record_ids": [3, 7, 12],        // reveals which records have errors
    "expected_answer": "Seattle",           // reveals the answer to a query task
    "hidden_target_keyword": "XRAY-0042"   // reveals a discovery search term
}
```

**What this means in practice**: An agent with shell access (via a terminal emulator visible in the VNC) can run `cat /workspace/tasks/my_task/task.json` and immediately learn which records are "wrong", what the expected query result is, or what keyword to search for — bypassing the entire discovery challenge of a very_hard task.

**The Fix — Two complementary approaches**:

**Approach 1 (preferred)**: Keep `metadata` to verification identifiers only. Store discovery-sensitive expected values in `/tmp/<task>_gt.json` using the GT-in-Setup pattern (Lesson 77). These are computed from real data at setup time, so an agent reading them gains no more information than they could obtain by querying the database themselves:

```json
// GOOD: metadata contains only what the task description already states
"metadata": {
    "target_id": 123,
    "target_name": "Helena Vasquez"
    // NOT: "expected_diagnosis", "wrong_record_ids", "computed_answer", etc.
}
```

```bash
# Instead, write discovery-sensitive values to /tmp/ at setup time:
python3 -c "import json; json.dump({'correct_city': '$CITY', 'error_count': $N}, open('/tmp/my_task_gt.json','w'))"
# The verifier reads this via copy_from_env — the agent can also read it,
# but since it was computed from the real database, it's no different from the agent querying directly
```

**Approach 2**: Use the Workspace Specification Document pattern (Lesson 144). Place the specification at `/workspace/tasks/<task_name>/spec.txt` and explicitly tell the agent to read it. When the spec is the declared source of truth, the agent reading it is the expected behavior — not a shortcut to guard against.

**What is safe in metadata for all difficulty levels**:
- Target IDs and names that the task description already states
- Scoring configuration values used only by the verifier (`pass_threshold: 70`)
- Environment access values used only in setup/export scripts (table names, API endpoints)

**What must NOT appear in metadata for very_hard tasks**:
- Expected values the agent should compute (`expected_answer`, `correct_city`, `right_count`)
- Lists of records that have errors (`wrong_record_ids`, `corrupted_entries`)
- Search terms or discovery keys the agent should identify themselves

**Why `/tmp/` ground truth is acceptable despite being VM-accessible**: Ground truth values in `/tmp/<task>_gt.json` are computed by `setup_task.sh` from the same live database the agent has access to. An agent reading `/tmp/my_task_gt.json` learns nothing they couldn't compute themselves — whereas `metadata` in `task.json` may contain values you chose during task design that would not be trivially derivable from the application data.

**Rule**: Before finalizing `task.json` metadata for a very_hard task, ask: "If an agent ran `cat /workspace/tasks/<task>/task.json` before taking any other action, would it trivially solve the discovery portion of the task?" If yes, move those values out of `metadata` and into a pre-computed ground truth file at `/tmp/` (Lesson 77), or redesign so the discovery information is embedded in the application's own data rather than in task scaffolding.


---

## Lesson 164: Use Task-Specific Names for All `/tmp/` Files to Prevent Multi-Task Collisions

**The Problem**: If all tasks in an environment use generic `/tmp/` filenames like `/tmp/initial_count`, `/tmp/task_start_timestamp`, and `/tmp/task_result.json`, running or testing multiple tasks in the same VM session causes collisions. Task B's `setup_task.sh` overwrites Task A's baseline files. When Task A's `export_result.sh` runs afterward, it reads Task B's baseline and computes a wrong delta — silently producing an incorrect verifier score.

This is not just a development/debugging hazard. At evaluation time, multiple tasks may run back-to-back in the same VM instance. Generic names cause subtle contamination between tasks that appears as intermittent test failures rather than a systematic bug.

**The Fix**: Always include the full task name in every `/tmp/` file your task creates:

```bash
# BAD: generic names that collide across tasks in the same environment
echo "$COUNT"  > /tmp/initial_count
date +%s       > /tmp/task_start_timestamp
# ... export writes /tmp/task_result.json

# GOOD: task-specific names that are safe to run concurrently
echo "$COUNT"  > /tmp/<task_name>_initial_count
date +%s       > /tmp/<task_name>_start_ts
# ... export writes /tmp/<task_name>_result.json
```

The standard templates in this codebase already follow this convention (e.g., `task.json` points to `verifier.py::verify_<task_name>` and export scripts write to `/tmp/<task_name>_result.json`). This lesson explains **why**: task-specific naming is not cosmetic — it is a correctness requirement for multi-task environments.

**Secondary benefit**: When debugging a single task by running `setup_task.sh` → agent actions → `export_result.sh` in one terminal, and simultaneously running another task's pipeline in a second terminal, each pipeline is fully isolated. You can identify which files belong to which task at a glance.

**Applies to**: All tasks in all environments. Baseline count files (`/tmp/<task>_initial_*`), timestamps (`/tmp/<task>_start_ts`), ground-truth files (`/tmp/<task>_gt.json`), result files (`/tmp/<task>_result.json`), and screenshots (`/tmp/<task>_start_screenshot.png`).

---

## Lesson 165: Calibrate Task Difficulty Against AI Agent Capability Profiles, Not Just Human Intuition

**The Problem**: The human litmus test ("could a competent professional who has never used this software solve this in under 10 minutes by clicking around?") is necessary but not sufficient. It sets a floor on human difficulty but says nothing about whether tasks are achievable by AI agents. AI agents and humans fail on fundamentally different axes.

**Known AI agent failure modes by domain type:**

1. **Specialized visual recognition** (medical imaging, microscopy, geospatial, astronomy): Agents can navigate application menus and toolbars reliably but cannot identify domain-specific structures by visual inspection. A task requiring "measure the aorta at the L3 vertebral level" requires the agent to recognize what L3 looks like — knowledge humans develop through years of training. The agent's typical response is an **infinite search loop**: it knows it must find something specific, scrolls through the entire data volume, and exhausts all steps without ever committing to action. A task that a radiologist solves in 90 seconds becomes impossible for an agent, not because the UI is hard but because the visual recognition is.

2. **Commit-under-uncertainty failure**: When agents cannot confidently determine they have reached the "correct" state (the right slice, the right record, the right view), they continue exploring indefinitely rather than making a "good enough" decision. This is the inverse of the human behavior of estimating: humans commit when they are approximately right; agents often do not commit at all.

3. **Multi-window dialog tracking**: Agents lose state when dialogs open in unexpected positions, close and reopen, or stack. A task requiring navigation through 3 nested dialogs may fail not because any dialog is hard, but because the agent loses orientation after the second one.

**Implications for task difficulty calibration:**

- **The human litmus test calibrates human difficulty.** It does NOT guarantee the task is achievable for an agent. A task rated "easy" by human standards may be agent-impossible if it requires domain-specific visual recognition.
- **For new environments with domain-specific visual content**, create one simple pilot task (UI navigation only, no domain interpretation required) and test it with the agent before designing the full task set. The pilot result reveals which operations the agent can reliably perform in this environment.
- **If the pilot task fails for unexpected reasons** (e.g., agent cannot identify a target structure despite following instructions), all tasks that require that same recognition will also fail. Redesign to eliminate or pre-resolve the recognition requirement before investing in harder tasks.

**The standard fix for domain-recognition failure modes:**
- **Pre-position the environment**: Load the correct slice, zoom to the correct view, highlight the target structure in `setup_task.sh` before the agent starts. Remove the "find it" step for easy and medium tasks.
- **Describe targets by appearance, not domain name**: "Measure the bright circular structure in the center of the image" vs. "Measure the aorta at L3." The agent can identify "bright circular structure" visually; it cannot reliably identify "L3 vertebral level."
- **Use existing segmentations or pre-placed markers**: If the environment supports it, place segmentation masks, color overlays, or fiducial markers on the target before the agent starts. This converts a visual-recognition task into a spatial-click task, which agents handle well.

**Design principle**: For domains with high visual-recognition burden (medicine, biology, geology, materials science), the agent's effective "easy" bar is: *UI operations on pre-identified targets*. The agent's effective "hard" bar is: *multi-step workflows where the target is visually obvious but the operations are non-trivial*. Reserve true "discovery" tasks (where the agent must identify what needs to be done from domain knowledge) for very_hard difficulty, and validate that such tasks are actually achievable before publishing them.

**Applies to**: All environments where the primary application requires domain-specific interpretation of visual content. Less relevant for productivity software (spreadsheets, email, word processors) where task content is self-describing.

---

## Lesson 166: Exclude Pre-Seeded Setup Files When Detecting New Agent-Created Files

**The Problem**: When `setup_task.sh` places sample data files into a directory that the agent is expected to write to (e.g., seeding recordings, exports, or examples into `~/Documents/App/Recordings/`), a naive "new file" check in `export_result.sh` will include those pre-seeded files as candidates. If the do-nothing test runs and no setup timestamp is recorded (or timing is tight), pre-seeded files appear as valid new files, causing the do-nothing test to return a non-zero score.

**Concrete example**: Setup copies `Sample-Recording.txt` into `~/App/Recordings/` before the task starts. The task asks the agent to START and STOP a new recording. The export script finds all files in Recordings/ newer than `task_start` — but because setup_task.sh copied files at `task_start` second, those setup files can appear as "new" (see Lesson 15 on sub-second mtime). The do-nothing verifier score becomes non-zero.

**The Fix — Two complementary approaches**:

**Approach 1 (Preferred): Explicit filename exclusion list**

Record the exact filenames present at the end of setup in `/tmp/<task>_setup_files.txt`, then filter them out at export time:

```bash
# In setup_task.sh (after copying all sample data):
ls /home/ga/Documents/App/Recordings/ 2>/dev/null > /tmp/<task_name>_setup_files.txt
```

```bash
# In export_result.sh:
TASK_START=$(cat /tmp/<task_name>_start_ts 2>/dev/null || echo "0")
SETUP_FILES=$(cat /tmp/<task_name>_setup_files.txt 2>/dev/null || echo "")

NEW_RECORDING=""
NEW_RECORDING_SIZE=0

for f in /home/ga/Documents/App/Recordings/*; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f")
    # Skip files that existed at setup time
    if echo "$SETUP_FILES" | grep -qF "$BASENAME"; then
        continue
    fi
    MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        NEW_RECORDING="$BASENAME"
        NEW_RECORDING_SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
        break
    fi
done
```

**Approach 2: Naming-pattern exclusion**

If setup-seeded files have a known naming pattern (e.g., always start with `Sample-` or `Template-`), exclude by pattern without needing a setup manifest:

```bash
for f in /home/ga/Documents/App/Recordings/*; do
    BASENAME=$(basename "$f")
    # Skip files that match the known setup-seeded naming pattern
    case "$BASENAME" in
        Sample-*|Template-*|Example-*)
            continue ;;
    esac
    # ... rest of new-file check
done
```

**Why the timestamp check alone is insufficient**: Because `setup_task.sh` runs seconds before `date +%s > /tmp/<task>_start_ts`, the seeded files and the timestamp are created within the same wall-clock second. Combined with sub-second mtime (Lesson 15), a seeded file created at T.97s appears newer than the integer task_start T, giving a false positive.

**Rule**: Whenever `setup_task.sh` places files into a directory the agent will also write to, add an explicit exclusion step in `export_result.sh`. The safest approach is Approach 1 (enumerate setup files at the end of setup); the most concise is Approach 2 (pattern exclusion) when the naming convention is reliable.

**Applies to**: Any task where the setup script seeds sample data into an application output directory — recording directories, export folders, screenshot directories, download folders, project directories. Does not apply when setup data and agent output go to different directories.

---

## Lesson 167: Diagnose Task Quality Problems from Agent Trajectory Analysis

**The Problem**: The task creation validation process (do-nothing=0, wrong-target=0, partial=partial) verifies that the verifier is correct, but cannot predict whether real agents will achieve meaningful success rates. After deployment and trajectory collection, you often discover that tasks fail systematically — not because the agents are incompetent, but because the task design has a structural problem invisible during creation. Without a diagnostic framework, task creators mistake "agent skill gap" for "task design flaw" and vice versa, leading to either accepting broken tasks or incorrectly dumbing down genuinely hard tasks.

**Five diagnostic patterns and their targeted fixes:**

**Pattern 1: Aimless wandering — 0% success, trajectories show random UI navigation**
- **Symptom**: Agent opens and closes menus repeatedly, types in random fields, navigates to unrelated screens.
- **Diagnosis**: The task description is too vague. The agent cannot identify the goal.
- **Fix**: Make the success criterion more explicit. Add the exact target name, expected end state, or any missing login credentials.

**Pattern 2: Infinite search loop — 0% success, trajectories show repeated scrolling/cycling without action**
- **Symptom**: Agent correctly identifies what to do but spends all steps scanning (scrolling image slices, cycling through records, scanning dropdown options) without committing to any action.
- **Diagnosis**: The task requires visual recognition or data discovery that exceeds the agent's domain knowledge. The agent knows it must find "the right place" but cannot identify when it has found it. This is the most common failure mode for tasks involving domain-specific visual content (medical imaging, microscopy, geospatial data, scientific spectra).
- **Fix (for easy/medium tasks)**: Pre-position the application state in `setup_task.sh` so the target is already visible when the agent starts — navigate to the correct slice, open the relevant record, apply the right filter. Remove the "find it" step entirely.
- **Fix (for hard/very_hard tasks)**: If the search loop is expected difficulty, accept it. If the loop is caused by ambiguous visual content the agent *should* be able to resolve, consider describing the target by appearance rather than domain name ("measure the bright circular structure in the center of the image" vs. "measure the aorta at L3").

**Pattern 3: Correct approach, wrong values — partial success only, agent reaches the right feature but fails**
- **Symptom**: Agent navigates to the right dialog/module and attempts the correct action, but enters wrong values or selects wrong parameters. Score is partial.
- **Diagnosis**: The agent lacks domain knowledge to determine the correct value. The description does not provide expected values.
- **Fix (for hard tasks)**: Add the expected values to the description. This moves the task from hard to medium difficulty, which may be acceptable if the workflow navigation is the skill being tested.
- **Fix (for very_hard tasks)**: Accept this — the agent is supposed to determine correct values from context. If it cannot, that is appropriate failure at very_hard difficulty.

**Pattern 4: Hits the step limit — 0% success, every trajectory reaches max_steps mid-task**
- **Symptom**: Agents are clearly on the right track but run out of steps. The task is partially complete at every run.
- **Diagnosis**: The step budget is too tight. Navigation overhead (login, waiting for UI, opening menus, dismissing dialogs) is consuming most of the budget before core task execution begins.
- **Fix**: Before adjusting the task, decompose it into phases and estimate minimum step requirements:
  - Navigation phase (login, navigate to feature): ~N steps
  - Core execution phase (the actual task): ~M steps
  - Save/export phase (save, confirm, close): ~K steps
  - Set `max_steps` to at least `1.5 × (N + M + K)`
- If N is large relative to M (navigation dominates), consider pre-navigating to the starting screen in `setup_task.sh` for easy/medium tasks. For hard tasks, N is part of the challenge and max_steps should be increased instead.

**Pattern 5: Unexpectedly high success — >80% success on a task intended to be hard**
- **Symptom**: Agents pass a task labeled hard/very_hard with high frequency, or via obviously unintended paths.
- **Diagnosis**: Agents found a shortcut — the verifier awards points for pre-existing state, or a simpler path bypasses the intended challenge.
- **Fix**: Re-run the do-nothing and wrong-target tests. Check if any scoring criterion is satisfied by state that existed before the agent acted. Add baseline recording or a wrong-target gate if missing. Inspect what specific actions the agents took that triggered the pass condition.

**Minimum useful sample for analysis**: 3–5 trajectories per task reveal systematic patterns reliably. A single trajectory can be misleading (one agent may have been unusually lucky or unlucky). For pattern identification, look for failure modes that appear in at least 3 of 5 runs.

**What to look for when inspecting trajectories**:
- Count steps spent in each phase (navigation vs. execution vs. saving)
- Identify the last action before step exhaustion
- Look for repeated identical actions (a sign of looping/getting stuck)
- Note which UI elements the agent clicked — does it reach the right panel/dialog?
- Check whether the agent's final state is "almost complete" (partial score available) or "completely off track" (score=0)

**Applies to**: All task sets after initial deployment, or after any significant change to the environment or agent model. Run this diagnostic whenever a task achieves <5% or >80% success rate across 5+ agent runs. Do NOT adjust tasks based on a single run — individual runs have high variance.

---

## Lesson 168: Verifiability Inventory — Assess Each Feature's Verification Story Before Committing to a Task

**Category**: Task design / New environment onboarding
**Applies to**: All environments, especially when creating the first tasks for a new application

### The Problem

A common late-stage failure in task creation is discovering that the feature the task is built around cannot be programmatically verified. This realization typically arrives during the verifier-writing phase — after the task description, setup script, and export script have already been written. At that point, the options are to either redesign the task (wasteful) or accept a weak proxy verification that is gameable (dangerous).

The root cause: task designers naturally start from "what should the agent do?" and defer "how will I verify it?" until implementation time. But verifiability is not a given. It must be confirmed before committing to a task.

### The Fix: Verifiability Inventory as a Pre-Design Step

Before brainstorming specific tasks, build a **verifiability inventory** for the application. This takes 30–60 minutes and prevents hours of wasted implementation work.

**Step 1**: List every major feature/workflow in the application (open menus, read tooltips, consult documentation).

**Step 2**: For each feature, answer: *"If an agent successfully uses this feature, what observable change occurs outside the application's in-memory state?"*

**Step 3**: Categorize each feature by its verification tier:

| Tier | Verification mechanism | Examples |
|------|----------------------|----------|
| **Tier 1** | Direct DB or file query | Record inserted in DB, output file written to disk, config file updated |
| **Tier 2** | Proxy signal | Screenshot count increases, clipboard content changes, app process restarts |
| **Tier 3** | Domain-vocabulary report | Agent must write a report proving it explored the feature (Lesson 27) |
| **Tier 4** | No verification possible | View-mode-only, in-memory toggles with no persistent effect, animations |

**Step 4**: Map difficulty levels to verification tiers:
- **Easy/Medium tasks**: Require Tier 1 verification. The outcome must be directly readable.
- **Hard tasks**: Tier 1 or Tier 2 acceptable. Proxy signals must be clearly unambiguous.
- **Very Hard tasks**: Tier 1 preferred; Tier 3 acceptable if vocabulary is app-specific and un-gameable (see Lesson 30).
- **Avoid Tier 4** as a primary verification path at any difficulty level.

### Concrete Example

For a reference management tool (e.g., Zotero, Jurism):

| Feature | Observable artifact | Tier |
|---------|-------------------|------|
| Add item to library | Row inserted in `items` table | Tier 1 |
| Edit item metadata | Updated columns in `items` + `itemData` | Tier 1 |
| Add tag | Row in `tags` + `itemTags` junction | Tier 1 |
| Export bibliography | `.bib` file written to disk | Tier 1 |
| Change display sort order | In-memory UI state only, no config write | Tier 4 |
| Mark item as read | Depends: some apps write to DB, some do not | Tier 1 or 4 — check schema |

A task built around "change display sort order" would require Tier 4 verification — unavoidable redesign late in the process. Building the inventory first reveals this before any code is written.

### Why This Matters for New Environments

In established environments (OpenEMR, Moodle, Oracle), the verification story is already known from prior tasks. In a **brand new environment** where no tasks exist, the verification story is completely unknown. Without the inventory, a task creator will naturally gravitate toward "interesting" features and only later discover that the feature writes nothing to disk or DB. This lesson exists to make verifiability the first design constraint, not the last.

**Rule**: If you cannot answer "how will I verify this?" for a task in one sentence before writing the first line of code, the task is not ready to design. Do the inventory first.

**Also applies to the feature-matrix check** (Principle 2, Data Diversity, `01_core_principles.md`): building the verifiability inventory and the feature matrix simultaneously is efficient — you capture both "which features exist" and "which are verifiable" in a single exploration pass.

---

## Lesson 169: Clean Stale Output Artifacts Before Recording Task Start Timestamp — Universal Ordering Rule

**Category**: Task script correctness / Timestamp-based verification
**Applies to**: All environments (Linux, Windows, Android) wherever timestamp checks are used

### The Problem

Many tasks verify that the agent created or modified a specific output file by checking that its modification time (`mtime`) is strictly greater than the task start timestamp. This check fails silently when a **stale output file from a previous run** exists at the expected output path when `setup_task.sh` runs.

The failure mode:
1. Task run #1: agent creates `/home/ga/Desktop/output.csv` at time T1.
2. Next test run: `setup_task.sh` records `task_start = T2`. But `output.csv` still exists from run #1, with `mtime = T1 < T2`.
3. In the do-nothing test for run #2: `export_result.sh` checks `mtime(output.csv) > T2`. This correctly returns `False` — the stale file is ignored. ✓
4. BUT: if `setup_task.sh` runs at T2 and records `task_start = T2`, and THEN a bug or timing issue causes the file to be re-touched at T2+ε (e.g., a GUI app refreshes the file on startup), the file now has `mtime ≈ T2`, and `int(mtime) > T2` is `False` — the agent's actual new file is rejected. ✗

The root cause is that cleanup and timestamp recording are in the wrong order. The correct order ensures a clean baseline before the clock starts.

### The Universal Ordering Rule

In `setup_task.sh`, always follow this strict sequence:

```
1. CLEAN  — delete all stale output artifacts at the expected output paths
2. RECORD — write the task start timestamp to /tmp/<task>_start_ts
3. SEED   — insert database records, copy starter files, configure app state
4. LAUNCH — start the application (if needed)
```

**Why this order?**
- Cleaning BEFORE recording ensures that when the timestamp is recorded, the output path is empty. Any file that appears after the timestamp was created by the agent or by seeding — and seeded files can be excluded by name (Lesson 166).
- Recording BEFORE seeding means seeded files always have `mtime ≥ task_start`, making them easy to identify and exclude.
- If you record the timestamp FIRST and then delete stale files, a stale file with `mtime > task_start` could persist if the delete fails silently — giving the do-nothing test a false positive.

### Implementation (Linux bash)

```bash
#!/bin/bash
echo "=== Setting up <Task Name> ==="
source /workspace/scripts/task_utils.sh

# Step 1: CLEAN — delete stale output artifacts FIRST
# List every path the agent might produce output at
rm -f /home/ga/Desktop/output.csv
rm -f /home/ga/Documents/report.html
rm -f /home/ga/Downloads/export.zip
find /home/ga/App/OutputDir -name "*.png" -delete 2>/dev/null || true

# Step 2: RECORD — timestamp is clean; no stale artifacts exist
date +%s > /tmp/<task_name>_start_ts

# Step 3: SEED — insert data into DB, copy starter files, etc.
# (seeded files will have mtime >= task_start — use Lesson 166's exclusion pattern)
python3 << 'PYEOF'
# ... database seeding ...
PYEOF

# Step 4: LAUNCH — restart the app with seeded data visible
su - ga -c "DISPLAY=:1 /opt/app/app &"
sleep 3

echo "=== Setup Complete ==="
```

### Relationship to Other Lessons

- **Lesson 15** (sub-second mtime): Shows why `int(mtime) > task_start` (not `mtime > task_start`) must be used. The ordering rule in this lesson makes the comparison safe.
- **Lesson 166** (exclude seeded files): Shows how to filter out files created by Step 3 (SEED). The timestamp recorded in Step 2 is the anchor for that exclusion.
- **`08_windows_environment_patterns.md` Section 2**: States this rule explicitly for PowerShell. This lesson generalizes it to all environments.

**Rule**: The line `date +%s > /tmp/<task_name>_start_ts` must always appear AFTER all `rm -f` / cleanup lines and BEFORE all `INSERT`/`cp`/`seed` lines in `setup_task.sh`. Any other ordering introduces a window for timestamp-based false positives or false negatives.

**Applies to**: All `setup_task.sh` (Linux) and `setup_task.ps1` (Windows) files in any environment that uses timestamp-based new-file detection. Verified by: run the do-nothing test twice in the same VM without rebooting, and confirm the second run still returns score=0.

---

## Lesson 170: Visually inspect the environment after running your setup script

### Problem

File and database checks confirm that data was written correctly — but they do not tell you whether the *application* is displaying the expected view. After `setup_task.sh` runs, the following silent failures are possible and only detectable by visual inspection:

- The app opened to the wrong tab, module, or screen (the agent starts blind in the wrong place)
- The seeded data is in the database but the app requires a refresh or restart to display it
- A dialog or error message is blocking the main window
- The app loaded the correct record but collapsed a section the agent needs to see
- The wrong file is open (e.g., app reopened the last session's file instead of the seeded one)

These failures don't cause `export_result.sh` to fail and don't show up in `/tmp/` checks. The agent simply starts in an unexpected state and fails for opaque reasons.

### Fix

After your setup script finishes, take a screenshot and visually inspect the environment state before declaring setup complete. In Linux desktop environments:

```bash
# At the end of setup_task.sh, take a screenshot for visual inspection
DISPLAY=:1 import -window root /tmp/<task_name>_setup_check.png
echo "=== Setup Complete — check /tmp/<task_name>_setup_check.png ==="
```

Then inspect the screenshot. Ask yourself:
1. Is the correct application open and in the foreground?
2. Is the application showing the screen/module the agent needs to start from?
3. Is the seeded data actually visible (not just present in the DB)?
4. Are there any blocking dialogs, error messages, or loading spinners?
5. Is the starting state unambiguous — would an agent know immediately what it is looking at?

If any answer is "no" or "uncertain", fix the setup script before proceeding to implement the verifier. A visually wrong starting state invalidates all subsequent testing.

### When pre-positioning is the goal

For tasks where pre-positioning the agent (Lesson 11 in `11_agent_behavior_patterns.md`) is a deliberate design choice, visual inspection is the *only* way to confirm the pre-positioning worked. A database entry is not sufficient — the data must be visually present in the application's UI at task start.

**Applies to**: All GUI-based environments (Linux desktop, Windows, Android). Not applicable to purely CLI/headless environments where there is no visual UI state to inspect.

---

## Lesson 171: Apply the "fresh-eyes" test to task descriptions

### Problem

Task creators have deep familiarity with the software they are tasking. This causes a systematic blind spot: task descriptions that are clear to the creator contain hidden assumptions that a capable agent — which has never used that specific software before — cannot resolve.

Examples of hidden assumptions that slip into descriptions:
- "Update the appointment status" — but the agent doesn't know where appointment status is changed, or what the valid status values are
- "Fix the billing code error" — the agent doesn't know which billing code has an error, or how errors are surfaced in the UI
- "Export the patient summary" — the agent doesn't know which patient, or which export format, or where the export function is located

For **easy/medium** tasks, these assumptions must be resolved by the description itself.
For **hard/very_hard** tasks, these assumptions must be resolvable by an agent through normal exploration — not by luck or prior knowledge of the software.

### Fix

After writing the task description, apply the "fresh-eyes" test: read the description as if you have never used the software and have no knowledge of its UI layout. For each noun and verb in the description, ask:

- **Noun test**: Can an agent that has never opened this application find this entity? (Is it searchable? Is it on a known screen?)
- **Verb test**: Can an agent that has never used this feature discover how to perform this action through normal exploration? (Is it in a menu? Is it a button? Is the path to it findable?)
- **Value test**: If a specific value or format is required, does the description provide it — or can the agent derive it unambiguously from the application's own data?

If any test fails:
- For easy/medium: add the missing information to the description.
- For hard/very_hard: verify the software's own UI makes the path discoverable (tooltips, labels, search, error messages). If it does not, either lower the difficulty level or redesign the task.

### Anti-pattern to avoid

> "Set the notification preference to silent for high-priority alerts."

A fresh-eyes reader cannot answer: *Where is the notification preference setting? Is "silent" a valid value in this software? What constitutes a "high-priority alert" in this software's terminology?*

### Corrected forms

Easy: *"In the application's Settings → Notifications panel, set the notification mode for alerts with priority level 'High' to 'Silent'."*

Hard: *"Configure the application so that high-priority alerts no longer produce sound notifications."* (The agent must discover where notification settings are and what values are available.)

**Applies to**: All task descriptions at all difficulty levels in all environments. Perform this test after writing the first draft of the `task.json` description and the README.

---

## Lesson 172: Verify that cleanup commands actually succeeded before recording the baseline

### Problem

Lesson 169 establishes the CLEAN → RECORD → SEED → LAUNCH ordering. However, the CLEAN phase is often implemented with `rm -f`, `find -delete`, or database `DELETE` statements that can fail silently:

- `rm -f` exits 0 even if the file didn't exist (fine) but also exits 0 if the file is locked by a running process (problem)
- `DELETE FROM table WHERE ...` succeeds even if zero rows were deleted — and if the wrong `WHERE` clause is used, stale data persists
- Shell glob expansions like `rm -f /home/ga/outputs/*.csv` silently do nothing if the glob matches zero files AND the shell was invoked without `nullglob`

If the CLEAN phase appears to succeed but doesn't, the baseline recorded in the RECORD phase is dirty: it may include stale artifact files or stale database rows. The do-nothing test will then produce a false positive (score > 0 with no agent action).

### Fix

After each cleanup command, add an explicit verification that the cleanup actually worked:

```bash
# Linux bash example

# Step 1: CLEAN — and verify each cleanup

# Kill app first so file locks are released (see Lesson 28, Lesson 35)
pkill -f "my_app" 2>/dev/null; sleep 1

# Remove output artifacts
rm -f /home/ga/Desktop/output.csv
[ -f /home/ga/Desktop/output.csv ] && echo "ERROR: cleanup failed for output.csv" && exit 1

# Clean database entries from prior runs (use a unique tag/marker)
sqlite3 /home/ga/.config/myapp/app.db \
  "DELETE FROM exports WHERE source = 'task_<task_name>';"
COUNT=$(sqlite3 /home/ga/.config/myapp/app.db \
  "SELECT COUNT(*) FROM exports WHERE source = 'task_<task_name>';")
[ "$COUNT" -ne 0 ] && echo "ERROR: DB cleanup failed, $COUNT rows remain" && exit 1

# Step 2: RECORD — now the baseline is clean
date +%s > /tmp/<task_name>_start_ts
```

For Windows PowerShell:

```powershell
# Remove and verify
Remove-Item -Path "C:\Users\Docker\output.csv" -Force -ErrorAction SilentlyContinue
if (Test-Path "C:\Users\Docker\output.csv") {
    Write-Error "ERROR: cleanup failed for output.csv"; exit 1
}
```

### When verification is impractical

For cleanup steps that remove entire directories (e.g., `rm -rf /tmp/<task>_workdir/`), an existence check on the directory itself is sufficient. For database cleanup, a `COUNT(*)` query after the `DELETE` is the most reliable check.

If a cleanup step genuinely cannot be verified (e.g., clearing an app's in-memory cache), document this in a comment so future maintainers know the risk.

**Applies to**: All `setup_task.sh` (Linux) and `setup_task.ps1` (Windows) files. Most critical for tasks that will be run repeatedly on the same VM image (e.g., during development and testing), where stale artifacts from prior runs are most likely.

---

### 222. Discover the On-Disk Format of Config Values Before Writing Verification Logic

**The Problem**: Many GUI applications store user-set values in a format that is completely different from what appears in the UI. The most common mismatches are:

- **Coordinates**: UI shows degrees (e.g., 40.44°N) → config stores radians (`0.705822`)
- **Dates/Times**: UI shows a calendar date → config stores Julian Day Number (`2460141.5`)
- **Colors**: UI shows a color picker → config stores packed RGBA integer or hex string
- **Enumerations**: UI shows a dropdown label ("Natural") → config stores an integer (`13`)
- **Sizes/Distances**: UI shows meters or kilometers → config stores internal units

If you write verification logic based on the UI-visible value without checking the actual stored format first, your verifier will always score 0 (the radian value is never "equal to" the degree value) or always score 100 (a wrong format comparison is never triggered).

**The Fix**: Before writing any verification or setup logic for a config-backed setting:

1. **Boot the VM and set the value through the UI.**
2. **Close the application** (to flush in-memory state — see Lesson 28).
3. **Read the raw config file** and note the exact key name, section, and stored value format.

```bash
# Example: discover how an app stores latitude
cat /home/ga/.config/myapp/config.ini | grep -i "lat\|lon\|location"
# Output: latitude=0.705822  ← radians, not degrees!

# Example: discover how a calendar app stores dates
cat /home/ga/.config/myapp/prefs.json | python3 -m json.tool | grep -i "date\|time\|start"
# Output: "event_start": 2460141.5  ← Julian Day Number!
```

4. **Write your conversion code** in both `setup_task.sh` (to write the target value in the correct format) and `verifier.py` (to compare in the correct format).

```python
# In verifier.py — compare in the app's native format (radians), not the user-visible format (degrees)
import math
TARGET_LAT_RAD = math.radians(40.44)        # Pittsburgh: 0.70582...
stored_lat_rad = result.get("lat_rad", None)

if stored_lat_rad is not None:
    if abs(stored_lat_rad - TARGET_LAT_RAD) < 0.08:   # ±4.6° tolerance in radians
        score += 25
```

**How to find the config file path**: Check:
- `~/.config/<AppName>/` (XDG standard)
- `~/.local/share/<AppName>/`
- `~/<AppName>/` (older apps)
- Application documentation or source code for the config file name

**Applies to**: Any desktop application that stores GUI-settable values in a text config file (INI, TOML, JSON, XML, `.conf`). Planetarium software (Julian Days), GIS/mapping apps (radians), scientific tools (unit conversions), and legacy desktop apps (packed integers for colors/enums) are the most common sources of format surprises.

---

### 223. Write the Full Config From Scratch in setup_task.sh, Don't Patch an Unknown State

**The Problem**: A common (but fragile) `setup_task.sh` pattern is to query the current config, read specific fields, and only patch the fields that need to change:

```bash
# FRAGILE: read current state and patch
sed -i 's/atmosphere=true/atmosphere=false/' /home/ga/.config/myapp/config.ini
```

This fails in several ways:
- If the field wasn't in the config at all, the `sed` is a no-op
- If a previous test run or agent session left the config in an unexpected intermediate state, the patch may not converge to the desired state
- If the config file format changed between app versions, the sed pattern breaks silently

**The Fix**: Write the **entire relevant config section** from scratch using a structured parser. This guarantees a completely known starting state regardless of any prior history.

```bash
# ROBUST: rewrite the complete config with known values
python3 << 'PYEOF'
import configparser, os

config = configparser.RawConfigParser()
config_path = "/home/ga/.config/myapp/config.ini"

# Read existing config to preserve unrelated sections
if os.path.exists(config_path):
    config.read(config_path)

# Overwrite every field we care about in the relevant section
if not config.has_section("viewing"):
    config.add_section("viewing")
config.set("viewing", "flag_atmosphere", "true")
config.set("viewing", "flag_ground", "true")
config.set("viewing", "flag_equatorial_grid", "false")
config.set("viewing", "flag_azimuthal_grid", "false")

if not config.has_section("location_run_once"):
    config.add_section("location_run_once")
config.set("location_run_once", "latitude", "0.705822")   # radians!
config.set("location_run_once", "longitude", "-1.396192")

with open(config_path, "w") as f:
    config.write(f)

print("Config written with known starting state")
PYEOF
```

After writing the config, kill and restart the application so it loads the fresh config:

```bash
pkill -f myapp 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 /opt/myapp/myapp >> /home/ga/myapp.log 2>&1 &"
```

**Key advantages**:
- **Reproducible**: same starting state on every run, even after agent sessions that partially modified config
- **Transparent**: the config is human-readable; anyone can inspect what the starting state is
- **Self-documenting**: the Python block serves as ground truth for what the task's initial conditions are

**When to preserve vs. overwrite**: Use `config.read()` first (to preserve unrelated sections like window geometry or user preferences) and only `config.set()` the fields relevant to the task. Never wipe the entire config — other sections may be required for the app to start correctly.

**Applies to**: Any `setup_task.sh` for a desktop application that stores its settings in a file-backed config (INI, TOML, JSON, XML, SQLite preferences table). Most common for standalone GUI applications: astronomy software, scientific tools, creative suites, and any app without a separate database.

---

### 224. Deliberately Wrong Starting State as a Difficulty Lever for Hard Tasks

**The Problem (from a task design perspective)**: Hard and very_hard tasks need to require active agent decision-making, not just mechanical execution. If the application always starts in a neutral or correct state, the agent only needs to perform the requested configuration — it never needs to recognize and correct errors. This makes the task easier than intended.

**The Technique**: Deliberately set one or more display settings, flags, or configuration values to the *opposite* of what the task requires. The agent must:
1. Recognize the current state is wrong (requires visual inspection or UI reading)
2. Determine what the correct state should be (requires domain knowledge)
3. Fix the wrong settings AND complete the primary task

This is fundamentally different from "pre-positioning" (Lesson 1 in `11_agent_behavior_patterns.md`), which makes tasks easier by putting the correct starting point in view. The deliberately-wrong starting state makes tasks harder by adding a recognition-and-correction subtask that is not explicitly described in the task prompt.

**Example**:

```bash
# In setup_task.sh for a celestial navigation task:
# Task goal: configure Stellarium for a maritime navigation exercise
# INTENTIONALLY set the WRONG starting state — agent must recognize and fix all of these

python3 << 'PYEOF'
import configparser
config = configparser.RawConfigParser()
config.read("/home/ga/.stellarium/config.ini")

# Wrong: constellation lines ON (clutters the sky for nav — agent must turn OFF)
config.set("viewing", "flag_constellation_drawing", "true")
# Wrong: constellation art ON (agent must turn OFF)
config.set("viewing", "flag_constellation_art", "true")
# Wrong: star labels OFF (agent needs them ON for nav star identification)
config.set("stars", "flag_star_name", "false")
# Wrong: azimuthal grid OFF (agent needs it ON for bearing reference)
config.set("viewing", "flag_azimuthal_grid", "false")

with open("/home/ga/.stellarium/config.ini", "w") as f:
    config.write(f)
PYEOF
```

**Design constraints for this technique**:

1. **Verify the wrong state in export_result.sh / verifier.py**: each wrong-→-correct fix is an independent scoreable criterion. An agent that fixes 3 of 4 wrong settings earns partial credit.

2. **Use when the correct state is knowable from the task description**: the task prompt must provide enough context for a skilled agent to determine what the correct configuration should be. The agent shouldn't need to guess — the domain scenario (e.g., "configure for maritime celestial navigation") implies which settings are appropriate.

3. **Limit to 3–5 wrong settings per task**: more than 5 creates a task about "find the toggles" rather than the intended domain challenge.

4. **Document the wrong settings in `task.json` metadata**: this helps verifier authors and test writers know what to expect in the do-nothing baseline.

```json
"metadata": {
    "intentional_wrong_settings": {
        "flag_constellation_drawing": "true (should be false)",
        "flag_star_name": "false (should be true)"
    }
}
```

**When NOT to use**: Do not apply this technique to the core correctness criterion (e.g., the location coordinates or the target date). Wrong starting state should apply to auxiliary display/configuration settings, not to values the agent is expected to set for the first time.

**Applies to**: Any desktop application with multiple independently-toggleable settings where the correct combination for a given professional use case is non-trivial (astronomy tools, GIS, CAD, scientific analysis software). Particularly effective for hard tasks where the domain persona (navigator, astronomer, archaeologist) would be expected to know the correct professional configuration.

---

### 225. Use Visual Grounding to Validate UI State During Task Creation

**The Problem**: When creating tasks for GUI applications, task creators must confirm the application's starting state, identify exact UI element locations for setup scripts, and verify that task descriptions accurately describe what an agent will actually see. This is usually done by taking screenshots and scanning them visually. Visual inspection is slow, inconsistent, and easy to fool — a partially-loaded application, a dialog hidden behind another window, or the wrong data loaded can all look "fine" at a glance while silently causing every agent trajectory to fail for an unintended reason.

**The Pattern**: During task creation, use a visual grounding tool (such as the `visual_grounding` MCP tool) to systematically query screenshots rather than relying on visual inspection alone.

**Four high-value uses during task creation:**

**1. Verify the start screenshot shows the intended state**

After running `setup_task.sh`, take a screenshot and query it to confirm the expected elements are present before finalizing the task:

```python
# Example queries to run against the start screenshot
result = visual_grounding(
    question="Is the application's main window visible and fully loaded? "
             "What is currently displayed in the center panel?",
    screenshot_path="/tmp/task_start_screenshot.png"
)
# If the answer is "a loading spinner" or "an error dialog", setup failed.
```

Common setup failures that are easy to miss visually but caught by targeted grounding queries:
- Application stuck on splash/welcome screen instead of the working view
- Data loaded but wrong dataset (wrong patient, wrong file)
- A dialog box partially hidden behind the main window
- The expected module/panel not active

**2. Identify UI element coordinates without trial-and-error**

For `setup_task.sh` scripts that need to interact with the UI (e.g., dismiss first-run dialogs, navigate to a specific module), use visual grounding to find exact element locations rather than hardcoding coordinates from memory or running the script repeatedly until it works:

```python
result = visual_grounding(
    question="Where is the 'Close' or 'X' button for the welcome dialog? "
             "Give me its approximate screen coordinates.",
    screenshot_path="/tmp/app_first_launch.png"
)
# Use the returned coordinates in your setup script's tap/click commands
```

This is especially valuable for Android environments (where `uiautomator dump` XML coordinates must be computed from bounds) and Windows environments (where PyAutoGUI coordinates are required for GUI automation).

**3. Validate that hard/very_hard task descriptions are achievable from the start state**

Before finalizing a task description that says "find the anomalous records and fix them," confirm that the anomalous records are actually discoverable from the start state — not buried behind 15 clicks:

```python
result = visual_grounding(
    question="Is there any visible indication on this screen that records have errors "
             "or need attention? What does the agent see first?",
    screenshot_path="/tmp/task_start_screenshot.png"
)
# If the answer is "no — the screen just shows a blank list", the task may require
# more steps than expected before any meaningful work can begin.
```

**4. Confirm evidence screenshots actually show what you think they show**

When collecting evidence for `evidence_docs/`, use visual grounding to confirm the screenshot documents the correct state rather than a stale or incorrect capture:

```python
result = visual_grounding(
    question="Does this screenshot show [expected application state]? "
             "Is the correct data/module/record visible?",
    screenshot_path=f"benchmarks/cua_world/environments/{env_name}/evidence_docs/{task_name}_screenshot.png"
)
```

**Important caveats**:
- Visual grounding queries the screenshot at a fixed resolution (1280×720 normalized). When using coordinates for actual click/tap actions, scale them to the actual VM display resolution.
- Use grounding to *confirm* what you already believe to be true. If the grounding result is surprising, investigate further — don't simply accept either the grounding result or your prior assumption without checking.
- This is a task creation aid, not a task verification mechanism. The verifier should use programmatic checks (database queries, file content), not visual grounding, as the primary scoring criterion.

**Applies to**: All GUI environments (Linux desktop, Windows, Android). Particularly valuable for complex or unfamiliar applications (medical imaging software, scientific tools, professional software) where the expected start state involves multiple interacting UI elements and silent setup failures are easy to miss.

---

### 226. Pre-Navigate to the Correct Application Mode for Mode-Specific Tasks

**The Problem**: Many professional applications have multiple editing interfaces, workspaces, or modes — and the task may be specific to only one of them. Examples:

| Application | Modes/Interfaces |
|---|---|
| PsychoPy | Builder (GUI experiment designer) vs. Coder (Python script editor) |
| MATLAB | Live Editor (notebook) vs. Script Editor (plain .m files) vs. Command Window |
| RStudio | Source editor vs. Console vs. R Notebook |
| Blender | Object Mode vs. Edit Mode vs. Scripting workspace |
| GIMP | Single-window mode vs. multi-window mode |
| Jupyter | Code cells vs. Markdown cells |

If `setup_task.sh` leaves the application in the wrong mode, the agent's first several steps will be consumed navigating from the default mode to the correct one — steps that are not part of the task's intended challenge. Worse, if the mode switch is non-obvious, agents may attempt the task in the wrong interface and fail completely (e.g., trying to use Builder drag-and-drop for a Coder-only task).

**The Fix**: In `setup_task.sh`, programmatically switch the application to the correct mode before the task starts. The method depends on the application:

```bash
# Option A: App stores the current interface mode in a config file
# Detect the relevant key and set it to the correct value before launch

# Option B: App accepts a CLI flag specifying the mode or an entry point
# e.g., `psychopy --coder myfile.py` or `rstudio --no-restore-workspace`

# Option C: The mode is determined by which file the app opens at startup
# Open a file of the type associated with the target mode (a .py file opens Coder,
# a .psyexp file opens Builder, a .R file opens RStudio's Source editor)

# Option D: Use xdotool/wmctrl to click the mode switch button after launch
# (last resort — fragile, but acceptable for applications with no other API)
```

**Task description guidance**: For very_hard mode-specific tasks, the description should state which interface the agent must use (e.g., "Using PsychoPy Coder (not Builder)...") but should NOT specify how to switch modes — that's a UI navigation step the agent should discover. The `setup_task.sh` should pre-position to the correct mode so the navigation step isn't a silent time sink.

**How this differs from pre-positioning (Lesson 1 in `11_agent_behavior_patterns.md`)**: Pre-positioning is about putting the correct *data* in view (right record open, right file loaded). Mode pre-navigation is about activating the correct *interface context*. Both reduce incidental overhead that would otherwise consume step budget without testing the intended capability.

**How to discover what mode is needed**: Read the task description. If it says "write a Python script," the task requires Coder or Script view. If it says "build in the visual interface," it requires the GUI builder. If it says "use the console/REPL," it requires the interactive session. Any mention of file extension (`.py` vs `.psyexp`, `.R` vs `.Rmd`) implies the correct mode.

**Applies to**: Any task for an application that has ≥2 meaningfully different editing interfaces or modes, where the task is specific to one of them.

---

### 135. Legitimate Dual-Use of a Target Pattern Causes Export Script False Positives

**The Problem**: In bug-fix and refactoring tasks, the unfixed source code may legitimately use the same identifier, function, or keyword that your export script greps for — but for a completely different purpose. This is distinct from Lesson 19 (comment contamination): the unfixed code's *executable logic* already contains the pattern you're using to detect the fix.

**Classic example**: A task requires fixing a Sharpe ratio bug where the code divides by variance instead of standard deviation. The export check `grep -qE 'math\.sqrt'` seems correct — the fix would add `math.sqrt(variance)`. But the unfixed file already calls `math.sqrt(252)` for the annualization factor. The grep fires immediately, marking the bug as "fixed" even before the agent changes anything.

```python
# UNFIXED code — contains math.sqrt for a different reason:
sharpe = mean_excess / variance * math.sqrt(252)  # BUG: divides by variance
                                      # ↑ this causes grep for 'math\.sqrt' to match!

# FIXED code:
sharpe = mean_excess / math.sqrt(variance) * math.sqrt(252)  # correct
```

**The Fix**: Use a specific grep pattern that is present ONLY in the fixed state, never in the unfixed state:

```bash
# BAD — matches unfixed code (math.sqrt(252) is already there):
if echo "$STATS_CONTENT" | grep -qE 'math\.sqrt'; then BUG_FIXED=true; fi

# GOOD — only matches when the specific fix is applied:
if echo "$STATS_CONTENT" | grep -qE 'math\.sqrt\(variance\)|sqrt\(variance\)'; then BUG_FIXED=true; fi
```

**Detection protocol**: After writing each export script check, manually run it against the *unfixed* setup file content and verify it returns false. The fastest way is a local dry-run:

```bash
# Paste the unfixed code into a temp file and test your grep against it
echo 'sharpe = mean_excess / variance * math.sqrt(252)' | grep -qE 'math\.sqrt\(variance\)' && echo "MATCH (false positive!)" || echo "no match (correct)"
```

**What makes this harder than Lesson 19**: With comments, you can audit by searching for comment lines. Here you must read the unfixed logic holistically and ask: "Does this code already call the function/use the API/have the keyword I'm searching for, even though it's doing something else with it?" Loops, imports, constants, and helper calls are all potential sources.

**Applies to**: Any bug-fix, security-fix, or refactoring task where the export script uses text patterns to detect whether specific code was changed. Common targets: math functions with multiple call sites, imported modules used for different purposes, class names used in both the bug and the fix, SQL keywords that appear in both the vulnerable and safe versions.

---

### 136. Behavioral Tests Must Measure WHEN, Not Just WHETHER

**The Problem**: A test that verifies "did the side effect occur?" will pass even when the underlying mechanism is wrong, as long as the side effect *eventually* happens. This produces a test that appears to validate the fix but is actually insensitive to the bug.

**Classic example**: A test for "process_job must use non-blocking sleep" creates a concurrent coroutine and asserts it ran:

```python
async def test_process_job_not_blocking(registry):
    other_ran = []
    async def other_task():
        await asyncio.sleep(0.01)
        other_ran.append(True)

    await asyncio.gather(process_job(job, registry), other_task())
    assert len(other_ran) == 1  # ← FLAWED: passes even with time.sleep bug!
```

With the bug (`time.sleep(0.1)` blocking the event loop), `other_task` still runs — just 100ms later instead of 10ms later. The assertion `len(other_ran) == 1` is satisfied either way. The test never fails.

**The Fix**: Measure *when* the side effect occurred relative to a known reference point:

```python
async def test_process_job_not_blocking(registry):
    other_done_at = []
    async def other_task():
        await asyncio.sleep(0.01)
        other_done_at.append(time.monotonic())

    start = time.monotonic()
    await asyncio.gather(process_job(job, registry), other_task())

    assert len(other_done_at) == 1, "other_task never ran"
    elapsed = other_done_at[0] - start
    assert elapsed < 0.06, (
        f"other_task completed at {elapsed:.3f}s — expected ~0.01s. "
        "process_job is blocking the event loop."
    )
    # With time.sleep(0.1): elapsed ≈ 0.10s → FAILS (bug detected)
    # With await asyncio.sleep(0.1): elapsed ≈ 0.01s → PASSES (fix confirmed)
```

**The general principle**: Whenever a task's success criterion is a behavioral property (non-blocking I/O, concurrent execution, ordering of operations, bounded latency), the test must observe the *timing* or *ordering* of events — not just whether they happened at all.

| Task type | Wrong check | Correct check |
|---|---|---|
| Non-blocking async sleep | `assert len(results) >= 1` | `assert completion_time - start < threshold` |
| Concurrent task execution | `assert all jobs completed` | `assert total_elapsed < sum_of_individual_times` |
| Ordered callback | `assert callback_called` | `assert callback_time < main_operation_time` |
| Rate limiting | `assert response received` | `assert len(responses_in_window) <= limit` |

**Applies to**: Any environment where tasks involve async I/O, threading, concurrency, scheduled operations, or latency constraints. IDE environments (code debugging tasks), server environments, and any task asking an agent to fix performance or correctness bugs in concurrent code.

---

### 227. Starter Files Must Be Created Before the Task Start Timestamp

**The Problem**: When `setup_task.sh` provides a starter/template file for the agent to work from (a skeleton R script, a broken config, a code project stub), and the verifier awards points for "script modified after task start" or "file is new", the starter file must be created **before** `date +%s > /tmp/task_start_ts` is called. If the starter is created after the timestamp, its mtime will be greater than `task_start` — causing the do-nothing test to return a non-zero score even though the agent touched nothing.

**Classic failure sequence**:
```bash
# WRONG order in setup_task.sh:
date +%s > /tmp/task_start_ts        # (1) record timestamp

# ... package installs, downloads ...

cat > /home/ga/starter.R << 'EOF'    # (2) create starter AFTER timestamp
# template code for agent to fill in
EOF
```

The export script then checks:
```bash
FILE_MTIME=$(stat -c %Y /home/ga/starter.R)
[ "$FILE_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_MODIFIED=true
# → true, even though the agent never opened the file
```

The verifier awards "script modified" points in the do-nothing test. The do-nothing score is non-zero, which invalidates the test.

**The Fix**: Create all starter/template files **before** recording the timestamp. Then record the timestamp. Package installation, data downloads, and app launch can all happen after the timestamp — they don't create files the verifier checks.

```bash
# CORRECT order in setup_task.sh:

# (1) Remove stale output files
rm -f /home/ga/RProjects/output/*.csv /home/ga/RProjects/output/*.png

# (2) Create starter file BEFORE timestamp
cat > /home/ga/starter.R << 'EOF'
# Skeleton code — agent must fill in
EOF

# (3) Record timestamp (starter mtime is now <= task_start)
date +%s > /tmp/task_start_ts

# (4) Install packages, download data, launch app — all after timestamp (fine)
R --vanilla --slave -e "install.packages('somepackage', quiet=TRUE)"
su - ga -c "DISPLAY=:1 rstudio /home/ga/starter.R &"
```

**Why package installation after the timestamp is safe**: Package installation creates files in R library directories or system paths, not at the output paths the verifier checks. Only files whose modification time is explicitly checked (starter scripts, output CSVs, output PNGs) need to pre-date the timestamp.

**The three-part ordering rule for setup_task.sh**:
1. Remove stale output files (so old outputs are gone, not "new")
2. Create starter/template files (so they are "old" before the task begins)
3. Record `TASK_START` timestamp ← this is the boundary between "old" and "new"
4. Everything else: installs, downloads, launch, screenshot

**How this interacts with error-injection tasks** (Lesson 1 pattern in `01_core_principles.md`): For tasks where `setup_task.sh` creates a *deliberately broken* config or code file for the agent to repair, the same rule applies. The broken file must be created before the timestamp so that agent-modified versions of it will correctly show as "new". An agent that repairs and saves the file will produce a new mtime > task_start; the original broken file's mtime will be ≤ task_start.

**The diagnostic**: After writing a new `setup_task.sh`, run this check:
```bash
# After setup_task.sh runs (do-nothing state):
TASK_START=$(cat /tmp/task_start_ts)
STARTER_MTIME=$(stat -c %Y /home/ga/starter.R)
[ "$STARTER_MTIME" -le "$TASK_START" ] && echo "OK: starter predates task start" \
                                       || echo "BUG: starter is newer than task start"
```

If this prints "BUG", the starter was created after the timestamp and will give free points in the do-nothing test.

**Applies to**: Any environment where `setup_task.sh` provides a starter/template file and the verifier checks whether that file was modified after task start. Particularly common in: scientific computing environments (R, Python, MATLAB), code editor environments (IDE tasks with a starting project), document editors (a pre-seeded document the agent must edit), and configuration-repair tasks (a broken config the agent must fix).

---

## Lesson 228: Algorithm/model selection is a legitimate and potent difficulty axis for complex technical software

**Context**: Many technical software packages offer multiple computation models for the same physical system — a simplified "fast" model and a detailed "physics-based" model. PVWatts vs. CEC Pvsamv1 in SAM, NASTRAN's linear vs. nonlinear solver, MATLAB's ode45 vs. ode15s, OpenFOAM's steady-state vs. transient solvers. The simplified model often accepts only aggregate inputs (DC capacity, a single efficiency number) while the detailed model accepts per-component parameters (individual I-V curve coefficients, temperature coefficients, material properties).

**The difficulty pattern**: If a task requires comparing items that differ in a parameter only the detailed model captures (e.g., temperature coefficients that differ by technology class), then an agent that defaults to the simplified model will produce identical or nearly-identical results for all items — an obviously wrong outcome that signals to a careful agent that the model choice was wrong. This "failure signal" is itself a teaching moment requiring domain reasoning to interpret.

**How to use this as a task design tool**:
1. Identify a parameter that meaningfully differentiates the items being compared (temperature coefficient, material bandgap, aerodynamic roughness class, kinematic viscosity).
2. Make the simplified model *incapable* of accepting that parameter — it only takes aggregate inputs.
3. Task description: state that "a bankability-grade analysis requires modeling each technology's individual [parameter]" or equivalent professional framing, without naming the specific model or API.
4. Verifier anti-bypass: check `.py` or script files for import patterns specific to the detailed model (`Pvsamv1`, `cec_v_mp_ref`, `nonlinear`, etc.).

**Why this works as a difficulty axis**: Selecting the wrong computation model produces plausible-looking numbers, not an obvious crash or error. The agent must notice that all outputs are suspiciously similar and reason about why — which requires genuine understanding of what the simplified model abstracts away.

**Applies to**: Any environment where the software has tiered computation models: energy simulation (SAM, EnergyPlus, TRNSYS), structural analysis (ANSYS, Abaqus), computational chemistry (DFT vs. force-field), fluid simulation (RANS vs. LES), or financial modeling (Black-Scholes analytic vs. Monte Carlo).

---

## Lesson 138: Unit normalization in verifiers for technical and engineering software

**Context**: In engineering and scientific software, the same physical quantity is often reported in different units depending on which module, post-processor, or output format was used. Examples from energy simulation:
- LCOE: cents/kWh (SAM default internal), $/MWh (common industry usage), $/kWh (residential context)
- Annual energy: kWh, MWh, GWh depending on system scale
- Power: kW, MW, GW
- Demand charges: $/kW-month vs. $/kW-year

**The problem**: A verifier that checks `20 <= lcoe_value <= 80` will incorrectly fail an agent that correctly computed 4.5 ¢/kWh (= 45 $/MWh, which is in range) if that agent reported in $/MWh, or incorrectly pass an agent that reported 4.5 when the verifier expected 45.

**The fix — three-layer normalization**:
1. **In the output JSON spec** (in `task.json`): explicitly state the required unit for each numeric output field. Example: `"lcoe_nominal": "$/MWh"`. This eliminates ambiguity at the agent level.
2. **In `export_result.sh`**: add a plausibility range guard that detects likely unit errors. If the extracted value is in [0.01, 0.5] when the expected range is [20, 80], flag it as a likely ¢/kWh → $/MWh conversion error rather than a wrong answer.
3. **In `verifier.py`**: add a unit-detection heuristic — if the raw value is in a plausible "wrong unit" range, attempt conversion and note the discrepancy in the score report rather than silently failing.

**A secondary issue**: capacity factor is dimensionless but sometimes reported as a fraction (0.28) and sometimes as a percentage (28%). Build verifiers to accept both by normalizing: `if cf > 1: cf = cf / 100`.

**General rule**: For every numeric output field in a technical verifier, ask: "What unit would a correct but unit-naive agent report this in?" If the answer differs from your expected unit, add explicit normalization. The cost is two lines of code; the benefit is avoiding false failures that mask genuinely correct agent work.

**Applies to**: Any environment producing numeric outputs with multiple valid unit conventions — energy (kWh/MWh/GWh, kW/MW, $/kWh vs. ¢/kWh), chemistry (molar vs. mass concentration), structural engineering (Pa vs. MPa vs. GPa), finance (basis points vs. percent vs. decimal), geospatial (degrees vs. radians, meters vs. kilometers).

---

### 173. Verify That All Criterion Point Values Sum Exactly to the Intended Maximum Score

**The problem**: In a multi-criterion verifier, each criterion has a maximum point value. If the sum of ALL maximum values exceeds the intended task maximum (typically 100), a `min(score, 100)` clamp will silently hide the bug — but partial-completion scenarios will produce incorrectly inflated scores. An agent that, for example, completes 4 of 5 subtasks may score 100 (instead of ~80) because the overcapped total happens to cross 100 even without the 5th subtask.

**Concrete example**: A wiki task has 5 tiddlers × 8 pts each = 40 pts, plus tables (10), tags (10), links (9), words (7), GUI save (14) = 90 pts additional. Total max = 130. The `min(score, 100)` clamp means anyone with all tiddlers + GUI save already has 40 + 14 = 54 pts and may reach 100 with only partial coverage of other criteria. The partial scenario should fail, but it scores 100.

**The fix**: After writing the verifier, sum every criterion's maximum explicitly in a comment:

```python
# Maximum score breakdown — must sum to exactly 100:
# Tiddlers found:   5 × 7 pts  =  35
# Tag A:            min(5, N)   =   5
# Tag B:            min(5, N)   =   5
# Tables:           min(10, N)  =  10
# Links:            min(5, N)   =   5
# Headings:         min(5, N)   =   5
# Word count:       min(5, N)   =   5  (2 pts/tiddler)
# GUI save:                     =  14
# Hub→existing link:            =   6
#                        TOTAL  = 100  ← confirm this
```

If the sum is > 100, reduce the highest per-item point value until the sum equals exactly 100. Never rely on `min(score, 100)` to hide the surplus — it silently produces false-100 scores for partial completions.

**The diagnostic test**: After writing the offline tests (Lesson 118), explicitly check the *partial* scenario. If a test that should score ~70 scores 100, the overcap has masked the error. Re-examine the criterion breakdown.

**Applies to**: All multi-criterion verifiers. Particularly acute in tasks with per-item partial scoring (N items × P pts each) combined with cross-cutting bonuses (GUI save, tag checks, word count), where the combination can exceed the 100-point ceiling without the task author noticing.

---

### 174. Discover Application Filename Sanitization Rules Before Writing Filesystem-Based Verification

**The problem**: Many applications silently transform user-visible display names (titles, labels) into filesystem paths using app-specific sanitization rules. If your export script or verifier looks up files by a naively derived path (e.g., replacing spaces with underscores), it may never find the actual file because the app used different rules — and the verifier will return score=0 for every correct submission.

**Common sanitization patterns by application type**:

| Application type | Common rule |
|---|---|
| TiddlyWiki | Replaces `/:*?"<>|` with `_`; spaces preserved |
| Obsidian | Replaces `/` and `\` only; other characters preserved |
| WordPress/MediaWiki | Spaces → `_`, colons stripped, lowercased |
| JIRA / Confluence | URL-encoded, spaces → `+`, special chars → `%XX` |
| Windows file dialogs | Strips `*?"<>|:` but keeps most others |
| Python `os.path` | Nothing — you must sanitize explicitly |

**The discovery protocol**: Before writing a single line of filesystem-based verification for a new environment, do the following:

```bash
# 1. Create a test entity with a known display name from the GUI
# 2. Immediately look at what filename appeared on disk
ls -la /path/to/app/data/  # or equivalent

# 3. Try names with: spaces, hyphens, apostrophes, colons, parentheses, slashes
# 4. Document the rule in the task's README before moving on
```

**In export scripts and verifiers**, once the rule is known, normalize both the expected name and the actual filename using the same transformation:

```python
import re

def sanitize_title(title, app="tiddlywiki"):
    if app == "tiddlywiki":
        return re.sub(r'[/:*?"<>|\\]', '_', title)
    # Add other apps as discovered
    return title

expected_path = sanitize_title("My Document: Part 1")
# → "My Document_ Part 1"  (not "My_Document__Part_1")
```

**Symptoms of a sanitization mismatch**: The export script checks for a file by name, finds nothing, reports `found=False`, and the verifier scores 0 — even when the agent created the file correctly. If do-nothing and full-completion both score 0, check file naming first.

**Applies to**: Any task that creates or modifies files using names derived from user-visible entity titles — wiki tiddlers, notes, documents, project files, database-backed exports. Especially relevant for applications that support a broad character set in their UI while storing files on case-insensitive or character-restricted filesystems (NTFS, FAT32, ext4 with restricted names).

---

### 175. Use Application Server Logs as an Anti-Gaming Signal for Client-Server Applications

**The problem**: For applications with a client-server architecture (web-based UIs, local servers serving a browser frontend, Jupyter, TiddlyWiki, WikiJS, Gitea, and similar tools), an agent can bypass the GUI entirely by writing files directly to disk. Direct file writes produce correct content but skip server-side processing — they will not appear in the server's event log. A verifier that checks only file content awards full credit to both the legitimate GUI path and the bypass path.

**The pattern**: Client-server apps always log server-mediated interactions. When the agent uses the browser or UI to save a document, the server handles the PUT/POST request and logs it. When the agent writes directly to disk with `tee`, `cat`, or Python `open()`, nothing appears in the server log.

**How to use this in export scripts**:

```bash
# Example: TiddlyWiki server log entries
# Legitimate GUI save triggers: "syncer-server-filesystem: Dispatching 'save' task: <title>"
GUI_SAVE_DETECTED=false
if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
    GUI_SAVE_DETECTED=true
fi

# Example: Jupyter server log
# Legitimate notebook save triggers a PUT /api/contents/<path> entry
if grep -qE "PUT /api/contents" /var/log/jupyter.log 2>/dev/null; then
    GUI_SAVE_DETECTED=true
fi

# Example: Flask/Django application
# Any authenticated POST from localhost:port is a browser-mediated action
if grep -qE '"POST /.* HTTP.*" 20[0-9]' /var/log/app.log 2>/dev/null; then
    GUI_SAVE_DETECTED=true
fi
```

**In the verifier**: Make GUI save detection a hard requirement in the pass condition, and award meaningful points (10–15% of total) for it as a scored criterion. An agent that bypasses the server should be able to score up to ~85% (correct content, correct file) but must fail (`passed=False`) because the server interaction criterion failed.

```python
gui_save = result.get('gui_save_detected', False)
if gui_save:
    score += 14
    parts.append("GUI save verified via server log (+14 pts)")
else:
    parts.append("FAIL: No server-mediated save — direct file write suspected")

# In pass condition — require gui_save regardless of content score:
passed = content_score >= threshold AND gui_save
```

**Finding the right log file**: Start by running `ps aux | grep <server>` to find the process, then check its startup flags for a log path. Common locations: `/var/log/<appname>.log`, `/tmp/<appname>.log`, `/home/<user>/<appname>.log`, or the server's `stdout` if launched as a service (check `journalctl -u <service>`).

**Caveat**: REST API calls from the agent itself also go through the server and will appear in the server log. Server log detection proves that a server round-trip occurred, not that the *browser* specifically was used. For stronger browser verification, combine server log detection with trajectory analysis (check that the agent's actions include browser navigation steps). For most benchmark purposes, server log detection alone is sufficient.

**Applies to**: Any task in a client-server environment where direct filesystem manipulation is a plausible bypass. Particularly relevant for: wiki applications (TiddlyWiki, MediaWiki, Outline), notebook environments (Jupyter, Zeppelin), content management systems, self-hosted web applications, and any application where the agent can plausibly `curl` or write files directly while also being able to use a browser GUI.

---


### 176. Index-Mediated Metadata: Close the App and Wait Before Reading Back User Actions

**The Problem**: Many desktop applications maintain two kinds of storage for the same data: a **main data file** (mbox, XML, JSON) and a **separate index or cache file** (.msf, .db, .thumbnail, .cache). User-generated metadata—email tags, starred/flagged status, read/unread markers, annotations, custom labels—is often written first to the index file for performance, and only synced back to the main data file when the application closes cleanly or the folder is explicitly "compacted."

This creates a verification trap: you can read the main data file while the app is running and find the underlying content (the emails, documents, media), but the freshly-applied metadata fields will not yet be present in the main file. They are in the index, which is binary or opaque.

**Thunderbird example**:
- `X-Mozilla-Keys: $label1` (the "Important" tag) is an `mbox` header field — it lives in the email's `.sbd/FolderName` file.
- When the agent right-clicks and applies a tag, Thunderbird writes the change to the `.msf` (mail summary file) index, **not** immediately to the `.sbd` mbox.
- Only when Thunderbird exits cleanly (graceful shutdown, not kill -9) are the tag fields flushed from the `.msf` back into the mbox.
- If `export_result.sh` reads the mbox with `mailbox.mbox()` before closing Thunderbird, it will find the email but see `X-Mozilla-Keys: ` (empty).

**General pattern — two-layer storage in desktop apps**:
| Application | Main data file | Index/cache | Metadata requiring flush |
|---|---|---|---|
| Thunderbird | `FolderName` mbox | `FolderName.msf` | Tags, starred, read status |
| Beets / MusicBrainz Picard | MP3/FLAC file (ID3 tags) | SQLite database | Rating, genre corrections |
| digiKam / Shotwell | JPEG/RAW file (EXIF) | SQLite database | Stars, color labels, geo-tags |
| Calibre | EPUB/PDF file | `metadata.db` | Tags, series, custom columns |
| Firefox | HTML bookmarks | `places.sqlite` | Last-visited, tag assignments |

**The Fix**: In `export_result.sh`, always close the application gracefully before reading any metadata from the main data file. A graceful close — not `kill -9` or `pkill -f <binary>` — is required to trigger the flush:

```bash
# In export_result.sh — close app GRACEFULLY before reading user-generated metadata
close_thunderbird   # sends SIGTERM + waits for clean exit; provided by task_utils.sh
sleep 3             # allow OS to finish file writes

# Now safe to read tags, flags, labels from the main mbox file
python3 << 'PYEOF'
import mailbox
mb = mailbox.mbox("/home/ga/.thunderbird/default-release/Mail/Local Folders/Referrals.sbd/Urgent_Referrals")
for msg in mb:
    keywords = msg.get('X-Mozilla-Keys', '') or ''
    print(keywords)
mb.close()
PYEOF
```

**How to identify which fields require a flush**: Before designing verifiers, perform the action manually in the application, then immediately check the main data file (without closing the app) to see if the field appears. If it doesn't, close the app and re-check. If it appears only after close, you have an index-mediated field.

```bash
# Test: apply a tag in Thunderbird without closing it
grep "X-Mozilla-Keys" /home/ga/.thunderbird/default-release/Mail/Local\ Folders/Inbox
# → (empty or absent)

# Kill Thunderbird (gracefully), then re-check
pkill -x thunderbird && sleep 3
grep "X-Mozilla-Keys" /home/ga/.thunderbird/default-release/Mail/Local\ Folders/Inbox
# → X-Mozilla-Keys: $label1
```

**Why `kill -9` is wrong here**: Force-killing the application prevents the flush from happening at all — the index changes are discarded and the main data file is never updated. The only reliable mechanism is a graceful exit that allows the application to run its shutdown procedure.

**Distinguishing this from Lessons 28 and 35**:
- Lesson 28 (config flush on exit): The config file is unreadable/stale until exit because the app holds the authoritative state in memory. Close → flush → readable.
- Lesson 35 (SQLite lock): The database is locked against writes while the app runs. Close → release lock → writable.
- **This lesson (index-mediated metadata)**: The main data file IS readable while the app runs (you get the emails/documents), but specific metadata fields are stale because they live in a separate index. Close → index flushed to main file → metadata readable.

All three require closing the app first — but the diagnosis of why differs, and consequently so does the debugging strategy.

**Applies to**: Any environment where the application uses an index file alongside its main data files: email clients (mbox-based), music taggers, photo managers, document managers, and any application with a "compact folder" or "optimize database" feature (a sure indicator of deferred write-back).

---

### 177. Shared App-Internal State Files Require Targeted Cleanup per Task in setup_task.sh

**The Problem**: Beyond `/tmp/` filenames (Lesson 164), many applications maintain **global state files** that are shared across all task runs within the same environment:

- An email client's **Drafts folder** — a single mbox containing all saved drafts, shared across every task
- An email client's **address book** — one database shared by all tasks, even if different tasks add different contacts
- An email client's **filter rules file** — one file; multiple tasks may create different filters
- An application's **history or recently-opened list** — one list shared across all tasks

When two tasks exercise the same shared state file and the VM is reused (which happens during testing and at evaluation time when tasks run back-to-back), a stale entry from Task A's previous run can satisfy Task B's verifier — without the agent having done any work.

**Concrete failure scenario**:
- Task 2 requires composing a draft email to `jkowalski@sec.gov` and saving it.
- The developer runs Task 2's setup → agent test → export pipeline.
- The draft to `jkowalski@sec.gov` now exists in the Drafts mbox.
- Task 2's pipeline is run again with `use_cache=True` but without clearing the Drafts folder.
- The export script finds the draft from the first run, verifier awards full points to a do-nothing agent.

**Why this is different from Lesson 164**: Lesson 164 addresses `/tmp/` file name collisions between tasks. This lesson addresses **task-specific content** that accumulates inside application-owned data files. The file name (`Drafts`) is always the same — the collision is in the *content* of the file.

**The Fix**: In `setup_task.sh`, for every shared application state file that your `export_result.sh` will inspect, add a targeted cleanup step that removes **only the entries matching your task**. Do not wipe the entire file — that would remove state injected for the task scenario itself.

```bash
# BAD: Wipes everything — may remove injected task emails too
rm -f "/home/ga/.thunderbird/default-release/Mail/Local Folders/Drafts"

# GOOD: Remove only drafts addressed to this task's target
python3 << 'PYEOF'
import mailbox, os

drafts_path = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/Drafts")
if os.path.exists(drafts_path) and os.path.isfile(drafts_path):
    try:
        mb = mailbox.mbox(drafts_path)
        mb.lock()
        to_remove = [k for k, msg in mb.items()
                     if 'jkowalski@sec.gov' in (msg.get('To', '') or '').lower()]
        for k in to_remove:
            mb.remove(k)
        mb.flush()
        mb.unlock()
        mb.close()
        print(f"Removed {len(to_remove)} pre-existing draft(s)")
    except Exception as e:
        print(f"Cleanup: {e}")
PYEOF
```

**A complete inventory check for your environment**: Before finalizing `setup_task.sh` for a new task, list every shared state file that `export_result.sh` reads and explicitly answer: "Can a previous run of any task leave a stale entry here that satisfies my verifier?"

For email client environments, the common shared state files to audit are:
| File | Shared across tasks | Cleanup action |
|---|---|---|
| `Local Folders/Drafts` | All draft-composition tasks | Remove drafts to task-specific recipient |
| `Local Folders/Sent` | All send tasks (uncommon in benchmarks) | Remove sent items with task-specific subject |
| `abook.sqlite` | All address-book tasks | Remove contact matching task's target email |
| `msgFilterRules.dat` | All filter-creation tasks | Reset to `version="9"\nlogging="no"\n` |
| `Local Folders/<any folder>` | All routing tasks | Remove with `rm -f` (setup reinjects anyway) |

**Applies to**: Any environment where multiple tasks in the same environment interact with the same globally-shared state file. Most prevalent in email clients, calendar/contacts applications, note-taking apps with a single shared notebook, and any application with a "recently opened" history.

---

### 178. Draw the Feature Matrix Before Writing Any Implementation Scripts

**The Problem**: The feature diversity requirement (each feature combination must appear in at most 2 of the 5 tasks) is described in `01_core_principles.md` — but if you discover a violation *after* writing `setup_task.sh`, `export_result.sh`, and `verifier.py` for all 5 tasks, fixing it requires editing 4 files per affected task. Description changes are cheap; script changes are expensive.

**When the mistake happens**: A natural workflow when creating 5 tasks is to write task descriptions → write scripts for each task in sequence. When writing Task 3, it's easy to copy-paste the structure from Task 2 (which already has a working verifier template), inadvertently reusing the same 4th feature. By Task 5, you've written 20 script files and then realize the feature matrix has 3 tasks sharing the same 4-feature combination.

**The Fix**: Treat the feature matrix as a **blocking gate** between the description phase and the implementation phase:

```
Phase 1 (cheap): Write all 5 task.json descriptions
           ↓
    STOP: Draw the feature matrix
    Check: no combination appears in more than 2 tasks
    Fix: change task descriptions to diversify (cheap)
           ↓
Phase 2 (expensive): Write setup_task.sh, export_result.sh, verifier.py
```

**Practical checklist before writing the first `setup_task.sh`**:
```
Feature matrix for <env_name> — drawn before implementation:

           | Feature A | Feature B | Feature C | Feature D | Feature E |
Task 1     |     ✓     |     ✓     |     ✓     |     ✓     |           |
Task 2     |     ✓     |     ✓     |     ✓     |           |     ✓     |
Task 3     |     ✓     |     ✓     |     ✓     |           |     ✓     |  <-- collision with Task 2
Task 4     |     ✓     |     ✓     |     ✓     |     ✓     |           |  <-- collision with Task 1
Task 5     |     ✓     |     ✓     |     ✓     |     ✓     |           |  <-- triple collision! redesign now.
```

**The rule**: If any cell in the matrix shows a 3rd tick for the same feature combination, redesign the task description before writing any scripts. Adding a new verifiable feature is always possible at the description phase; retrofitting a new feature into a working 4-file script set is expensive and error-prone.

**Identifying new verifiable features for your application**: When you need to replace a feature to fix a matrix collision, first explore the application's data storage directory and observe what changes after each user action. New candidates will appear as new/modified files or new rows in a database. Common under-used but verifiable features in typical desktop apps include:
- **Draft/unsent content**: files in a Drafts folder (email, documents, code)
- **User annotations**: comment fields, tag metadata, sticky notes, bookmarks
- **Status changes**: read/unread, flagged/starred, archived, prioritized
- **Export outputs**: files generated by the agent (PDFs, CSVs, reports, images)
- **Account/profile settings**: preferences, signature, notification rules

**Applies to**: Every task creation effort for any new environment. The feature matrix check must happen between writing task descriptions and writing task scripts — not after all scripts are written.

---

---

### 179. The export_result.sh JSON Field Names Are a Contract — Verify Consistency with verifier.py

**The Problem**: When writing `export_result.sh` and `verifier.py` independently (the natural workflow), it is very easy to use slightly different field names for the same logical check. The export script might produce `"history_has_ddg_search"` while the verifier reads `"history_has_ddg_onion_search"`. Both files compile and run without errors — the mismatch is silent. The verifier simply reads `False` for every field whose name differs, producing a permanently-zero score that looks like the agent never completed the task.

**Why it's dangerous**: Offline mock tests can also miss this bug if you write the mock data from memory (using the field names you *think* the export produces) rather than from the actual script output. The bug surfaces only when you run both scripts together on a live VM — or when a capable agent scores 0 despite visibly completing the task.

**The Fix**: Treat the JSON field names as a shared contract. Define them in one place before writing either script:

```bash
# At the top of both export_result.sh and verifier.py, document the schema:
# Result JSON fields:
#   prefs_file_exists       bool  — prefs.js exists (browser was opened)
#   security_slider         int   — 1=standard, 2=safer, 4=safest
#   https_only_enabled      bool  — dom.security.https_only_mode is true
#   prefetch_disabled       bool  — network.prefetch-next is false
#   history_never_saved     bool  — places.history.enabled=false OR autostart=true
```

After writing `export_result.sh`, extract the actual JSON it produces on a live VM and build your mock data for offline verifier tests from that real output. Never write mock data from memory.

**Verification step**: After writing both files, run this one-liner to catch mismatches:
```bash
# Extract keys from export script's JSON template
grep -oP '"[a-z_]+"(?=:)' export_result.sh | sort > /tmp/export_keys.txt
# Extract keys the verifier reads
grep -oP "result\.get\('[a-z_]+'" verifier.py | grep -oP "'[a-z_]+'" | tr -d "'" | sort > /tmp/verifier_keys.txt
diff /tmp/export_keys.txt /tmp/verifier_keys.txt
```
Any line appearing only in `verifier_keys.txt` is a field the verifier reads that the export never writes — guaranteed zero score on that criterion.

**Applies to**: Every new task with a verifier that reads a JSON result file produced by an export script. This is the normal pattern for all gym-anything tasks.

---

### 180. Offline Verifier Tests Are Sufficient Validation — You Do Not Need a Live VM for Scoring Logic

**The Problem**: The checklist requires do-nothing, partial, and wrong-target tests. A naive reading suggests these all require a running VM. In practice, the verifier function is a pure function of its JSON input — it does not call the VM at runtime (it calls `copy_from_env` once to read a file, then operates entirely locally). This means all three test variants can be run without a VM by directly passing mock JSON to the verifier.

**When live testing is blocked**: SSH connectivity to QEMU VMs is intermittently unreliable. The Python runner's `exec_capture` uses paramiko, which can fail even when command-line SSH (same key, same port) works. When paramiko fails, all hook execution fails — setup scripts don't run, export scripts don't run — but the environment is otherwise ready.

**The correct approach when live testing is unavailable**:

```python
import importlib.util, json, shutil, tempfile, os

def run_verifier_offline(task_name, result_dict):
    """Run verifier with mock result JSON, no VM needed."""
    path = f'benchmarks/cua_world/environments/<env>/tasks/{task_name}/verifier.py'
    spec = importlib.util.spec_from_file_location(f"v_{task_name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    verify_fn = getattr(mod, f'verify_{task_name}')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w')
    tmp.write(json.dumps(result_dict))
    tmp.close()

    def copy_from_env(src, dst):
        shutil.copy(tmp.name, dst)

    result = verify_fn([], {'copy_from_env': copy_from_env}, {})
    os.unlink(tmp.name)
    return result

# Do-nothing: copy_from_env raises (file not found in VM)
def copy_raises(src, dst): raise Exception("Connection refused")
result = verify_fn([], {'copy_from_env': copy_raises}, {})
assert result['score'] == 0 and not result['passed']  # ✓

# Partial: fill in only some fields
result = run_verifier_offline(task_name, partial_data)
assert 0 < result['score'] < 100 and not result['passed']  # ✓

# Perfect: fill in all fields correctly
result = run_verifier_offline(task_name, perfect_data)
assert result['score'] == 100 and result['passed']  # ✓
```

**What live testing adds that offline cannot**: (1) Confirming the export script *produces* the expected JSON on the real system (field names, data types, edge case handling). (2) Confirming the setup script correctly establishes the starting state. These two are the only reasons to use a live VM during task creation — and they can be deferred to the first time an agent actually runs the task.

**The checklist items that require live VM** are specifically about the *setup* and *export* scripts, not the *verifier*. The verifier can always be fully tested offline.

**Applies to**: Any task creation effort where live VM testing is slow, unreliable, or unavailable. Offline verifier tests are also faster (seconds vs minutes) and produce deterministic results, making them valuable even when live testing is available.

---

### 181. QEMU SSH "Available" Detection Is a TCP Port Check, Not an Auth Check — Use a 300s+ Timeout

**The Problem**: When `env.reset()` prints `[QemuApptainer] SSH available!` and then immediately fails with `[QemuApptainer] SSH key auth failed (code 255)`, the two messages look contradictory. They are not: the "available" check only confirms the TCP port is accepting connections; the subsequent auth failure means the SSH *daemon* is running but not yet ready to authenticate. This transient period typically lasts 2–5 minutes after QEMU starts.

**Observed failure pattern**:
```
[QemuApptainer] SSH available!          ← TCP port 22 is open
[QemuApptainer] Setting up mounts...   ← file copies via SSH succeed
[QemuApptainer] Desktop ready after 10.6s
[QemuApptainer] SSH key auth failed (code 255)  ← daemon rejecting auth
[QemuApptainer] Paramiko error: Unable to connect to port XXXX  ← or port closed again
```

The runner's mount copies succeed because they happen immediately after the TCP check. The hook execution (`pre_start`, `post_start`, `pre_task`) fails because paramiko uses a different code path with stricter connection handling.

**Separate issue — paramiko vs. command-line SSH**: Even when the SSH port is fully ready, paramiko may fail while `ssh -i key ga@localhost` succeeds. This is caused by system-level differences in how paramiko handles certain SSH server configurations, ciphers, or key exchange algorithms. If you need to run SSH commands from a test script, use `subprocess.run(['ssh', ...])` rather than relying on the runner's `exec_capture`.

**The Fix**: When writing any test script that polls for SSH readiness, use a timeout of **at least 300 seconds** (5 minutes), not 60 or 120 seconds:

```python
def wait_for_ssh(port, max_secs=360):
    start = time.time()
    while time.time() - start < max_secs:
        try:
            r = subprocess.run(
                ['ssh', '-i', key, '-o', 'StrictHostKeyChecking=no',
                 '-o', 'UserKnownHostsFile=/dev/null',
                 '-o', 'ConnectTimeout=8', '-o', 'BatchMode=yes',
                 '-p', str(port), 'ga@localhost', 'echo ok'],
                capture_output=True, text=True, timeout=10
            )
            if r.returncode == 0 and 'ok' in r.stdout:
                return True
        except Exception:
            pass
        time.sleep(5)
    return False
```

**Tip**: The SSH readiness lag is longer when the VM is running resource-intensive startup scripts (e.g., Tor Browser's `install_tor_browser.sh` which downloads and installs a large package). For environments with heavy startup hooks, budget 8–10 minutes.

**Applies to**: Any QEMU-based environment where you write test scripts that wait for SSH. The same behavior applies to Docker-based environments where the container's sshd takes time to configure itself.

---

### 182. Jupyter Notebook Execution Detection — Use `execution_count`, Not `mtime`

**The Problem**: For tasks where the agent works in a Jupyter notebook, a natural "did the agent do anything?" check is to compare the notebook file's `mtime` against `task_start_ts`. This check is always True — because `setup_task.sh` creates the starter notebook during setup, which happens *after* `task_start_ts` is recorded. Every do-nothing agent sees a notebook that is "newer than task start" because setup wrote it after recording the timestamp. The `mtime` gate provides zero discrimination.

This is a specific instance of the Lesson 169 ordering problem, but cannot be fixed by re-ordering setup steps: the notebook must be created by setup (the agent needs it as a starting artifact), and `task_start_ts` must be recorded after setup completes (otherwise no agent actions would be "after start"). The two events are inherently inverted.

**Why `execution_count` is the correct signal**: A freshly created Jupyter notebook has every code cell's `execution_count` field set to `null`. When the agent runs a cell — even once — Jupyter sets `execution_count` to a positive integer. This is written into the `.ipynb` JSON regardless of whether the agent saves explicitly, because Jupyter updates the file on every cell execution.

```python
# verifier.py — detect whether the agent ran any notebook cells
import json, os

def count_executed_cells(notebook_path):
    """Returns the number of code cells with a non-null execution_count."""
    try:
        with open(notebook_path) as f:
            nb = json.load(f)
    except Exception:
        return 0
    count = 0
    for cell in nb.get("cells", []):
        if cell.get("cell_type") == "code":
            if cell.get("execution_count") is not None:
                count += 1
    return count

executed = count_executed_cells(local_notebook_path)
if executed == 0:
    return {"passed": False, "score": 0, "feedback": "No notebook cells were executed"}
```

**Do-nothing test behavior**: A do-nothing agent never runs any cells. The starter notebook has all `execution_count: null`. `count_executed_cells()` returns 0. Gate fires, score=0 ✓

**Partial completion test behavior**: An agent that runs N cells but produces no output files has `executed >= 1` but fails the output-existence criteria. Correctly scored as partial. ✓

**What `execution_count` does NOT tell you**: It confirms cells were executed, but not that the output files are correct or that the right analysis was performed. Gate execution detection should always be paired with content-based output verification criteria.

**Do NOT check** `outputs` field non-emptiness as a proxy — some cell types (print statements, side-effect-only code) produce no `outputs` entries even when executed. `execution_count` is the authoritative signal.

**Applies to**: Any environment where the agent's primary work surface is a Jupyter notebook (`.ipynb`) — data science environments, scientific simulation tasks, analytics pipelines, exploratory analysis tasks. This includes environments that use `urbansim`, `statsmodels`, `pandas`, or any other library where the canonical interface is a notebook.

**Rule**: For Jupyter notebook tasks, never use `mtime > task_start_ts` as the "did the agent do anything?" check. Always check `execution_count is not None` for code cells. The mtime check will always pass because the setup script creates the notebook after recording the task start timestamp.

---

### 183. Framework Usage Verification via Notebook Cell Source Code

**The Problem**: For tasks that require the agent to use a specific framework or library (e.g., orca for urban simulation, scikit-learn for machine learning, statsmodels for econometric modeling), it is possible for an agent to produce correct-looking output *without* using the specified framework. An agent might hard-code results, use an alternative library that produces numerically compatible output, or copy values from the task description. A verifier that checks only output file content rewards this shortcut with full marks.

This matters because the task is implicitly about the agent's ability to operate the designated software, not just its ability to produce numbers. A housing policy analyst who pastes fake values into a CSV rather than running UrbanSim has not demonstrated the skill the task measures.

**The Fix — source code scanning in the verifier**: After copying the notebook to a temp path, parse its JSON and search code cell sources for framework-specific import patterns and API calls. Award a criterion for confirmed framework usage:

```python
import json, re

def check_framework_usage(notebook_path, required_patterns):
    """
    Returns True if any code cell in the notebook contains all required_patterns.
    required_patterns: list of regex strings that must ALL match somewhere in cell sources.
    """
    try:
        with open(notebook_path) as f:
            nb = json.load(f)
    except Exception:
        return False

    all_source = "\n".join(
        "".join(cell.get("source", []))
        for cell in nb.get("cells", [])
        if cell.get("cell_type") == "code"
    )
    return all(re.search(p, all_source) for p in required_patterns)

# Example: verify agent used the orca simulation framework
used_orca = check_framework_usage(local_notebook_path, [
    r"import orca|from orca",       # framework imported
    r"@orca\.step|orca\.add_table|orca\.run",  # framework-specific API calls
])

if used_orca:
    score += 15   # criterion: used required tool
else:
    feedback.append("Agent did not use the orca simulation framework")
```

**Pattern selection guidelines**:
- Use the framework's canonical import statement as the minimum signal: `import orca`, `from sklearn`, `import statsmodels`
- For stronger evidence, also require at least one framework-specific API call: `orca.run(`, `LinearRegression()`, `OLS(`
- Do NOT require a specific call signature — agents may use the API correctly in multiple ways
- Do NOT fail the task for missing framework usage alone (award 0 pts for that criterion, but still score other criteria); framework usage should be one criterion among many, not a gate

**What this does NOT catch**: An agent that writes the correct `import` statement but never actually calls any framework methods. For these cases, combine with Lesson 182's `execution_count` check (cells must have been run) and output-existence checks (CSV/plot must exist with correct content).

**When to apply**: Any task whose primary learning objective is "use this specific software to compute X" rather than "produce output with these properties." Especially applicable to:
- Urban simulation (orca/urbansim): verify `@orca.step`, `orca.run(iter_vars=...)`
- Statistical modeling (statsmodels): verify `OLS(`, `fit()`, `summary()`
- Machine learning (scikit-learn): verify `fit(`, `predict(`
- Domain-specific simulation frameworks with distinctive API signatures

**Do NOT apply**: To tasks where the agent has legitimate freedom to choose any method (e.g., "compute the mean rent by zone" — any approach producing the correct numbers is acceptable). Only scan for framework usage when the task description specifically names the tool the agent must use.

**Rule**: For Jupyter notebook tasks that require a specific framework, add a criterion that checks notebook cell sources for framework-specific import and API call patterns. Weight this criterion at 10–20% of total points. This prevents an agent from earning full credit by producing correct output through means other than the specified tool.

---

## Lesson 229: Minimize SSH Roundtrips in Verifiers — Batch Queries and Validate Return Data

**The Problem**: Verifiers that call `exec_capture()` many times (once per DB query, once per file read) are fragile in QEMU environments. SSH key authentication can intermittently fail, forcing a paramiko password fallback that may corrupt the returned data — especially longer strings like UUIDs. Short strings (e.g., "Customer", "0") often survive intact, but 36-character UUIDs or multi-line outputs can arrive garbled. When this garbled data is used in equality comparisons, it produces false negatives (value doesn't match the expected baseline) which can falsely trigger `changes_made=True` and cause do-nothing tests to fail.

**Real example**: A verifier with ~20 individual `exec_capture()` calls (11 file reads + 9 SQL queries) experienced 4 SSH key auth failures during a single verification run. The account type queries returned correct short strings ("Prospect", "Customer"), but the contact `account_id` queries returned garbled UUIDs. The do-nothing test scored 31/100 instead of 0 because the garbled UUIDs didn't match the seeded baseline values, triggering partial-credit paths.

**The Fix — Batch queries and validate format**:

1. **Batch file reads into one SSH call**:
```python
# BAD: 11 separate SSH calls
apple_id = exec_capture("cat /tmp/apple_id.txt").strip()
meta_id = exec_capture("cat /tmp/meta_id.txt").strip()
# ... 9 more calls

# GOOD: 1 SSH call
names = ["apple", "meta", "exxon", "adobe", "salesforce"]
batch_cmd = "; ".join(f'echo "{n}:$(cat /tmp/{n}_id.txt 2>/dev/null)"' for n in names)
batch_out = exec_capture(batch_cmd)
ids = {}
for line in batch_out.splitlines():
    if ":" in line:
        key, val = line.split(":", 1)
        ids[key.strip()] = val.strip()
```

2. **Batch SQL queries into one call**:
```python
# BAD: 5 separate SQL queries via exec_capture
apple_type = db_query(f"SELECT account_type FROM accounts WHERE id='{apple_id}'")
meta_type = db_query(f"SELECT account_type FROM accounts WHERE id='{meta_id}'")
# ... 3 more calls

# GOOD: 1 SQL query returning all needed data
sql = f"SELECT id, account_type FROM accounts WHERE id IN ('{apple_id}','{meta_id}','{exxon_id}')"
rows = db_query(sql)  # parse tab-separated id\tvalue pairs
```

3. **Validate data format before comparisons**:
```python
import re

def _is_uuid(s):
    return bool(re.match(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        s, re.IGNORECASE))

# Only award "reassigned" partial credit if the returned value is a valid UUID
if account_id and account_id != expected_id and _is_uuid(account_id):
    score += partial_points  # genuinely changed to a real account
else:
    # Garbled SSH output or unchanged — don't trigger changes_made
    pass
```

**Rule of thumb**: If your verifier makes more than 3 `exec_capture()` calls, batch them. If any returned value is used in an equality comparison, validate its format first. This applies to any structured ID format (UUIDs, numeric IDs, dates, email addresses) — not just UUIDs.

**When to apply**: Any verifier that queries state via `exec_capture()` rather than parsing a pre-exported JSON file. Particularly critical for verifiers running against Docker containers inside QEMU VMs (double SSH hop: host→VM→container).

---

## Lesson 230: Avoid `set -e` in Setup Scripts Run via SSH Hooks

**The Problem**: `set -e` causes a bash script to exit immediately on any non-zero exit code. When setup scripts run via the framework's SSH hook mechanism, transient SSH authentication failures can cause commands to return non-zero even though they would succeed on retry. With `set -e`, the entire setup script silently aborts at the first such failure, leaving the environment in a partially-seeded state. The framework reports a short execution time (e.g., 1s instead of the expected 40s) but no error message.

**Real example**: A setup script that should take ~42 seconds to seed data into a Docker database completed in 1.14 seconds. The `set -e` at the top of the script caused it to exit at the first SSH command that failed due to key auth issues. All subsequent data seeding was skipped. The verifier then found empty/default values and returned a non-zero score on the do-nothing test because the seeded "corrupt" baseline never existed.

**Symptoms**:
- Setup hook completes suspiciously fast (seconds instead of tens of seconds)
- No error output visible
- Verification finds default/empty values instead of seeded test data
- Do-nothing test returns a non-zero score

**The Fix**:
```bash
#!/bin/bash
# Do NOT use set -e in setup scripts run via SSH hooks.
# Instead, check critical commands individually:

source /workspace/scripts/task_utils.sh

# Ensure PATH is complete (SSH sessions may have minimal PATH)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Wait for dependent services before proceeding
for i in $(seq 1 30); do
    if docker exec mydb-container mysqladmin ping -u user -ppass --silent 2>/dev/null; then
        echo "Database ready after ${i}s"
        break
    fi
    sleep 1
done

# Run seeding commands without set -e; check critical ones explicitly
RESULT=$(docker exec mydb-container mysql -u user -ppass mydb -N -e "SELECT COUNT(*) FROM mytable" 2>/dev/null)
if [ -z "$RESULT" ] || [ "$RESULT" = "0" ]; then
    echo "ERROR: Seeding failed — table is empty"
    # Optionally retry or exit with a clear error
fi
```

**Why not just fix the SSH issue?** The SSH key auth failures are transient and environment-dependent — they depend on VM boot timing, key propagation, and paramiko fallback behavior. You cannot reliably prevent them. The robust approach is to make your scripts tolerant of them.

**Rule**: Never use `set -e` in `setup_task.sh` or `export_result.sh` files. Instead, explicitly check the exit status of critical commands (database queries, file creation) and handle failures with retries or clear error messages. For service dependencies (databases, web servers), add explicit readiness wait loops at the top of the script.

---

### 184. CLI/Database Changes Do Not Reflect in the Browser Until Page Refresh

**The Problem**: In web application environments, `setup_task.sh` often injects state via command-line admin tools (WP-CLI for WordPress, drush for Drupal, occ for Nextcloud, manage.py for Django apps, moosh for Moodle, etc.) that write directly to the database. However, any browser session open at the time of injection still shows the **pre-injection state** — the browser has a cached DOM and will not reflect the new database values until the page is refreshed or the user navigates away and back.

**Symptoms**:
- Initial screenshot shows the **old** state, not the injected state
- Evidence review is confusing: "the screenshot says the site title is clean, but the DB query confirms it's spam"
- The agent must navigate/refresh to *discover* the injected state, which is actually desirable for difficulty

**Why this matters for task design**:
1. **Evidence collection**: Don't be alarmed if the initial screenshot doesn't show the injected changes. The database is the ground truth, not the screenshot.
2. **Difficulty benefit**: This is a *feature* for "very hard" tasks. The agent must actively explore the admin interface to discover problems — they aren't visible on the default dashboard page.
3. **Export scripts are unaffected**: `export_result.sh` queries the database directly (not the browser), so it always reflects the true state.

**Applies to**: Any web application environment where `setup_task.sh` modifies the database via CLI tools while a browser session is open. This includes WordPress, Drupal, Moodle, OpenEMR, Odoo, Nextcloud, and any app with both a CLI admin and a web GUI.

---

### 185. Setup Scripts That Download External Resources Need Fallback Paths

**The Problem**: Some tasks require installing plugins, extensions, or packages during `setup_task.sh` (e.g., WooCommerce for WordPress, calendar modules for Odoo, DICOM viewer for medical apps). These installations typically download from the internet. If the download fails (CDN outage, rate limiting, DNS issues), the entire task setup silently breaks — the plugin directory is empty, and the agent faces an impossible task.

**Symptoms**:
- Setup hook completes but the plugin/extension is not installed
- The agent's task becomes impossible (e.g., "configure WooCommerce" when WooCommerce isn't there)
- The error is intermittent — works on retry

**The Fix**: Always provide a fallback download mechanism:
```bash
# Primary: use the application's built-in package manager
wp plugin install woocommerce --allow-root 2>&1
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: Primary install failed, trying direct download..."
    cd /tmp
    curl -sL "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -o woocommerce.zip || \
    wget -q "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -O woocommerce.zip
    if [ -f /tmp/woocommerce.zip ]; then
        unzip -o /tmp/woocommerce.zip -d /var/www/html/wordpress/wp-content/plugins/
        chown -R www-data:www-data /var/www/html/wordpress/wp-content/plugins/woocommerce
    fi
fi

# ALWAYS verify the install succeeded before continuing
if [ ! -d "/var/www/html/wordpress/wp-content/plugins/woocommerce" ]; then
    echo "FATAL: Plugin installation failed — task cannot proceed"
fi
```

**Key principles**:
1. **Try the native package manager first** (wp plugin install, pip install, npm install, etc.)
2. **Fall back to direct download** if native install fails (curl/wget from official source)
3. **Always verify** the installation result before continuing — don't assume success
4. **Check `env.json` has `"net": true`** — network access must be enabled for download-dependent setups

**Applies to**: Any task where `setup_task.sh` installs a plugin, extension, theme, package, or external dependency. Common in CMS environments (WordPress, Drupal, Joomla), ERP systems (Odoo modules), and development environments (npm/pip packages).

---

### 231. Guard Every Parsed Shell Variable Before JSON Heredoc Interpolation

**The Problem**: Export scripts often use bash helper functions that return structured data (pipe-delimited, tab-delimited, or multi-field output) which is then parsed with `cut`, `awk`, or parameter expansion. When the queried entity does not exist — which is the **normal state during do-nothing tests** — these parsers return empty strings. If the empty string is interpolated as a bare (unquoted) JSON value in a heredoc, the resulting JSON is structurally invalid and the verifier crashes.

**Example failure pattern**:
```bash
# Helper function returns "term_id|is_child|parent_id" or "NOT_FOUND||"
RESULT=$(check_subcategory "Camping Gear" "Outdoor & Recreation")
IS_CHILD=$(echo "$RESULT" | cut -d'|' -f2)

# During do-nothing test, RESULT="NOT_FOUND||", so IS_CHILD=""
# This heredoc produces INVALID JSON:
cat <<EOF > /tmp/result.json
{
  "is_child_of_parent": $IS_CHILD
}
EOF
# Output: "is_child_of_parent":    ← missing value, invalid JSON
```

**Why this specifically hits do-nothing tests**: During normal operation, the queried entities exist and every field has a value. During do-nothing tests, **nothing** exists — every query returns empty/null. This means every parsed field is simultaneously empty, maximizing the chance of producing invalid JSON. The bug is invisible during normal testing and only surfaces during do-nothing validation.

**The fix**: Always default every parsed variable immediately after extraction, before it reaches the heredoc:
```bash
IS_CHILD=$(echo "$RESULT" | cut -d'|' -f2)
[ -z "$IS_CHILD" ] && IS_CHILD="false"

COUNT=$(echo "$RESULT" | cut -d'|' -f3)
[ -z "$COUNT" ] && COUNT="0"

NAME=$(echo "$RESULT" | cut -d'|' -f1)
[ -z "$NAME" ] && NAME="null"
```

**Broader principle**: In `export_result.sh`, every variable that appears as a bare value in the JSON heredoc (i.e., not inside quotes) must be guaranteed non-empty. The safe defaults by type are:
- Booleans: `false`
- Numbers: `0`
- Strings (inside quotes): `""` is fine, but bare `null` works too
- Arrays: `[]`

---

## Lesson 186: Document Transformation Tasks — Verify Formatting Attributes, Not Text Presence

**The Problem**: A common task pattern is "take raw/unformatted text and transform it into a professionally formatted document" (e.g., convert pasted email text into a structured report, reformat a draft contract, restructure clinical notes into a protocol). In these tasks, the starting document already contains **all** the content — just without formatting, heading styles, tables, or structure. Any verifier criterion that checks "does text X exist in the document?" will unconditionally pass in the do-nothing test, because the raw text already contains every keyword, phrase, and data point.

This is a specific, high-frequency application of Lesson 124's general principle ("trace every criterion against the starting file"), but the failure mode is subtle: unlike database tasks where "new record exists" clearly requires agent action, document transformation tasks tempt you to write criteria like "does the document mention revenue figures?" or "is the drug name present?" — which are always true because the raw text already says those things.

**Real example**:
```python
# BAD — always passes on unformatted starting document
content_complete = all(term in full_text for term in ["revenue", "expenses", "headcount"])
if content_complete:
    criteria_passed += 1  # Free point in do-nothing test

# BAD — "document control" check that passes because the report number is in the raw text
if report_number in full_text:
    criteria_passed += 1  # Free point — the number was already in the prose
```

**The Fix**: Every criterion must check for a **formatting or structural change** that the agent must actively apply, not for content that was already present:

```python
# GOOD — checks for formatting attribute (heading style), not text presence
heading_count = sum(1 for p in doc.paragraphs
                    if p.style and 'heading' in p.style.name.lower())
if heading_count >= 5:
    criteria_passed += 1  # Raw text has 0 headings → fails do-nothing

# GOOD — checks for table structure, not text presence
if count_tables(doc) >= 2:
    criteria_passed += 1  # Raw text has 0 tables → fails do-nothing

# GOOD — checks formatting attribute (bold/shading), not just text existence
if report_number in para.text:
    is_bold = any(run.bold for run in para.runs if run.text.strip())
    is_heading = 'heading' in para.style.name.lower()
    if is_bold or is_heading:
        criteria_passed += 1  # Raw text has the number but not bold/heading
```

**Safe criterion types for document transformation tasks**:
| Criterion type | Example | Why it's safe |
|---|---|---|
| Heading style applied | "5+ paragraphs have Heading 1/2/3 style" | Raw text uses Normal style only |
| Table created from prose | "2+ tables exist with 3+ rows" | Raw text has no tables |
| Font/size/spacing changed | "Body text is Times New Roman 12pt double-spaced" | Raw text uses default font |
| Formatting attribute present | "Table headers have bold + shading" | Raw text has no tables to format |
| Structural element added | "Signature block / revision history present at end" | Raw text lacks these sections |
| Position-aware check | "Title is centered+bold in first 5 paragraphs" | Raw text has no such formatting at top |

**Unsafe criterion types** (will inflate do-nothing scores):
| Criterion type | Example | Why it fails |
|---|---|---|
| Text presence | "Document contains 'Executive Summary'" | Already in raw text |
| Keyword completeness | "All 5 department names appear" | Already in raw text |
| Content preservation | "Key clinical values are present" | Legitimate but awards free points — make it a prerequisite gate (score=0 if failed) rather than a scored criterion |

**Content preservation as a prerequisite gate**: It is valid to check that the agent didn't delete important content. But make this a **prerequisite** (fail with score=0 if content is missing) rather than a **scored criterion** (award points if content is present). This way, content preservation never inflates the do-nothing score:

```python
# CORRECT: prerequisite gate, not scored criterion
preserved = sum(1 for phrase in key_phrases if phrase in full_text)
if preserved < threshold:
    return {"passed": False, "score": 0, "feedback": "Content corrupted"}
# Then proceed to check formatting criteria that start at 0
```

**Position-aware verification**: When checking document structure, verify that elements appear in the **correct position**, not just anywhere. A title should be in the first few paragraphs. An executive summary should be near the top. A signature block should be near the end. An agent that appends all formatting at the bottom of the document (without restructuring) should not receive credit:

```python
# GOOD — position-aware: title must be in first 10 paragraphs
for para in doc.paragraphs[:10]:
    if para.alignment == WD_ALIGN_PARAGRAPH.CENTER and any(r.bold for r in para.runs):
        title_found = True

# BAD — position-unaware: finds title text anywhere
if "quarterly board report" in full_text:
    title_found = True  # Matches raw email subject line buried in prose
```

**Self-check**: After writing a verifier for a document transformation task, ask for each criterion: "Would this criterion return non-zero points if I ran it on the raw, unformatted starting document?" If yes, either (a) change the criterion to check a formatting attribute, (b) convert it to a prerequisite gate, or (c) remove it entirely.

**Applies to**: Any environment where the task starts with an existing document and asks the agent to restructure, reformat, or enhance it — word processors (WPS Writer, LibreOffice Writer, Google Docs), spreadsheet formatters, code formatters, report generators, presentation tools, or any "raw input → formatted output" workflow.

**Applies to**: Any `export_result.sh` that constructs JSON via heredoc and uses parsed/split values from database queries, API responses, or helper functions. The risk scales with the number of parsed fields — the more `cut`/`awk` extractions, the more potential empty-value failure points.

---

### 232. Baseline Value Leak in Modification Tasks — Target Values That Already Match Starting State

**The Problem**: In "modify existing" tasks (Lesson 14), the agent must change values from their current state to specified target values. If any target value *coincidentally already equals* the baseline value, the do-nothing agent scores points for that criterion — the verifier sees the "correct" value and awards points, even though the agent did nothing.

This is distinct from:
- **Preservation criteria** (Anti-Pattern in `03_verification_patterns.md`): those check "was X not damaged?" — always true on do-nothing. This lesson is about **target criteria** that check "is X equal to the goal value?" where the goal happens to match the start.
- **Always-true criteria** (Lesson 24): those are unconditionally true (e.g., "app is running"). This lesson is about criteria that are *conditionally* true — they depend on specific values that happen to coincide.

**Example that broke**: A task requires modifying a ship simulation scenario: set visibility to 0.5, rain to 0.0, radar range to 48, and add a 3rd vessel. The verifier awards points for each correct value. But the baseline already has rain=0.0, radar range=48, and vessel count=2 (which earned partial credit). The do-nothing test scored 8/100 instead of 0.

```python
# BAD: do-nothing agent scores 3 free points because Rain is already 0.0
rain = float(env_data.get('Rain', -1))
if abs(rain - 0.0) < 0.01:
    score += 3  # "Rain correctly set to 0.0"

# BAD: do-nothing agent scores 3 free points because max_radar_range is already 48
max_range = int(config.get('max_radar_range', 0))
if max_range == 48:
    score += 3  # "Radar range correctly set"
```

**The Fix — Only Score Values That Must Change**:

1. **Identify which target values differ from baseline.** During task design, compare every target value against the starting state.

2. **Remove or gate criteria where target == baseline.** If the target value is already correct at baseline, do not award points for it — the agent did no work.

```python
# GOOD: Only score values that CHANGED from baseline
# Baseline: Vis=10.0, Weather=3.0, StartTime=14.0, Rain=0.0
# Target:   Vis=0.5,  Weather=1.0, StartTime=8.0,  Rain=0.0
# Rain is unchanged — do NOT score it

vis = float(env_data.get('VisibilityRange', -1))
if abs(vis - 0.5) < 0.01:
    score += 5  # Vis changed from 10.0 to 0.5 — real work

# Rain intentionally omitted — baseline already matches target
```

3. **Redistribute the removed points** to criteria that require actual changes, keeping the total at 100.

4. **Alternative approach — change the starting state.** Instead of removing the criterion, change the baseline so it no longer matches the target:

```bash
# setup_task.sh: ensure baseline differs from target for ALL criteria
sed -i 's/^Rain=.*/Rain=5.0/' "$SCENARIO_DIR/environment.ini"  # Now agent must set to 0.0
```

**Detection method**: After writing the verifier, make a table:

| Criterion | Baseline Value | Target Value | Leaked? |
|-----------|---------------|--------------|---------|
| Visibility | 10.0 | 0.5 | No |
| Rain | 0.0 | 0.0 | **YES** |
| Radar range | 48 | 48 | **YES** |
| Vessel count | 2 | 3 | No (but partial credit for 2 leaks) |

Any row where Baseline == Target is a leak. Any row where partial credit includes the baseline value is also a leak.

**Applies to**: Any "modify existing" task in any environment — editing patient records (some fields already correct), updating configurations (some settings already at target), modifying documents (some formatting already applied), adjusting simulation parameters (some values already matching). The risk increases with the number of criteria: more criteria means more chances for a coincidental baseline-target match.

---

### Enterprise Applications With Dual Entity Types: Data Classes vs. Process/Workflow Classes

**The Problem**: Many enterprise applications (CMMS, ITSM, CRM, ERP, BPM) expose two fundamentally different kinds of entities through their REST API:

1. **Data classes** (also called "card classes", "tables", "objects"): Static records like buildings, assets, contacts, products. CRUD via endpoints like `POST /classes/{className}/cards`.

2. **Process/workflow classes**: Entities with a lifecycle managed by a workflow engine — tickets, work orders, approvals, change requests. CRUD via completely different endpoints like `POST /processes/{processName}/instances`.

Both types may appear side-by-side in the UI, share similar field structures (Code, Description, Priority, Building reference), and even show up in the same navigation menus. But they use **different API paths**, and a `POST /classes/{name}/cards` call will return 404 or 500 for a process class, with no helpful error message explaining why.

**Why this matters for task creation**: Setup scripts that create seed data (e.g., pre-existing tickets for the agent to triage) and export scripts that read current state will silently fail if they assume all entities are data classes. The setup appears to complete (no crash), but no records are actually created, and the task starts in a broken state with none of the expected seed data.

**How to detect**: During environment onboarding (Phase 1 of the onboarding protocol), enumerate both entity types:

```python
# List regular data classes
classes = api("GET", "classes?limit=500", token)

# List process/workflow classes — SEPARATE endpoint
processes = api("GET", "processes?limit=500", token)

# Check if your target entity is in classes or processes
for c in classes["data"]:
    if "maintenance" in c["description"].lower():
        print(f"CARD CLASS: {c['_id']} — {c['description']}")

for p in processes["data"]:
    if "maintenance" in p["description"].lower():
        print(f"PROCESS CLASS: {p['_id']} — {p['description']}")
```

**The Fix — build shared helpers with auto-detection from the start**:

```python
def find_entity(pattern, token):
    """Find entity by name pattern. Returns (type, name) where type is 'card' or 'process'."""
    # Check processes first (workflow entities are often the ones you need for tasks)
    for p in list_processes(token):
        if re.search(pattern, p.get("_id", ""), re.IGNORECASE):
            return "process", p["_id"]
    # Fall back to card classes
    for c in list_classes(token):
        if re.search(pattern, c.get("_id", ""), re.IGNORECASE):
            return "card", c["_id"]
    return None, None

def create_record(entity_type, entity_name, attrs, token):
    """Create a record using the correct API path for the entity type."""
    if entity_type == "process":
        return api("POST", f"processes/{entity_name}/instances", token, attrs)
    return api("POST", f"classes/{entity_name}/cards", token, attrs)

def get_records(entity_type, entity_name, token, limit=100):
    if entity_type == "process":
        return api("GET", f"processes/{entity_name}/instances?limit={limit}", token)
    return api("GET", f"classes/{entity_name}/cards?limit={limit}", token)
```

Then in setup/export scripts, store the detected type in the baseline so the export script uses the same API path:

```python
# setup_task.sh
entity_type, entity_name = find_entity(r"CorrectiveMaint", token)
baseline["entity_type"] = entity_type
baseline["entity_name"] = entity_name

# export_result.sh
entity_type = baseline["entity_type"]
entity_name = baseline["entity_name"]
records = get_records(entity_type, entity_name, token)
```

**Common enterprise software where this applies**:

| Software | Data entities | Workflow entities | API path difference |
|----------|--------------|-------------------|---------------------|
| CMDBuild / OpenMaint | Classes (Building, CI, Floor) | Processes (CorrectiveMaint, RequestForChange) | `/classes/` vs `/processes/` |
| ServiceNow | Tables (cmdb_ci, location) | Workflow contexts (incident, change_request) | Both via `/table/` but workflow tables have state machines |
| Jira | Projects, Components, Custom Fields | Issues (with workflow transitions) | `/project/` vs `/issue/` with `/transitions` |
| Salesforce | Standard/Custom Objects | Approval Processes, Flows | `/sobjects/` vs `/process/approvals/` |
| Odoo | Models (res.partner, product) | Workflows (sale.order stages) | Same endpoint but different state semantics |

**Key signals that an entity is a process class**:
- URL contains "processes" or "instances" (e.g., `/#processes/CorrectiveMaint/instances`)
- The entity has a "FlowStatus" or "_card_status" field
- Records have lifecycle state transitions (Open → In Progress → Closed)
- The UI shows the entity under a "Management" or "Workflow" menu rather than a "Data" menu
- Creating a record through the UI triggers a wizard with activity/step selection

**Rule**: During environment onboarding, always enumerate BOTH `classes` and `processes` (or their equivalents) via the API. Before writing any setup script that creates or queries records, confirm which API path the target entity uses. Build your shared API helpers with dual-mode support from the start — retrofitting is expensive.

---

### 187. Document-Editor Verifiers Must Check Formula Strings and Structural Markers, Not Computed Values

**The Problem**: When verifying tasks in spreadsheet, word processor, or presentation editors, the obvious approach is to open the output file and check computed values — "is cell B5 equal to $96,500,000?" But document parsing libraries (openpyxl, python-docx, python-pptx, odfpy) read formulas as raw strings (`=SUM(B2:B4)`) rather than evaluated results. The computed value is only available if you open the file in the actual application (Excel/WPS/LibreOffice), which you cannot do from the verifier running outside the VM.

**What happens**:
```python
# verifier.py reads the cell — expecting a number, gets a string
from openpyxl import load_workbook
wb = load_workbook('output.xlsx', data_only=False)  # default
cell = wb['Consolidated']['B2']
print(cell.value)  # "=Alpha_Inc!B2+Beta_Corp!B2+Gamma_LLC!B2" — NOT a number

# Even with data_only=True, openpyxl returns None for formulas
# that have never been evaluated by an Excel engine
wb2 = load_workbook('output.xlsx', data_only=True)
print(wb2['Consolidated']['B2'].value)  # None
```

**The Fix**: Design verifiers around three categories of evidence that document parsers CAN reliably detect:

1. **Formula strings** — Check that specific function names appear in cell formulas. This proves the agent used the correct approach, not just hardcoded values:
```python
# Check for presence of financial functions
has_pmt = any(
    'PMT' in str(cell.value).upper()
    for row in sheet.iter_rows() for cell in row
    if cell.value and isinstance(cell.value, str) and cell.value.startswith('=')
)
```

2. **Cross-sheet references** — Check that formulas in new sheets reference existing data sheets. This is a strong anti-gaming signal — an agent that hardcodes values won't have these references:
```python
def check_formula_references(sheet, target_sheet_names):
    refs_found = set()
    for row in sheet.iter_rows():
        for cell in row:
            if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                for name in target_sheet_names:
                    if name in cell.value:
                        refs_found.add(name)
    return refs_found

# Consolidated sheet should reference Alpha_Inc, Beta_Corp, etc.
refs = check_formula_references(wb['Consolidated'], ['Alpha_Inc', 'Beta_Corp', 'Gamma_LLC'])
has_proper_consolidation = len(refs) >= 2  # At least 2 of 3 source sheets referenced
```

3. **Structural markers** — Check for named elements the document parser can detect without formula evaluation:
   - **Sheet/page existence**: `'Consolidated' in wb.sheetnames`
   - **Conditional formatting rules**: `sheet.conditional_formatting` (openpyxl exposes these)
   - **Chart objects**: `hasattr(sheet, '_charts') and len(sheet._charts) > 0`
   - **Number formats**: `cell.number_format` (e.g., `'0%'` for percentage, `'$#,##0'` for currency)
   - **Data validation rules**: `sheet.data_validations`
   - **Column/row labels**: Text content in header rows (which are literal strings, not formulas)
   - **Named ranges**: `wb.defined_names`
   - **Cell font/fill formatting**: `cell.font.bold`, `cell.fill.fgColor`

**Scoring pattern**: Award points for each independent structural marker present, with bonus points for formula sophistication:

```python
# Tier 1: Sheet exists (basic)
if 'Ratios' in [s for s in wb.sheetnames]:
    score += 5

# Tier 2: Sheet has relevant content labels (medium)
ratio_keywords_found = count_keyword_matches(ratios_sheet, ['current ratio', 'gross margin', 'roe'])
if ratio_keywords_found >= 5:
    score += 8

# Tier 3: Sheet has cross-sheet formula references (strong evidence of real work)
if check_formula_references(ratios_sheet, ['Consolidated']):
    score += 7
```

**When to use value checks anyway**: If a formula result is a *literal value* (not a formula), it CAN be read. This happens when:
- The agent typed a number directly (not a formula)
- The agent computed it externally and pasted it
- The file was saved by an application that cached computed values (some do, some don't)

Use value checks as optional bonus scoring — award points if the value is present AND correct, but don't require it for the main score:
```python
# Optional: if we CAN read the value, check it
resolved = _resolve_value(cell.value)
if resolved is not None and abs(resolved - expected) / expected < 0.08:
    score += bonus_points
```

**Applies to**: Any environment where the agent produces document files that will be parsed by Python libraries outside the application:
- Spreadsheets: openpyxl (.xlsx), xlrd (.xls), odfpy (.ods)
- Word processors: python-docx (.docx), odfpy (.odt)
- Presentations: python-pptx (.pptx)
- Diagram editors: xml.etree (.drawio), zipfile + xml (.vsdx)

**Does NOT apply to**: Tasks where the output is plain text (CSV, JSON, code files) — those can be fully evaluated by the verifier since there are no formulas.

---

### 188. REST API as a Verification Seam for Self-Hosted Web Applications

**The Observation**: Many self-hosted web applications (Snipe-IT, GitLab, Nextcloud, Grafana, Mattermost, WikiJS, Portainer, etc.) ship with HTTP REST APIs that expose full CRUD operations over their data. These APIs provide a distinct verification seam that is often superior to direct database queries for `export_result.sh`.

**Why REST API verification differs from direct DB queries**:

1. **API responses are natively JSON** — no need to parse tab-separated MySQL output or handle column alignment issues (Lesson 3). The export script can pipe `curl` output directly through `jq` or Python.
2. **API queries return computed/joined data** — a single API call like `GET /api/v1/hardware/123` returns the asset with its status label name, location name, assigned user name, and category name already resolved. The equivalent DB query would require 4+ JOINs across normalized tables.
3. **API authentication must be provisioned at setup time** — store the API token in a known location (e.g., `/home/ga/app/api_token.txt`) during environment setup, then read it in both `setup_task.sh` and `export_result.sh`.
4. **The API reflects the same layer the agent interacts with** — if the agent creates a record through the GUI, the API sees it. If a DB trigger or application logic transforms the data, the API returns the transformed version. Direct DB queries might see raw data before application-level processing.

**The pattern**:

In environment setup (e.g., `setup_app.sh`):
```bash
# Provision API token and store for later use
API_TOKEN=$(curl -s ... | jq -r '.token')
echo "$API_TOKEN" > /home/ga/app/api_token.txt
```

In shared `task_utils.sh`:
```bash
app_api() {
    local METHOD="$1" ENDPOINT="$2"
    shift 2
    local TOKEN=$(cat /home/ga/app/api_token.txt 2>/dev/null)
    curl -s -X "$METHOD" "http://localhost:PORT/api/v1${ENDPOINT}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$@"
}
```

In `export_result.sh`:
```bash
# API responses are already JSON — extract fields with jq
ASSET_JSON=$(app_api GET "/hardware/byTag/ASSET-L007")
STATUS=$(echo "$ASSET_JSON" | jq -r '.status_label.name // "unknown"')
LOCATION=$(echo "$ASSET_JSON" | jq -r '.location.name // "unknown"')
ASSIGNED=$(echo "$ASSET_JSON" | jq -r '.assigned_to.username // "none"')
```

**When to prefer API over direct DB**:
- The app has a documented, comprehensive REST API
- The DB schema is undocumented or uses opaque foreign keys
- The app applies business logic between the DB and the user (computed fields, access control)
- You need relational data (an entity plus its associations) in a single query

**When to prefer direct DB over API**:
- The API does not expose the specific field you need to verify
- The API requires pagination for bulk queries and you need exact counts
- The API rate-limits and you need many queries in the export script
- You need to verify raw data that the API intentionally hides (soft-deleted records, audit logs)

**Dual-channel verification**: For high-stakes criteria, query BOTH the API and the DB and cross-check. If an agent somehow manipulated the DB directly without going through the application, the API response may differ from the DB state — catching this is a strong anti-gaming signal.

**Applies to**: Any self-hosted web application with a REST or GraphQL API — IT asset management (Snipe-IT, GLPI), project management (GitLab, Gitea), CMS (WordPress, Ghost), monitoring (Grafana, Zabbix), identity (Authentik, Keycloak), file sharing (Nextcloud, Seafile).

---

### 189. Verify External Data Content After Download, Not Just Existence

**The Problem**: When tasks use real data from external sources (APIs, public databases, file repositories), task creators often assume the downloaded content matches their expectation without inspecting it. External data sources have several failure modes that produce silently wrong task data:

- **Accession/ID mismatch**: A database accession number attributed to one entity may actually return a different entity (e.g., NCBI accession NR_025040.1 attributed to *Desulfovibrio vulgaris* actually returns *Methylosarcina quisquiliarum*).
- **Truncated records**: A protein sequence assumed to be 350+ residues may return only 15 residues (a fragment record, not the full protein).
- **Taxonomic reclassification**: Searching for a species by its historical name may return zero results because the organism has been reclassified (e.g., *Desulfovibrio gigas* was reclassified to *Desulfovibrio giganteus*).
- **Record versioning**: GenBank records have versions (e.g., MH167239.1 vs MH167239.2); the latest version may have different content than expected.

**The Fix**: After downloading any external data, programmatically verify the content matches expectations before incorporating it into the task:

```bash
# BAD: download and assume it's correct
curl -s "https://api.example.com/record/ABC123" > /path/to/asset.fasta

# GOOD: download, then verify content
curl -s "https://api.example.com/record/ABC123" > /path/to/asset.fasta

# Check that the file is non-empty and contains expected content
python3 -c "
with open('/path/to/asset.fasta') as f:
    content = f.read()
assert len(content) > 100, f'File too short: {len(content)} bytes'
assert 'ExpectedOrganism' in content, 'Wrong organism in downloaded data'
print(f'Verified: {len(content)} bytes, correct organism')
"
```

**Derive ground truth from the actual downloaded data**, not from what you assumed the data contains. If a setup script hardcodes ground truth values (sequence counts, repeat positions, expected coordinates) that were chosen based on assumptions rather than inspection of the actual file, the verifier will silently accept wrong answers or reject correct ones.

**Applies to**: Any task using data from external APIs (NCBI, UniProt, PDB, government data portals, open data repositories), downloaded sample files, or any data not directly generated by the task creator.

---

### 190. Domain-Equivalent Representations in Verification

**The Problem**: Lesson 13 covers synonym sets for column/field names — accepting multiple labels for the same concept (e.g., "red", "ch1", "rhodamine" for a red fluorescence channel). A distinct but related issue arises in scientific and technical domains where the **same ground truth value has multiple valid representations** that are not synonyms but domain equivalences:

- **DNA strands**: A tandem repeat motif can be reported as AATG (one strand) or TCAT/CATT (complementary strand). Both are correct representations of the same repeat.
- **Coordinate systems**: The same location can be expressed in decimal degrees (40.7128, -74.0060) or DMS (40°42'46"N, 74°0'22"W).
- **Chemical nomenclature**: The same compound can be identified by common name, IUPAC name, SMILES string, InChI key, or CAS number.
- **Units**: A measurement of 0.28 (fraction) and 28 (percent) represent the same value. Similarly, 9.81 m/s² and 32.2 ft/s² are equivalent.
- **Sequence reading frames**: A 4-mer repeat can be reported starting at any position in the motif: TATC, ATCT, TCTA, or CTAT are all valid representations of the same tandem repeat.

**The Fix**: Export scripts and verifiers must accept all domain-equivalent representations, not just the one used in ground truth:

```bash
# In export_result.sh: detect both strand representations
echo "$REPORT_CONTENT" | grep -qi "AATG\|aatg" && HAS_AATG=true
echo "$REPORT_CONTENT" | grep -qi "TCAT\|tcat" && HAS_TCAT=true
```

```python
# In verifier.py: accept either representation
if result.get("report_has_aatg", False) or result.get("report_has_tcat", False):
    motif_score += 5  # Agent correctly identified the repeat, regardless of strand
```

**This differs from Lesson 13 (synonym sets)** because synonym sets handle naming variation for the same concept, while domain equivalences handle fundamentally different but mathematically/scientifically equivalent representations. A verifier that accepts "red" and "ch1" as synonyms is handling label flexibility. A verifier that accepts both AATG and TCAT is handling domain knowledge about DNA strand complementarity.

**Applies to**: Any domain where data has inherent symmetry or multiple valid encodings — bioinformatics (strand complementarity, reading frames, codon degeneracy), chemistry (nomenclature systems), geospatial (coordinate reference systems), physics (unit systems), and signal processing (time/frequency domain representations).

---

### 191. Prefer Asset Files Over Inline Data in Setup Scripts

**The Problem**: When tasks require domain-specific data files (FASTA sequences, GenBank records, CSV datasets, GeoJSON files, etc.), task creators often embed the data directly in `setup_task.sh` using heredocs. This creates several problems:

- **Unreadable scripts**: A 200-line heredoc of DNA sequences in the middle of a bash script is impossible to review or audit for correctness.
- **Unmaintainable**: If the data needs to be updated (e.g., a sequence was wrong), you must edit a bash script rather than replacing a data file.
- **Non-reusable**: Multiple tasks that share reference data must each embed their own copy, leading to duplication and inconsistency.
- **Fragile formatting**: Heredocs can silently corrupt data through whitespace issues, variable interpolation (if `<<EOF` is used instead of `<<'EOF'`), or shell metacharacter expansion.

**The Fix**: Store real data files in a shared assets directory and copy them into the task workspace during setup:

```bash
# BAD: 150 lines of inline FASTA data in a bash script
cat > /home/ga/data/sequences.fasta << 'FASTA'
>Seq1 Long header
ATCGATCGATCG...
(150 more lines)
FASTA

# GOOD: copy from bundled assets directory
cp /workspace/assets/sequences.fasta /home/ga/data/sequences.fasta
```

**Asset directory conventions**:
- Store shared data files in `benchmarks/cua_world/environments/<env_name>/assets/` — this directory is typically mounted read-only at `/workspace/assets/` inside the VM.
- Name files descriptively: `reference_wheat_pathogens_ITS.fasta`, not `data1.fasta`.
- Document the data source (accession numbers, URLs, download dates) in comments in `setup_task.sh` where the `cp` command appears.
- Multiple tasks can reference the same asset file, ensuring consistency.

**When inline data is acceptable**:
- Very small data (< 10 lines) that is task-specific and not shared.
- Evidence/test samples that are inherently part of the task scenario (e.g., a "crime scene DNA sample" with specific allele counts).
- Error-injected variants of real data, where the base is copied from assets and errors are injected programmatically (per the error-injection scaffolding rule in `01_core_principles.md`).

**Applies to**: Any environment where tasks require input data files — bioinformatics (FASTA, GenBank, PDB), geospatial (GeoJSON, shapefiles), scientific computing (CSV datasets, HDF5), medical imaging (DICOM samples), and any domain with structured data files.

---

### 192. Numeric Range Scan Contamination from Pre-Filled Reference Values

**The Problem**: Lesson 16 covers keyword contamination in starter files. Numeric range scans have the exact same problem but are harder to spot. When a starter file contains a pre-filled reference value (a budget total, an allocation amount, a benchmark figure) and your verifier scans a region for "any number in [X, Y]," the pre-filled value matches — giving free points in the do-nothing test.

**Example that broke**:
```python
# Starter spreadsheet has a reference cell: "Title I Allocation: $582,174"
# Verifier scans rows 2-20, columns 6-16 for any value in [500000, 650000]
cands = _scan_numeric(ws, range(2, 20), range(6, 16), 500000, 650000)
# Finds $582,174 in the pre-filled reference cell → awards 20 points for free
```

**The Fix**: Restrict numeric scans to the specific region where agent output is expected, using structural anchors (row labels, section headers, or known output coordinates):

```python
# GOOD: Only check the row whose column A label is exactly "TOTAL"
for row in range(2, 20):
    label = ws.cell(row, 1).value
    if label and isinstance(label, str) and label.strip().upper() == "TOTAL":
        cands = _scan_numeric(ws, [row], range(6, 16), 500000, 650000)
        break
```

**Why this is distinct from keyword contamination**: Keywords can be neutralized by rephrasing labels (Lesson 16). Numeric reference values often *cannot* be removed — they are part of the task context the agent needs (e.g., the allocation amount the agent must distribute). The fix must be in the verifier's scan scope, not in the starter file.

**Applies to**: Any task with a starter file (spreadsheet, form, template, config) that contains both reference data and agent-output areas, where the verifier uses range-based numeric scans. Spreadsheet environments are the most common case, but this also affects structured document templates and forms.

---

### 193. Short Categorical Strings Require Exact-Match, Not Substring Search

**The Problem**: When verifiers search for short categorical values like "PASS", "FAIL", "SIGNAL", "YES", "NO", "HIGH", "LOW", or "TRUE", instruction text or labels in the starter file often contain those same words as substrings. A substring search matches the instruction text and awards free points.

**Example that broke**:
```python
# Starter spreadsheet has instruction text in a cell:
#   "Supplement Check: PASS if Title I Per Pupil > 0 and..."
# Verifier searched for cells containing "PASS":
if "PASS" in str(val).upper():
    supplement_count += 1
# Finds "PASS" in the instruction text → awards points for free
```

**The Fix**: Match the exact trimmed value of the cell/field, not substrings:

```python
# GOOD: Only match cells whose entire value is exactly "PASS" or "FAIL"
val = ws.cell(r, c).value
if val and isinstance(val, str):
    v = val.strip().upper()
    if v in ("PASS", "FAIL"):  # exact match, not substring
        supplement_count += 1
```

**When substring search IS appropriate**: When the expected output is a long, distinctive string that wouldn't appear in instructions (e.g., a full sentence, a UUID, a specific file path). Short categorical values (1-6 characters) should always use exact match.

**Applies to**: Any verifier that checks for short status/flag/category values in files where the starter content includes instructions, labels, or descriptions. Common in spreadsheet tasks (PASS/FAIL, COMPARABLE/NON-COMPARABLE, SIGNAL/NO-SIGNAL), form-filling tasks (YES/NO), and any template-based task.

---

### 194. Restrict Verifier Scans to Agent-Output Regions, Not the Entire File

**The Problem**: Lessons 192 and 193 are both symptoms of a deeper issue: verifier scans that cover the entire file (or entire sheet) instead of just the region where agent output is expected. Starter files typically have three distinct zones: (1) input data, (2) labels/instructions, and (3) blank areas where the agent must write results. When scans cover all three zones, both numeric values and keyword matches from zones 1 and 2 contaminate the results.

**The Fix**: Define explicit "results regions" in your verifier and restrict all scans to those regions:

```python
# Define where agent output is expected
N_DATA_ROWS = 11  # rows 2-12 are pre-filled data
RESULTS_START_ROW = N_DATA_ROWS + 2  # row 14+ is where agent writes results
RESULTS_COL_START = 2  # column B+

# Scan ONLY the results region
for r in range(RESULTS_START_ROW, RESULTS_START_ROW + 15):
    for c in range(RESULTS_COL_START, 10):
        val = ws.cell(r, c).value
        # ... check val ...
```

**How to determine the results region**: Look at the starter file and identify:
1. Which rows/columns contain pre-filled data (input zone)
2. Which rows/columns contain labels or instructions (label zone)
3. Which rows/columns are blank and intended for agent output (results zone)

Document these regions as constants at the top of the verifier, derived from the actual starter file structure.

**Applies to**: Any task where the starter file has both pre-filled content and designated output areas — spreadsheets with data + summary sections, forms with pre-filled fields + blank fields, templates with examples + blank slots, documents with instructions + work areas. This is the general principle underlying Lessons 16, 192, and 193.

---

### 195. Hybrid Data Strategy: Real Records + Published Reference Parameters

**The Problem**: Many professional tasks involve both (a) a dataset of individual records and (b) reference parameters used in calculations on that dataset (wage tables, tax rates, cap rates, benchmark values, union rate schedules). The "Real Data — No Exceptions" rule (Principle 2 in `01_core_principles.md`) applies to both, but they come from fundamentally different sources.

**The Pattern**: Use real individual-level data from APIs or databases for the main dataset, combined with exact published aggregate statistics as computation parameters. Both must be cited.

**Example**:
```python
# Main dataset: real school-level data from NCES CCD API
# Downloaded via: https://educationdata.urban.org/api/v1/schools/ccd/...
schools_df = download_from_nces_api(leaid="5100420", year=2022)

# Reference parameters: published aggregate statistics (exact values, no randomness)
STATE_AVG_PPE = 14603      # NCES Digest 2023, Table 236.65, Virginia
BENEFITS_RATE = 0.353       # VRS employer contribution rate FY2024
TITLE1_ALLOCATION = 582174  # Virginia DOE Title I Allocations FY2023
```

**Why this matters**: The alternative — trying to download individual-level data for *everything* — often fails because detailed reference tables (wage schedules, rate cards, benchmark surveys) are published only as PDFs or aggregate reports, not as API-queryable datasets. The hybrid approach lets you use the best available real source for each component.

**Documentation requirement**: In `task.json` metadata and README.md, cite both sources separately:
```json
"data_source": "NCES CCD 2022-23 Botetourt County VA (LEAID 5100420); BLS OEWS May 2023 Virginia salaries; NCES Digest 2023 Table 236.65 Virginia PPE $14,603; Virginia DOE Title I Allocations FY2023 ($582,174)"
```

**What is NOT acceptable**: Downloading real records and then generating synthetic reference parameters (random rates, estimated benchmarks, interpolated values). If you cannot find the exact published value, find a different parameter or use a different task design.

**Applies to**: Any computation-heavy task (financial modeling, compliance analysis, scientific calculations, engineering design) where the agent must apply domain-standard rates, benchmarks, or coefficients to a real dataset.

---

### 196. Compute Ground Truth Ranges from the Actual Data After Generation

**The Problem**: After downloading or assembling real data, task creators sometimes set expected value ranges based on intuition or rough mental math ("total should be around $1-2 million"). When the verifier uses these ranges, they may be too loose (giving credit for wrong answers) or too tight (rejecting correct answers).

**The Fix**: After generating the data file, programmatically compute the ground truth values from the actual data and use those to set verifier ranges:

```python
# After generating the xlsx, compute actual values
import openpyxl
wb = openpyxl.load_workbook("data/output.xlsx")
ws = wb["Sheet1"]

# Compute the actual total from the data
actual_total = sum(ws.cell(r, 5).value for r in range(2, ws.max_row + 1) if ws.cell(r, 5).value)
print(f"Actual total: {actual_total}")  # e.g., 1,782,000

# Set verifier range as ±15% of actual (accounts for agent rounding, formula variations)
lo = int(actual_total * 0.85)
hi = int(actual_total * 1.15)
print(f"Verifier range: [{lo}, {hi}]")  # e.g., [1,514,700, 2,049,300]
```

**Why ±15%**: Agent-computed values may differ from your exact computation due to: different formula implementations, rounding at intermediate steps, different aggregation order (floating-point accumulation), or legitimate alternative methodologies. A ±15% window catches clearly wrong answers while accepting any reasonable computation.

**When to use tighter ranges**: When there is exactly one correct formula and rounding cannot vary (e.g., a simple SUM or COUNT). In that case, ±5% or even exact match is appropriate.

**Applies to**: Any task where the verifier checks a computed numeric result against an expected range — financial totals, statistical summaries, engineering calculations, inventory costs, etc.

---

### 197. Defensive Parsing of Noisy Framework Runner Output in Export Scripts

**The Problem**: When the scripting seam for an environment is an application framework's runner command (`rails runner`, `django-admin shell`, `flask shell`, `wp-cli eval`, `drush eval`, etc.) executed via `docker exec`, the stdout is contaminated with framework boot messages that appear *before* the actual output. These messages include logger initialization lines, database pool resizing notifications, job queue announcements, deprecation warnings, and gem/package loading notices.

A naive `json.loads(stdout)` or `echo "$RESULT" | jq .` fails because the full stdout string is not valid JSON — it starts with log lines, not a `{`.

**Example of contaminated output**:
```
I, [2026-03-07T01:35:12.070069 #802]  INFO -- : Increasing database pool size to 17 (from 6) for 17 background jobs
I, [2026-03-07T01:35:12.071234 #802]  INFO -- : GoodJob 4.12.0 registered for execution
{"id":42,"name":"Sprint 1","status":"active"}
```

Only the last line is the actual output. But `json.loads()` on the full string fails, and splitting on newlines and taking `[-1]` is fragile because some frameworks also emit trailing log lines *after* the output.

**The Fix — reverse line scanning**:

```bash
# In export_result.sh (Python helper function)
def safe_json(s):
    """Extract JSON from framework runner output that may contain log lines."""
    for line in reversed((s or "").strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except:
                continue
    return {}

def safe_int(s, default=0):
    """Extract last pure-integer line from framework runner output."""
    import re
    for line in reversed((s or "").strip().splitlines()):
        line = line.strip()
        if re.match(r'^\d+$', line):
            return int(line)
    return default
```

**Why reverse scanning**: The actual output is typically the last meaningful line. Framework boot messages appear first (before the script runs). By scanning from the bottom, you find the real output immediately, skipping all boot noise regardless of how many log lines the framework emits.

**Alternative approach — unique output prefix**:

```ruby
# In the Rails runner script, prefix output with a unique marker
puts "__GA_VERIFY__" + result.to_json
```

```bash
# In export_result.sh, extract only the marked line
RESULT=$(echo "$RAW_OUTPUT" | grep '__GA_VERIFY__' | sed 's/__GA_VERIFY__//')
```

This is more robust than reverse scanning when the framework emits log lines *after* the output, but requires modifying every Rails runner invocation.

**Frameworks known to produce noisy stdout**:

| Framework | Noise source | Typical messages |
|-----------|-------------|-----------------|
| Rails (`bin/rails runner`) | ActiveSupport, GoodJob, ActiveRecord | `INFO -- : Increasing database pool size`, `GoodJob registered` |
| Django (`manage.py shell -c`) | Settings, migrations check | `Performing system checks...`, `System check identified no issues` |
| Laravel (`php artisan tinker --execute`) | Service providers | `Loading cached services...` |
| WordPress (`wp eval`) | Plugin initialization | `WP-CLI registered commands`, deprecation notices |
| Node.js (`node -e` with ORMs) | Sequelize, TypeORM | `Executing (default): SELECT...`, connection pool logs |

**The worst-case scenario**: During do-nothing tests, the export script runs but the queried entity doesn't exist. The framework runner returns an empty string or `null` for the actual output, leaving *only* log lines. If the parser doesn't handle this gracefully (returning `{}` or `0` as defaults), the verifier crashes instead of scoring 0. The `safe_json` and `safe_int` functions above handle this by returning safe defaults when no valid output line is found.

**Detection during onboarding**: In Phase 2 of the onboarding protocol (`12_new_environment_onboarding.md`), when you first run a framework command via `docker exec`, **always inspect the raw stdout** before writing any parsing code. Run a trivial command like `docker exec <container> bash -lc "cd /app && bin/rails runner 'puts({test: 1}.to_json)'"` and look at the full output, not just the last line. If you see any lines before the JSON, you need defensive parsing.

**Applies to**: Any environment where the scripting seam is an application framework runner executed inside a Docker container or VM — Rails (OpenProject, GitLab, Discourse, Redmine), Django (Sentry, Netbox, Taiga), Laravel (Monica, Firefly III), WordPress, Node.js ORMs (Strapi, Ghost), and any app with a built-in script console.

---

### 198. VM Snapshot File State Is Frozen at Checkpoint Time

**The Problem**: When using QEMU's `savevm`/`loadvm` mechanism (the standard for this framework), the VM's filesystem state is frozen at the moment the checkpoint was created. Any files modified on the host after the checkpoint was saved — including `setup_task.sh`, `export_result.sh`, and asset files — are **not reflected inside the running VM** after `loadvm`. The VM boots from the snapshot's baked-in filesystem, not from the host's current files.

This means that during iterative development of task scripts, editing a file on the host and then running it inside the VM will execute the *old* version from the snapshot, not your edited version. The bug is silent — the script runs without error, but produces wrong results because it's running stale code.

**How it manifests**:
1. You edit `export_result.sh` on the host to fix a parsing bug.
2. You SSH into the VM and run `/workspace/tasks/my_task/export_result.sh`.
3. The script runs the **old, buggy version** from the snapshot — your fix is not applied.
4. You see the same wrong output and conclude your fix didn't work.
5. Hours of debugging follow, chasing a phantom bug in code that was already fixed.

**The Fix**: After editing any file on the host, explicitly copy it into the running VM before testing:

```bash
# Copy a single updated file into the VM
sshpass -p 'password123' scp -P <SSH_PORT> -o StrictHostKeyChecking=no \
    /path/on/host/export_result.sh \
    ga@127.0.0.1:/workspace/tasks/my_task/export_result.sh

# Copy an entire task directory
sshpass -p 'password123' scp -r -P <SSH_PORT> -o StrictHostKeyChecking=no \
    /path/on/host/tasks/my_task/ \
    ga@127.0.0.1:/workspace/tasks/my_task/
```

**When this does NOT apply**: If you create a fresh checkpoint after editing files, the new checkpoint includes your edits. The problem only occurs when editing files *after* the checkpoint was already created and booting from that older checkpoint.

**Best practice during iterative development**:
1. Edit files on the host (where your editor and version control are).
2. SCP the changed files into the running VM.
3. Test inside the VM.
4. Once satisfied, create a new checkpoint that bakes in the final versions.

**Corollary — the `env.reset()` trap**: Each call to `env.reset()` in the framework's Python API restores the VM from the checkpoint. This means any files you SCP'd into a previous VM session are gone — you must re-copy after every reset. If you're running a test loop (`reset → setup → export → verify`), the SCP must happen inside the loop, after each reset.

**Applies to**: Any QEMU-based environment in this framework, which is all of them. The specific symptoms vary (stale setup scripts, stale export scripts, stale asset files), but the root cause is always the same: the VM filesystem is a snapshot, not a live mount of the host directory.

---

### 199. Safe JSON Assembly in Export Scripts with `jq -n` and Temp Files

**The Problem**: Export scripts must produce a single JSON file from multiple data sources (API calls, database queries, file reads). The natural approach — heredoc interpolation with shell variables — breaks in multiple ways:

- **Quotes in data**: If an API returns text containing single or double quotes, shell interpolation corrupts the JSON structure (Lesson 4).
- **Empty values**: If an entity doesn't exist (do-nothing test), parsed variables are empty, producing invalid JSON like `"key": ` (Lesson 185).
- **Nested JSON**: API responses that are already JSON objects cannot be embedded in a heredoc without escaping the entire structure.
- **Arrays**: Lists of members, messages, or IDs require `[...]` syntax that is painful to construct from shell loops.

The `escape_json()` function from Lesson 4 and the variable-guarding from Lesson 185 are workarounds. The pattern below eliminates the problem entirely by never using heredoc interpolation for the main result JSON.

**The Pattern**: Write intermediate results as separate JSON files to a temp directory, then use `jq -n` with `--slurpfile`, `--arg`, and `--argjson` to compose the final JSON object.

```bash
#!/bin/bash
TMPDIR="/tmp/${TASK_NAME}_export"
rm -rf "$TMPDIR" && mkdir -p "$TMPDIR"

# Step 1: Write each data source to its own temp file via jq
# API list responses → filtered arrays
api_call GET "channels.members?roomId=${CH_ID}&count=100" \
  | jq '[.members[].username] // []' > "$TMPDIR/members.json" 2>/dev/null \
  || echo '[]' > "$TMPDIR/members.json"

api_call GET "channels.history?roomId=${CH_ID}&count=50" \
  | jq '[.messages[] | {msg: .msg, ts: .ts}] // []' > "$TMPDIR/messages.json" 2>/dev/null \
  || echo '[]' > "$TMPDIR/messages.json"

# Step 2: Capture scalar values in shell variables
CHANNEL_EXISTS=true        # or false
CHANNEL_TOPIC="some topic" # may contain quotes, newlines, unicode

# Step 3: Assemble final JSON with jq -n
jq -n \
  --argjson ch_exists "$CHANNEL_EXISTS" \
  --arg     ch_topic  "$CHANNEL_TOPIC" \
  --slurpfile members  "$TMPDIR/members.json" \
  --slurpfile messages "$TMPDIR/messages.json" \
  '{
    channel_exists: $ch_exists,
    channel_topic:  $ch_topic,
    members:        $members[0],
    messages:       $messages[0]
  }' > "/tmp/${TASK_NAME}_result.json"

rm -rf "$TMPDIR"
```

**Why this is safe**:

| Mechanism | What it handles |
|---|---|
| `--arg key val` | Escapes `val` as a JSON string automatically — quotes, backslashes, newlines, unicode all handled |
| `--argjson key val` | Passes `val` as a raw JSON value (for booleans/numbers: `true`, `false`, `0`, `42`) |
| `--slurpfile var file` | Reads `file` as a JSON value and binds it to `$var` — no shell interpolation involved |
| `|| echo '[]'` | Fallback ensures the temp file always contains valid JSON, even when the API call fails |

**Key details**:

1. **`--slurpfile` wraps in an array**: `jq --slurpfile x file.json` makes `$x` an array with the file's content as `$x[0]`. Always use `$x[0]` in the template to unwrap.
2. **Boolean values**: Use `--argjson` (not `--arg`) for booleans. `--arg "true"` produces the JSON *string* `"true"`, not the boolean `true`.
3. **Temp directory cleanup**: Always `rm -rf "$TMPDIR"` at the end. Always `rm -rf "$TMPDIR" && mkdir -p "$TMPDIR"` at the start to ensure clean state.
4. **Composing nested objects**: For complex structures, build sub-objects with `jq -s` (slurp multiple files into one):

```bash
# Compose a room object from multiple temp files
build_room() {
  local prefix="$1"
  jq -s '.[0] + {members: .[1], messages: .[2]}' \
    "$TMPDIR/${prefix}_meta.json" \
    "$TMPDIR/${prefix}_members.json" \
    "$TMPDIR/${prefix}_messages.json"
}

ROOM_OBJ=$(build_room "main")

jq -n --argjson room "$ROOM_OBJ" '{main_room: $room}' > /tmp/result.json
```

**When to use this pattern vs. heredoc**:

| Scenario | Recommendation |
|---|---|
| 1-3 scalar fields, all controlled by you | Heredoc is fine (with Lesson 185 guards) |
| Any field from external data (API, DB, user input) | Use `jq -n --arg` for strings |
| Arrays or nested objects | Use `jq --slurpfile` with temp files |
| 5+ fields mixing scalars and arrays | Always use the full temp-file pattern |

**Applies to**: Any environment whose `export_result.sh` queries a REST API, database, or any external source whose output may contain arbitrary text (quotes, newlines, special characters). This is the majority of web application environments (Rocket.Chat, GitLab, Snipe-IT, WordPress, Moodle, etc.) and any environment where the export script assembles JSON from multiple data sources.

---

### 200. Entity-Type API Fallback for Role-Based Web Applications

**The Problem**: Many web applications expose different API endpoints for the same conceptual entity depending on its type or visibility. A "room" might be a public channel (`channels.*` endpoints) or a private group (`groups.*` endpoints). A "document" might be public (`documents.*`) or restricted (`restricted-documents.*`). The task description tells the agent to create an entity, but doesn't always control which type the agent chooses.

If the export script only queries one endpoint, it misses entities created as the other type. This is silent — the export produces `exists: false` even though the entity exists, and the verifier scores 0 for a correct action.

**The Pattern**: Always try both API paths in `export_result.sh`:

```bash
# Try public channel first
CH_RESP=$(api_call GET "channels.info?roomName=${ROOM_NAME}")
EXISTS=false
ROOM_ID=""

if echo "$CH_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  EXISTS=true
  ROOM_TYPE="public"
  ROOM_ID=$(echo "$CH_RESP" | jq -r '.channel._id // empty')
fi

# Fall back to private group
if [ "$EXISTS" = "false" ]; then
  GRP_RESP=$(api_call GET "groups.info?roomName=${ROOM_NAME}")
  if echo "$GRP_RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    EXISTS=true
    ROOM_TYPE="private"
    ROOM_ID=$(echo "$GRP_RESP" | jq -r '.group._id // empty')
  fi
fi
```

**Then use the room type to pick the correct sub-endpoints**:
```bash
if [ "$ROOM_TYPE" = "private" ]; then
  api_call GET "groups.members?roomId=${ROOM_ID}&count=100" | jq '...'
  api_call GET "groups.history?roomId=${ROOM_ID}&count=50" | jq '...'
else
  api_call GET "channels.members?roomId=${ROOM_ID}&count=100" | jq '...'
  api_call GET "channels.history?roomId=${ROOM_ID}&count=50" | jq '...'
fi
```

**Why this matters for scoring fairness**: If the task says "create a channel" and the agent creates a private group instead of a public channel, that may warrant partial credit (e.g., 6/12 instead of 12/12). But if the export script doesn't find the entity at all, the verifier scores 0/12 — punishing the agent for something it actually did. The verifier should evaluate *what was created*, not fail to detect it.

**Where this pattern occurs**:
- **Chat platforms**: public channels vs. private groups vs. DM rooms (Rocket.Chat, Mattermost, Zulip)
- **Project management**: public vs. private projects/boards (GitLab, OpenProject, Taiga)
- **CMS/wiki**: published vs. draft pages (WordPress, MediaWiki, BookStack)
- **File sharing**: public vs. private shares (Nextcloud, Seafile)
- **Any RBAC-aware API**: where the same logical entity has different endpoints depending on access level

**Applies to**: Any environment where the application's REST API uses different endpoint prefixes or paths for entities of different visibility or type. If the task allows the agent to choose the entity type (or if the agent might choose differently than expected), the export script must query all possible paths.

---

## Lesson 233: Industry Interchange Formats as Bidirectional Scripting Seams

**The Insight**: Many professional desktop applications save their primary project data in a **published industry data exchange standard** — not a proprietary format that happens to be XML (Lesson 18), but an actual standardized interchange schema with public documentation. When this is the case, the interchange format serves as a uniquely powerful **bidirectional scripting seam**: `setup_task.sh` can programmatically *write* complex, realistic initial data, and `verifier.py` can *parse* the saved file to check specific fields — all without ever touching the GUI.

**How this differs from Lesson 18 and Option D (Phase 2, `12_new_environment_onboarding.md`)**:

| Pattern | Direction | Discovery | Example |
|---------|-----------|-----------|---------|
| Lesson 18 (hidden format) | Read only | Reverse-engineer `.bsp` → SQLite | `sqlite3 file.bsp "SELECT ..."` |
| Option D (export trigger) | Read only | Trigger File → Export → parse CSV | `export_result.sh` runs an export command |
| **This lesson** (interchange format) | **Read + Write** | Format is documented; app natively saves in it | Setup writes XML; verifier reads same XML |

The key differentiator is **write access**: because the format is the app's native save format (not just an export option), `setup_task.sh` can create or modify the data file directly. This enables the full error-injection and contamination-injection patterns from `01_core_principles.md` without needing a running application instance.

**Common industry interchange formats by domain**:

| Domain | Application Examples | Interchange Format | Parse With |
|--------|---------------------|-------------------|------------|
| Project management | ProjectLibre, MS Project | MSPDI XML | `xml.etree.ElementTree` |
| CAD / 3D modeling | FreeCAD, LibreCAD, OpenSCAD | STEP, IGES, DXF | `ezdxf`, OCC |
| Music notation | MuseScore, Finale | MusicXML | `xml.etree.ElementTree` |
| GIS / mapping | QGIS, GRASS GIS | GeoJSON, GML, KML | `json`, `xml` |
| Personal finance | GnuCash, HomeBank | OFX / QFX | `ofxparse` |
| Medical imaging | 3D Slicer, OsiriX | DICOM, NRRD, NIfTI | `pydicom`, `nrrd` |
| Circuit design | KiCad | S-expression with documented schema | Custom parser |
| Business documents | LibreOffice (via UBL) | UBL XML (invoices, orders) | `xml.etree.ElementTree` |
| Chemical structures | Avogadro, PyMOL | PDB, MOL/SDF, CIF | `Bio.PDB`, `rdkit` |

**How to use this pattern**:

1. **In `setup_task.sh`**: Copy a real sample project file (in the interchange format), then use a Python heredoc to parse and modify specific fields — injecting errors, removing elements, or corrupting values. The app will load the modified file normally because the format is standards-compliant.

2. **In `verifier.py`**: Copy the saved file out of the environment and parse it with the same standard library. Check specific elements/fields for correctness using the documented schema as your guide.

```python
# setup_task.sh — inject errors into a standards-based project file
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

ns = "http://schemas.microsoft.com/project"  # MSPDI namespace
ET.register_namespace('', ns)
tree = ET.parse("/path/to/project.xml")

# Corrupt a specific field — the schema tells you exactly where it lives
for task in tree.findall(f'.//{{{ns}}}Task'):
    if task.findtext(f'{{{ns}}}UID') == '17':
        task.find(f'{{{ns}}}Duration').text = 'PT40H0M0S'  # was PT480H

tree.write("/path/to/project.xml", encoding='unicode', xml_declaration=True)
PYEOF
```

```python
# verifier.py — check the agent's corrections
root = ET.parse(saved_file).getroot()
dur = root.find(f'.//{{{ns}}}Task[{{{ns}}}UID="17"]/{{{ns}}}Duration')
hours = parse_duration(dur.text)
if hours >= 400:
    score += 20  # range-based: any domain-valid correction accepted
```

**When to look for this pattern**: During Phase 2 of environment onboarding (`12_new_environment_onboarding.md`), after checking Options A–D, also ask: *"Does this application save its primary data in a published interchange standard?"* Check the app's File → Save As dialog for format options, or inspect the saved file's XML namespace / header for standard identifiers. If the answer is yes, you have the strongest possible scripting seam — one that supports both complex setup injection and precise field-level verification without any GUI interaction.

**Rule**: When a desktop application uses an industry interchange format as its native save format, prefer direct file manipulation (read + write) over GUI-based setup or export-triggered verification. The interchange format's public schema serves as your verification contract — every element and attribute is documented, so you know exactly what to check.

---

### 201. Keyword-Scored Entity Discovery for Free-Form Named Resources

**The Problem**: Very hard tasks often require the agent to create a named resource (a channel, a document, a project, a folder) with a name of the agent's own choosing. You cannot hardcode the expected name in `export_result.sh` — the agent might call it "ir-ransomware-2026", "incident-command", or "emergency-cyber-response". Checking for a single hardcoded name will miss any valid agent response that chose a different name.

**The Pattern**: Record a baseline of all existing resources of the relevant type at setup time. At export time, enumerate ALL resources of that type, compute the delta (current − baseline), and score each new resource against a list of domain-relevant keywords. Pick the best-scoring one as the "agent's resource."

```python
# In export_result.sh — inline Python to identify the agent-created channel
python3 << 'PYEOF'
import json, os

tmpdir = os.environ['TMPDIR']
all_groups   = json.load(open(f'{tmpdir}/all_groups.json'))
baseline_set = set(json.load(open(f'{tmpdir}/baseline_groups.json')))

new_groups = [g for g in all_groups if g['name'] not in baseline_set]

# Domain-specific keywords for this task's expected resource type
domain_keywords = ['incident', 'ir-', 'ransomware', 'emergency', 'response', 'security']

best, best_score = None, -1
for g in new_groups:
    s = sum(1 for kw in domain_keywords
            if kw in g['name'].lower() or kw in (g.get('topic') or '').lower())
    if s > best_score:
        best_score, best = s, g

json.dump({'resource': best or {}, 'found': best is not None}, open(f'{tmpdir}/found.json','w'))
PYEOF
```

**In the verifier**: Award full credit if the resource is found with score > 0 (name/topic contains at least one domain keyword), partial credit if a resource was found but keywords are absent (agent may have created it with a generic name), zero credit if no new resource exists at all.

**What makes this robust**:
- Baseline delta ensures only agent-created resources are evaluated — pre-existing data cannot game it
- Keyword scoring tolerates diverse naming choices while rewarding domain-appropriate names
- The same pattern works for any named resource in any application: channels, documents, projects, tickets, folders, database records, Git branches, etc.

**Keyword selection rule**: Use 6–12 keywords that a professional naming this resource would plausibly use. Include both acronyms (`ir-`, `inc-`) and full words (`incident`, `response`), and both generic (`emergency`) and domain-specific (`ransomware`, `cve`, `churn`) terms. A new resource scores 0 if the agent creates something completely unrelated (e.g., "test-channel") — which should award 0 for name/topic criterion but not prevent the verifier from scoring content inside it.

**Applies to**: Any environment where the agent creates a named entity as part of the task — collaboration platforms (Rocket.Chat, Mattermost, Slack-like), project management tools (Jira, OpenProject, Taiga), wikis (Confluence, BookStack, MediaWiki), file systems, or databases. The pattern is universal: baseline → delta → keyword-score → pick best.

---

### 202. Multi-Source Text Aggregation for Open-Ended Communication Verifiers

**The Problem**: In tasks where the agent must communicate content (analysis, decision, plan, status update), a capable agent may write the content in any of several valid locations — a dedicated channel, a direct message, a thread reply, or an existing channel. A verifier that only scans one location (e.g., only the "expected" channel) will return a false negative score=0 whenever the agent chose a different-but-equally-valid location. This is a verification bug that punishes agent creativity.

**The Pattern**: Before any keyword or content scoring, collect ALL text produced by the agent across ALL relevant locations — channels, DMs, threads, notes, etc. — into a single combined string. Score against this combined text.

```python
def _collect_all_admin_text(result):
    """Aggregate all admin-authored content from every possible location."""
    texts = []
    # Dedicated channel messages
    for m in result.get('coord_channel', {}).get('messages', []):
        if m.get('u') != 'system':
            texts.append((m.get('msg') or '').lower())
    # Existing channel admin messages (agent may have used these instead)
    for m in result.get('source_channel_admin_messages', []):
        texts.append((m.get('msg') or '').lower())
    # DMs to any stakeholder
    for msgs in result.get('direct_messages', {}).values():
        for m in msgs:
            texts.append((m.get('msg') or '').lower())
    # Thread replies authored by admin
    for thread_msgs in result.get('threads', {}).values():
        for m in thread_msgs:
            if m.get('u') == 'admin':
                texts.append((m.get('msg') or '').lower())
    return texts

combined = ' '.join(_collect_all_admin_text(result))
# Now score against combined — location-agnostic
deadline_found = any(kw in combined for kw in ['deadline', 'by ', 'eod', 'march'])
```

**What this prevents**:
- An agent that sends the retention plan as a DM to the CEO (rather than posting it in the escalation channel) still gets credit
- An agent that replies to a thread rather than creating a new channel still gets keyword credit
- Verifier scores intent and content, not the specific UI path the agent chose

**Contrast with wrong-target checking**: This pattern is about location flexibility for *content*. It is compatible with wrong-target rejection for *entity creation* — you can still require that the agent created *some* new resource (Lesson 201) while allowing content to appear in any location.

**Export script responsibility**: The export script must be written to collect admin-authored content from all plausible locations so the verifier has the raw material. If you only export the content of one specific channel, the verifier cannot aggregate. Design `export_result.sh` to query every location where a capable agent might plausibly write.

**Applies to**: Any task in a communication platform (Rocket.Chat, email, Slack-like, project management comments), document collaboration tool, or any environment where the same content can legitimately appear in multiple locations. The pattern is especially important for "very hard" tasks where the agent must figure out the right structure independently — by definition, those agents will choose different structures.

---

### 203. Scattered-Context Task Design for Genuine Discovery Burden

**The Problem**: A common failure mode in task design is concentrating all task-relevant information in one obvious location. If all the context the agent needs is in a single channel, file, or record, the agent reads it once, acts on it, and the task is too easy. The agent never needs to reason about which locations to consult or how to synthesize a picture from fragments.

**The Pattern**: For very hard tasks, deliberately seed the task's situational context across 3+ distinct locations, where each location provides a different piece of a picture that requires synthesis to act on correctly. No single location is complete.

```
Location 1 (#customer-success):   Health score alert + VP Operations call quote
Location 2 (#sales-enterprise):   Competitive intel + executive escalation context
Location 3 (#product-feedback):   Root cause — 3 delayed roadmap commitments

None of these alone is sufficient to understand what retention requires.
The agent must read all three and synthesize: churn is about delayed features,
not just tickets, and the competitive threat is real.
```

**Design rules**:
1. **Each location provides a genuinely different aspect** — not just more detail on the same aspect. If all three channels say the same thing with different wording, the agent learns nothing new from reading all three.
2. **Context is complementary, not redundant** — Reading location 1 without locations 2 and 3 leads to a systematically wrong or incomplete action plan.
3. **The synthesis step is the actual task difficulty** — A professional who only reads one location would take the wrong action. The hard part is knowing you need to read multiple locations and what to conclude from the combination.
4. **Locations should be natural, not artificial** — Use channels/files that a professional would realistically consult. A hospital IT incident creates natural separation across clinical, nursing, and security channels. An SRE postmortem task has natural separation across postmortems, on-call, and general channels.

**What this is NOT**:
- A needle-in-haystack design (all locations contain lots of noise, one contains the answer) — that tests patience, not reasoning
- Redundant seeding (same information in multiple places for safety) — that eliminates the synthesis requirement

**Discovery burden vs. information hiding**: This pattern creates *legitimate* discovery burden where a professional would actually need to consult multiple sources. It is different from hiding information arbitrarily. The agent needs to know to check `#clinical-it-alerts` because a hospital IT incident would naturally generate alerts there. That's professional domain knowledge, not guessing.

---

### 204. Read Sibling Tasks' Export Scripts Before Writing SQL for a New Task

**The Problem**: Lesson 36 says "boot the VM and inspect the schema" before writing SQL. This is correct, but slow — it requires a full VM boot and manual exploration. For environments that already have working tasks, there is a faster and more reliable source of ground truth that is available immediately: the other tasks' `export_result.sh` files.

**The Insight**: Each existing task's export script encodes **the actual column names, table names, and query patterns that are known to work** in that environment. If a working task already queries `vtiger_troubletickets` using `title`, `status`, `priority`, `severity`, those are the correct column names — even if the official documentation says `ticket_title`, `ticketstatus`, `ticketpriorities`, `ticketseverities`.

**Concrete failure**: For a new Vtiger CRM task, the task creator assumed the standard Vtiger schema column names and wrote:
```sql
SELECT ticketstatus, ticketpriorities, ticketseverities
FROM vtiger_troubletickets
WHERE ticket_title = 'HIPAA audit finding - unencrypted backups'
```
This returned empty rows for every query — causing the do-nothing score to be wrong, and the setup injection to silently do nothing. The working `create_ticket` task already showed the correct columns:
```sql
SELECT t.status, t.priority, t.severity
FROM vtiger_troubletickets t
WHERE t.title = '...'
```
Ten seconds of reading the sibling task would have prevented hours of debugging.

**The Rule**: Before writing any SQL for a new task in an established environment, run:
```bash
grep -h "SELECT\|UPDATE\|INSERT\|FROM\|WHERE" benchmarks/cua_world/environments/<env_name>/tasks/*/export_result.sh | head -60
```
Use the column names, table names, and query patterns you find there. Only fall back to VM inspection or Lesson 40's multi-variant approach if no sibling task queries the same table.

**Applies to**: Any environment with multiple tasks backed by the same database (MySQL/MariaDB/PostgreSQL/SQLite). CRM environments (Vtiger, SuiteCRM, Odoo), ERP systems, and web apps backed by a shared database are especially prone to this because the official schema documentation often reflects a different version of the software than what is actually installed.

---

### 205. Audit Seed Data Before Writing Setup Logic — Entity Existence and Initial State

**The Problem**: Setup scripts often make two implicit assumptions that are never validated:
1. **The target entity exists** in the seeded database
2. **The target entity is in the expected initial state** (e.g., an active deal, not already Closed Won)

Both assumptions fail silently. If the entity doesn't exist, the `UPDATE` matches 0 rows and the task is broken. If the entity is already in the terminal state you want the agent to reach, a conditional `UPDATE ... WHERE stage NOT IN ('Closed Won', 'Closed Lost')` does nothing — and the export query returns the terminal state, giving the agent free points on the do-nothing test.

**Example failure — entity doesn't exist**: The stale_pipeline task cleared fields on "Blackstone Industrial" and used it as a verification target. But "Blackstone Industrial" was never in the seed data (`seed_data.php` had 15 other companies). Every query for this account returned empty, and the verifier awarded 0 points for criterion 3 regardless of what the agent did.

**Example failure — entity already in terminal state**: The same task tried to inject a stale closing date into "Nexus SCADA Security Assessment" using:
```sql
UPDATE vtiger_potential SET closingdate='2025-11-30'
WHERE potentialname='Nexus SCADA Security Assessment'
AND sales_stage NOT IN ('Closed Won', 'Closed Lost')
```
But the seed data had Nexus SCADA already set to `Closed Won`. The conditional `AND` clause made the UPDATE a no-op. The export then reported `nexus_stage='Closed Won'`, and the verifier gave partial credit (5/35) for "closed" appearing in the stage name — inflating the do-nothing score.

**The Fix**: Before writing any setup or export script, do this two-step audit against the seed data file:

```bash
# Step 1: Verify entity exists
grep -n "Blackstone Industrial\|Nexus SCADA" benchmarks/cua_world/environments/<env_name>/data/seed_data.sql
grep -n "Blackstone Industrial\|Nexus SCADA" benchmarks/cua_world/environments/<env_name>/utils/seed_data.php

# Step 2: Check the entity's seeded initial state
# e.g., look for sales_stage, ticketstatus, probability in the seed row
grep -A5 "Nexus SCADA" benchmarks/cua_world/environments/<env_name>/utils/seed_data.php
```

If the entity doesn't exist: either add it to the seed (preferred), create it in setup_task.sh, or pick a different entity that does exist.

If the entity is already in the terminal state: remove the defensive `AND ... NOT IN (...)` condition and unconditionally reset the entity to the desired starting state:
```sql
-- Force the entity to the expected starting state first, then task can proceed
UPDATE vtiger_potential
SET sales_stage='Value Proposition', probability='25', closingdate='2025-11-30'
WHERE potentialname='Nexus SCADA Security Assessment'
```

**Rule**: For every entity name that appears in setup_task.sh or export_result.sh, confirm it exists in the seed data and note its seeded initial state. Do this before writing a single line of SQL. The checklist item "Verify all seeded data is present in the environment before finalizing" means exactly this — not just "the environment boots," but "the specific records your task references are actually there and in the state you need."

**Applies to**: All tasks in database-backed environments. Especially common when reusing entity names across multiple tasks in the same environment, or when designing tasks for entities that "logically should exist" in a real business but weren't included in the initial seed.

---

### 206. Broad LIKE Queries in Export Scripts Can Match Pre-Existing Seeded Records

**The Problem**: Export scripts for tasks that require the agent to *create* a new record often use broad `LIKE` patterns to find that record:
```sql
SELECT ... FROM vtiger_activity
WHERE subject LIKE '%HIPAA%Pinnacle%'
   OR subject LIKE '%HIPAA%Emergency%'
```
If any pre-existing **seeded** record happens to match this pattern, the export will find it and mark `event_found=True` — giving the agent points for a record they never created. The do-nothing test then returns a non-zero score, masking a verifier bug.

**Concrete failure**: A task required the agent to create a HIPAA emergency meeting. The seed data included a calendar event called "Pinnacle HIPAA Remediation Kickoff" (seeded as context/backstory). This event matched `%HIPAA%Pinnacle%`, causing the export to find it and award 15/100 points on the do-nothing test — even though the agent did nothing.

**Why this is hard to catch**: The seeded record is legitimate context (it makes sense for the CRM to have a prior kickoff meeting). It is not a bug in the seed data. The bug is in the export query being too broad.

**The Fix — explicit deletion in setup_task.sh**: The simplest fix is to delete any pre-existing seeded records that would match the export query, at the start of the task. This is idempotent and resets the search space cleanly:
```bash
# In setup_task.sh: remove pre-existing records that could match export queries
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject='Pinnacle HIPAA Remediation Kickoff'"
vtiger_db_query "DELETE FROM vtiger_activity WHERE subject='HIPAA Emergency Remediation - Pinnacle Healthcare'"
echo "Cleared pre-existing HIPAA/Pinnacle events — agent must create a new one"
```

**Alternative fix — anchor queries to task start time**: Record the maximum record ID at setup time and filter to only records created after that ID:
```bash
# In setup_task.sh:
INITIAL_MAX_ID=$(vtiger_db_query "SELECT COALESCE(MAX(activityid), 0) FROM vtiger_activity")
echo "$INITIAL_MAX_ID" > /tmp/hipaa_initial_max_event_id

# In export_result.sh:
INITIAL_MAX_ID=$(cat /tmp/hipaa_initial_max_event_id 2>/dev/null || echo "0")
EVENT_DATA=$(vtiger_db_query "
  SELECT activityid, subject, ... FROM vtiger_activity
  WHERE activityid > $INITIAL_MAX_ID
    AND (subject LIKE '%HIPAA%' OR subject LIKE '%Emergency%')
  ORDER BY activityid DESC LIMIT 1
")
```

**The Rule**: After writing any export query that uses `LIKE` patterns to find agent-created records, search the seed data for any existing records that match the same pattern. If any exist, add explicit DELETE statements for them in setup_task.sh, or add an ID-anchor filter to the export query. Then re-run the do-nothing test and confirm score=0.

**Applies to**: Any task where the agent must *create* a new record and the export detects that record using a keyword/pattern search rather than a precise ID. Common for calendar events, notes, tickets, and any free-text-subject records in CRM, ERP, or project management environments.

**Applies to**: Any task in an environment where content naturally distributes across multiple locations — collaboration platforms (multi-channel situations), file systems (project data spread across directories), databases (data normalized across multiple tables), web applications with multiple views or sections. In single-location environments (e.g., a standalone desktop app with one document), this pattern does not apply — use error-injection or contamination-injection instead.

---

## Lesson 50: Use Episode Artifact Frames as Direct Evidence for Task Start State

When you run a do-nothing test (or any test episode), the framework records screenshots to:

```
benchmarks/cua_world/environments/<env_name>/artifacts/episode_<timestamp>/frame_00000.png
```

`frame_00000.png` is the very first frame captured — taken immediately after the pre-task hook completes and before the agent takes any action. This is the canonical evidence that the task's initial state is correct (correct application open, correct file loaded, correct UI visible).

**How to use this in evidence collection:**

```python
import glob, shutil, os

artifact_dirs = sorted(glob.glob("benchmarks/cua_world/environments/<env>/artifacts/episode_*"))
if artifact_dirs:
    latest = artifact_dirs[-1]
    frame = os.path.join(latest, "frame_00000.png")
    shutil.copy(frame, "benchmarks/cua_world/environments/<env>/evidence_docs/<task>_start_state.png")
```

**What to verify in the screenshot** (use visual inspection or the `visual_grounding` MCP tool):
- The correct application is open (VS 2022, browser, spreadsheet, etc.)
- The correct project/file/solution is loaded (visible in title bar or explorer pane)
- The task's injected content is visible (broken code, missing test, vulnerable code, etc.)
- No unexpected dialogs or error overlays are present

**Why this matters**: Verifying `frame_00000.png` is the only reliable proof that `setup_task` ran correctly for a GUI environment. Hook logs may show warnings (e.g., encoding errors) even when setup succeeded; conversely, a clean log does not guarantee the application actually launched. The screenshot is ground truth.

**Rule**: Always capture and review `frame_00000.png` as part of task validation. If it shows the wrong application, wrong file, or an error dialog, the task is broken regardless of what the hook log says.

---

### 207. Quoted vs. Unquoted Heredoc Markers for Bash-to-Python Variable Passing

**The Problem**: Setup and export scripts often embed Python code via bash heredocs (`python3 << 'PYEOF' ... PYEOF`). The standard recommendation is to use a quoted marker (`'PYEOF'`) to prevent shell variable expansion inside the Python block. But when the Python block needs access to a bash variable computed earlier in the script (e.g., a recorded timestamp, baseline count, or dynamically discovered ID), a quoted marker blocks that access entirely — and Python has no way to read the value.

**What breaks**:
```bash
# setup_task.sh records a start timestamp
date +%s > /tmp/task_start_ts
START_TS=$(cat /tmp/task_start_ts)

# export_result.sh reads it — but uses 'PYEOF' (quoted)
python3 << 'PYEOF'
import json
# $START_TS is NOT expanded — this is a literal dollar-sign string
start = "$START_TS"   # This will be the literal string "$START_TS", not the value
PYEOF
```

**The Fix**: Use an unquoted heredoc marker (`PYEOF` without quotes) when the Python block needs bash variables. Escape any `$` that is meant for Python (dict access, f-strings, regex patterns) with a backslash:

```bash
START_TS=$(cat /tmp/task_start_ts)

python3 << PYEOF
import json, subprocess

# $START_TS is now expanded by bash before Python runs
start_ts = $START_TS   # becomes e.g.: start_ts = 1741305600

# Escape Python's own $ with backslash (e.g., in subprocess shell strings)
result = subprocess.run(['mysql', '-e', "SELECT COUNT(\*)"], capture_output=True, text=True)

with open("/tmp/result.json", "w") as f:
    json.dump({"start": start_ts, "count": result.stdout.strip()}, f)
PYEOF
```

**Decision rule**:
- Need to pass a bash variable into Python → use `<< PYEOF` (unquoted); escape Python's `$` with `\$`
- No bash variables needed in Python → use `<< 'PYEOF'` (quoted); Python's `$` works naturally

**Common context**: export scripts that filter DB results by a task start timestamp (e.g., `WHERE request_time >= $START_TS`), or that include baseline counts recorded by setup_task.sh as JSON values.

**Pitfall**: Using `<< PYEOF` without escaping Python's `$` fails silently. Shell expansion attempts to expand all unescaped `$var` sequences; if the variable is undefined, it expands to an empty string, producing a Python syntax error (`start_ts = ` with nothing after it).

---

### 208. Schema-Adaptive INSERTs via Column Discovery for Version-Tolerant Setup Scripts

**The Problem**: `setup_task.sh` often needs to INSERT rows into application database tables. Documentation may list more columns than actually exist in the deployed version, or optional columns may vary. Hardcoding all columns in the INSERT fails with `Unknown column 'X' in 'field list'` when X was not present in this deployment, and bash heredoc Python blocks may swallow the exception — printing "Setup complete" while zero rows were inserted.

**What breaks**:
```python
# Hardcoded INSERT — fails silently if OC_CHRONICMED_POSOLOGY doesn't exist in this version
q("INSERT INTO oc_chronicmedications (OC_CHRONICMED_PATIENTID, OC_CHRONICMED_PRODUCTID, "
  "OC_CHRONICMED_POSOLOGY, OC_CHRONICMED_STARTDATE) VALUES (...)")
```

**The Fix**: Query `SHOW COLUMNS` (MySQL/MariaDB) or `PRAGMA table_info` (SQLite) before building the INSERT, and include only columns that exist:

```python
# Discover actual columns first
col_info = q("SHOW COLUMNS FROM oc_chronicmedications")
actual_cols = [line.split('\t')[0] for line in col_info.splitlines() if line.strip()]

# Build INSERT conditionally
col_map = {
    'OC_CHRONICMED_PATIENTID': patient_id,   # always required
    'OC_CHRONICMED_PRODUCTID': product_id,   # always required
}
# Optional columns: include only if present in the schema
if 'OC_CHRONICMED_POSOLOGY' in actual_cols:
    col_map['OC_CHRONICMED_POSOLOGY'] = f"'1 tablet daily'"
if 'OC_CHRONICMED_STARTDATE' in actual_cols:
    col_map['OC_CHRONICMED_STARTDATE'] = 'NOW()'
if 'OC_CHRONICMED_VERSION' in actual_cols:
    col_map['OC_CHRONICMED_VERSION'] = 1

col_names = ', '.join(col_map.keys())
col_vals  = ', '.join(str(v) for v in col_map.values())
q(f"INSERT IGNORE INTO oc_chronicmedications ({col_names}) VALUES ({col_vals})")
```

**DB-specific equivalents**:
| Database | Schema discovery query |
|---|---|
| MySQL / MariaDB | `SHOW COLUMNS FROM table_name` |
| SQLite | `PRAGMA table_info(table_name)` |
| PostgreSQL | `SELECT column_name FROM information_schema.columns WHERE table_name='table_name'` |
| SQL Server | `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='table_name'` |

**When to apply**: Any `setup_task.sh` that inserts into an application's built-in tables (HIS, EHR, CMS, ERP, or any multi-version software). Third-party table schemas change across versions, patch levels, and local customizations. Always discover before inserting.

**When NOT to apply**: Tables you control and create in the setup script itself — you know the schema because you defined it.

**Rule**: Never hardcode a full column list for an application-owned table. Always query the schema, build the INSERT dict conditionally, and log which columns were omitted so that setup failures are visible.

---

### 209. Same-Field-Different-Context Traps for Multi-Entity Domain Knowledge Tasks

**The Problem**: The standard contamination injection / decoy design (01_core_principles.md) describes a "correct" item that must not be removed alongside "incorrect" items that must be removed. In simple decoys, the correct item differs from the incorrect ones by category, type, or some easily visible property. This can be gamed by an agent that simply avoids items it hasn't encountered before. The deeper class of trap — one that requires actual domain reasoning — is when the **exact same field value** appears in two entities' records, but is appropriate for one and inappropriate for the other, and the distinction is only visible by reading a **second, independent field** for each entity.

**Example — medication correctness varies by patient lab result**:
- David (10004): has Metformin on chronic medications list; CREAT = 1.1 mg/dL (normal) → Metformin is APPROPRIATE, must keep
- Li Wei (10009): has Metformin on chronic medications list; CREAT = 4.8 mg/dL (critical) → Metformin is CONTRAINDICATED, must remove

Both patients have the same drug. The field value (Metformin) is identical. The correct action (keep vs. remove) is determined entirely by a second field (the CREAT lab result). An agent that pattern-matches "Metformin + critical CREAT = remove" without reading each patient's actual CREAT value will either remove it from both (wrong) or neither (wrong).

**Other domains where this pattern applies**:
- Finance: same investment product is compliant for one account type but violates regulations for another (the distinguishing field is account classification or jurisdiction)
- Manufacturing: same component spec is valid for Product A but out-of-tolerance for Product B (the distinguishing field is product-line tolerance range)
- IT config management: same parameter value is correct for one deployment tier but wrong for another (the distinguishing field is environment tag or region)
- HR/compliance: same policy applies to full-time employees but not contractors (the distinguishing field is employment type)

**Why this is harder than a simple decoy**:
- Simple decoy: agent avoids removing the visually/categorically distinct item
- Same-field trap: agent must read a second field per entity, apply domain knowledge, and make an entity-specific decision — there is no shortcut based on the field value alone

**Design rules**:
1. The shared field must be **identically formatted** for both entities (same drug name, same parameter key, same product code) — any formatting difference would give it away
2. The distinguishing field must be **in a different part of the UI** (a different module, tab, or record view) than the shared field — the agent must actively navigate to retrieve it
3. The verifier must score the **two entities independently**: keeping the correct one earns points separately from removing the incorrect one; removing both or neither loses points on both
4. Document both the shared field value AND the distinguishing field values in `task.json` metadata so the verifier has ground truth without reading the setup script

**Scoring design**: Give the trap (keeping the correct entity unchanged) its own criterion worth 10–15% of total score. This penalizes agents that "solve" the task by indiscriminately removing all matching items.

**Applies to**: Any multi-entity task in an environment where domain knowledge governs whether a shared field value is appropriate — medical, financial, regulatory, manufacturing, configuration management.

---

### 210. Seeded Entity State Can Pre-Satisfy Verifier Criteria — Check Every Criterion Against the Seed

**The Problem**: In database-backed environments (CRM, project management, EMR, ERP), the seed script puts entities in specific states — statuses, priorities, assignees, time entries. When a verifier criterion checks for state S on entity X, it fires immediately if the seed already set entity X to state S. This gives the agent free points without doing anything, violating the do-nothing invariant.

**This is distinct from Lesson 16 (Starter File Keyword Contamination)**: Lesson 16 is about text keywords in files provided to the agent. This lesson is about field values in records that the seed script inserted — the entity already *is* in the target state, so no change is needed to pass the criterion.

**Classic example**: Task says "change the payment gateway issue from New to In Progress." Verifier has criterion: `status == 'In Progress' → 25 pts`. But the seed set that issue's status to "In Progress". Do-nothing score = 25.

**The Fix**: Before writing each criterion, look up the actual seeded value of that field. If the seeded value already matches the expected post-task value, that criterion cannot be used — it gives free points immediately.

```bash
# Before finalizing any criterion, query the seed state directly:
curl -s "http://localhost:3000/issues/${ISSUE_ID}.json?key=${API_KEY}" | jq '.issue.status.name'
# → "In Progress"  # already there! Don't write a criterion that checks status == "In Progress"
```

**Three valid remedies**:
1. **Remove the criterion** and replace it with something the agent must actually change.
2. **Make it a delta criterion**: check that the field CHANGED relative to baseline (e.g., `new_status != baseline_status`). This requires recording baseline in `setup_task.sh`.
3. **Replace with a different criterion** on the same issue that is NOT already satisfied — e.g., instead of checking status, check that a specific comment was added.

**Audit protocol**: After writing all verifier criteria, run `export_result.sh` immediately after `setup_task.sh` (before any agent action) and inspect the result JSON. For every criterion that would be satisfied by that JSON, the criterion is broken.

**Applies to**: Any database-backed environment with complex seed data — project management tools (Redmine, Jira, Azure DevOps), CRM systems (Vtiger, Salesforce), EMR/EHR systems, ERP systems, ticketing systems. The richer and more realistic the seed data, the higher the chance that some seeded entity already satisfies a criterion you planned to write.

---

### 211. Partial-Credit Scoring Branches Must Also Be Checked Against Seeded Data

**The Problem**: A verifier criterion that awards full points requires agent action. A partial-credit branch (e.g., `elif total_hours >= 1.5: score += 12`) is treated as "safe" — it's only partial credit. But if the seed already satisfies the partial-credit condition (e.g., 2.5h of Development time was already logged on the issue in the seed), the partial-credit branch fires in the do-nothing test, giving free points just as surely as a full-credit criterion would.

**The typical pattern that fails**:
```python
# Task: "Log ≥1.5h of Testing activity on the push notification issue"
push_testing_hours = result.get('testing_hours', 0)   # 0 in seed
push_total_hours   = result.get('total_hours', 0)     # 2.5 in seed (Development, not Testing)

if push_testing_hours >= 1.5:
    score += 25   # full credit — correct, not triggered
elif push_total_hours >= 1.5:
    score += 12   # partial credit — WRONG: triggered because seed has 2.5h Development!
```

**The Fix**: Two options:
1. **Remove the partial-credit branch entirely** if the partial condition can be satisfied by seeded data. Only award points for the specific, required outcome.
2. **Gate partial credit on the right activity type or a baseline delta**: partial credit should only fire if the agent added time (new entry count > baseline count) even if the activity type is wrong.

```python
# SAFE: no partial credit for wrong activity type
if push_testing_hours >= 1.5:
    score += 25
else:
    subscores['push_notif_testing_hours'] = False
    feedback.append(f"Push notif has {push_testing_hours}h Testing logged (expected >=1.5h Testing)")
```

**The broader principle**: The do-nothing invariant (`score == 0 when agent does nothing`) applies to EVERY scoring branch, not just the primary `if` branch. Walk through every `elif` and `else` branch in your verifier with the seed state JSON and confirm that none of them award points.

**How to audit**: Construct the seed-state JSON (by running `export_result.sh` immediately after `setup_task.sh` in a live environment) and trace through every verifier branch manually. Any branch that awards >0 points given the seed-state JSON is a bug, regardless of whether it is labelled as "full" or "partial" credit.

**Applies to**: Any verifier that uses partial-credit scoring (`elif` branches that award a fraction of the full score). Common in time-logging tasks, quality-score tasks, and any criterion where "partial completion" is a meaningful intermediate state. The risk is highest when the seed data is rich and realistic — seeded time entries, existing comments, pre-set priorities, and pre-existing issue links are all potential sources of partial-credit leakage.

---

### 212. Strip HTML from Rich-Text Fields Before Writing to Result JSON

**The Problem**: Many web applications use rich-text editors (TinyMCE, Quill, Odoo's HTML field widget, CKEditor) for multi-line text fields such as descriptions, notes, corrective actions, and comments. When these fields are read via the application's API, they return the raw stored value — which includes full HTML markup: `<p>Fix applied: replaced defective part.</p>`. Verifiers that check the returned string for length, keywords, or non-emptiness operate on the HTML-tagged version, producing two classes of silent bugs:

1. **False positives on empty fields**: A field the user left blank may be stored as `<p><br/></p>` or `<p>\u00a0</p>`. `len("<p><br/></p>") >= 10` evaluates to `True`, incorrectly awarding points for an empty response.
2. **Inflated length checks**: `len("<p>ok</p>") >= 10` is `True` even though the meaningful content is only 2 characters. A minimum-length threshold intended to reject trivial responses is bypassed by the surrounding tags.

**Real example** (Odoo `quality.alert` fields `corrective_action`, `preventive_action`): These are stored as HTML. Reading via XML-RPC returns `'<p>Replaced supplier batch.</p>'`. A raw `len(value) >= 10` check passes even for `'<p><br/></p>'` (visually empty).

**The Fix**: In `export_result.sh`, strip HTML tags before writing rich-text fields to the result JSON. Use Python's `re` and `html` modules (always available in stdlib):

```python
import re, html

def strip_html(s):
    if not s:
        return ''
    s = html.unescape(s)           # &amp; → &, &nbsp; → space, etc.
    s = re.sub(r'<[^>]+>', '', s)  # remove all tags
    return s.strip()

corrective = strip_html(alert.get('corrective_action', '') or '')
```

Write the stripped plain-text value to the result JSON. The verifier then receives clean text it can reason about correctly.

**Defence-in-depth**: Even if `export_result.sh` strips HTML, apply the same `strip_html` function inside the verifier before any length or keyword check. This costs nothing and prevents silent regressions when future export scripts omit the stripping step.

**Applies to**: Any environment where the application uses a rich-text / WYSIWYG editor for fields the verifier checks — CRM/ERP systems (Odoo, SuiteCRM, ERPNext), project management tools (Redmine, Jira), medical/EHR systems (OpenEMR note fields), CMS platforms, and any web application with description or comment fields. If the API returns a string starting with `<p>` or `<div>`, strip before verifying.

---

### 213. In Modular Web Applications, Verify Application-Module Readiness Separately from Service Availability

**The Problem**: Many web applications install optional features as application-level modules or plugins that activate *after* the web service is already running and accepting HTTP requests. In these environments two distinct readiness layers exist:

- **Layer 1 (service layer)**: The web server accepts HTTP requests and returns 200 OK. This is what `wait_for_service` / Lesson 160 checks for.
- **Layer 2 (module layer)**: The specific application module (e.g., `quality_control` in Odoo; WooCommerce in WordPress; a Django app) has been fully installed and its database models/tables are accessible. Module installation runs after the service is up and can take several minutes.

When `post_start.sh` triggers a module installation that takes 5–10 minutes, `setup_task.sh` (pre_task hook) may run while the installation is still in progress. The web service responds to HTTP normally (Layer 1 ready), but querying the module's models raises errors like `Object quality.alert.stage doesn't exist` or `Invalid field X on model Y` — because Layer 2 is not yet complete.

**Symptoms**:
- `setup_task.sh` Python block exits with an API/ORM error mid-way through seeding
- Without `set -e`, bash continues past the failed Python block; the script prints "Setup complete" and may even take a screenshot — but the GT file was never written
- The verifier returns `passed=False, score=0` with feedback like `gt_missing: No such file or directory: '/tmp/<task>_gt.json'`
- The failure looks like a code bug but is actually a timing issue

**The Fix**: In `setup_task.sh`, after confirming the web service is up (Layer 1), add a Layer 2 probe that checks whether the specific application model your task depends on is accessible. Retry with backoff until it is:

```python
import xmlrpc.client, time, sys

url, db, user, pwd = 'http://localhost:8069', 'mydb', 'admin', 'admin'
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

uid = common.authenticate(db, user, pwd, {})  # Layer 1 must already pass

# Layer 2: verify the target module's model is accessible
MAX_WAIT, INTERVAL = 600, 15  # wait up to 10 minutes
for attempt in range(MAX_WAIT // INTERVAL):
    try:
        models.execute_kw(db, uid, pwd, 'quality.alert.stage', 'search', [[]], {'limit': 1})
        print("Module ready.")
        break
    except Exception as e:
        msg = str(e)
        if "doesn't exist" in msg or "does not exist" in msg:
            print(f"Module not yet installed (attempt {attempt + 1}), waiting {INTERVAL}s...")
            time.sleep(INTERVAL)
        else:
            raise  # unexpected error — surface it immediately
else:
    print("FATAL: Application module did not become ready within timeout.")
    sys.exit(1)
```

**When this check is not needed**: In production benchmark environments that use pre-built QEMU snapshots (where module installation was completed before the snapshot was taken), Layer 2 is already satisfied when the VM starts. The retry loop adds negligible overhead (one fast probe) and can be left in for safety.

**How to tell whether you need it**: If `post_start.sh` runs a module installation command (e.g., `docker compose run ... install_module`, `wp plugin install ...`, `python manage.py migrate`), assume Layer 2 may not be ready when `setup_task.sh` starts.

**General principle**: A generic HTTP 200 check is necessary but not sufficient for modular applications. Always write a Layer 2 probe targeted at the specific model or API endpoint your task uses.

**Applies to**: Modular ERP/CRM systems (Odoo, ERPNext, SuiteCRM), CMS platforms with plugins (WordPress, Drupal), Django/Rails apps with optional engines, and any web application where `post_start` installs application-level features after the web service starts.


---

## Lesson 234: Document the Anti-Pattern 4 Score Audit Table in Every Verifier Docstring

**The Problem**: Anti-Pattern 4 (partial credit total exceeds pass threshold) is easy to diagnose in principle but easy to miss in practice because the calculation is implicit — it requires mentally summing across all criteria, including multi-entity amplification. When a verifier is modified or the threshold is adjusted later, the audit is not re-run and the invariant silently breaks.

**The Fix**: Every verifier function should include an explicit score audit table in its docstring, written at the time the verifier is first created and updated whenever criteria or thresholds change:

```python
def verify_my_task(traj, env_info, task_info):
    """
    Scoring breakdown:
      C1  user_registration    28 pts  | partial: 0 (binary: all N or nothing)
      C2  email_set            9 pts   | partial: 6 (proportional to N correct)
      C3  routine_name         10 pts  | partial: 0
      C4  training_days        9 pts   | partial: 6 (proportional to days correct)
      C5  measurement_cats     12 pts  | partial: 0
      C6  measurement_entries  24 pts  | partial: 8 (1/3 categories)
      C7  nutrition_macros     8 pts   | partial: 0
      Total full:              100 pts

      Anti-Pattern 4 audit:
        max_partial_total = 0 + 6 + 0 + 6 + 0 + 8 + 0 = 20
        pass_threshold    = 70
        20 < 70 ✓  (partial-only completion cannot pass)

      Multi-entity amplification check (C1, N=4 users):
        If C1 were awarded per-entity at 5 pts partial → 4×5 = 20 pts
        20 + 6 (C2) + 0 + 6 (C4) + 0 + 8 (C6) + 0 = 40 < 70 ✓
    """
```

**Why the docstring, not a comment**: Docstrings survive code-search tools, code review, and automated doc extraction. A reviewer looking at a modified verifier can immediately evaluate whether the invariant still holds without running any code.

**The invariant to enforce**:

```
max_partial_total = sum of all partial_pts values across all criteria
                  (including per-entity partial × N for multi-entity criteria)

MUST satisfy: max_partial_total < pass_threshold
```

**When to re-audit**: Any time you:
- Add or remove a criterion
- Change a criterion's partial or full point value
- Change the pass threshold
- Change N (the number of entities required)

**Applies to**: Every verifier in every environment. The two-minute cost of writing the audit table prevents the multi-hour debugging session of discovering that partial-only agent behavior passes.

---

### 214. Adversarial "Not Doing Something" Criteria Need Activation Guards

**The Problem**: Some verifier criteria award points for the agent correctly *not* doing something — for example:
- "Did not tag the out-of-scope document" (+10 pts)
- "Did not grant access to the wrong user" (+15 pts)
- "Did not delete the record that should be kept" (+10 pts)

These are valuable "adversarial correctness" checks that prevent agents from blindly over-applying an operation. But in the do-nothing state (agent took no actions at all), every "not done" check trivially passes: the out-of-scope document was never tagged because *nothing was tagged*. The agent gets free points for inaction.

**Classic example**:
```python
# Criterion: correctly did NOT tag the out-of-scope Marketing document
decoy_tags = get_tags("Marketing-Campaign-Summary")
if "legal-hold" not in decoy_tags:
    score += 10
    details.append("PASS: Out-of-scope document correctly not tagged")
# In do-nothing state: decoy_tags = [] → "legal-hold" not in [] → True → 10 free points!
```

**The Fix**: Gate each negative criterion on at least one positive main-task action being confirmed first. Only evaluate "did not tag the decoy" if the agent has already tagged at least one in-scope document:

```python
# Count how many in-scope documents the agent actually tagged
inscope_tagged_count = 0
for doc_name in in_scope_docs:
    tags = get_tags(doc_name)
    if "legal-hold" in tags:
        score += 15
        inscope_tagged_count += 1

# Adversarial check: ONLY evaluated if agent started doing the main task
if inscope_tagged_count > 0:
    decoy_tags = get_tags("Marketing-Campaign-Summary")
    if "legal-hold" not in decoy_tags:
        score += 10
        details.append("PASS: Out-of-scope document correctly not tagged")
else:
    details.append("INFO: Adversarial check skipped — no in-scope docs tagged yet")
```

**Why this is different from Lesson 210 (seeded values pre-satisfying criteria)**: Lesson 210 is about the *seed data already being in the target state*. This lesson is about a criterion whose truth condition is permanently satisfied by the *absence of any action*. No seed data is involved.

**Why this is different from Lesson 134 (multi-state intermediate values)**: Lesson 134 is about setup placing an entity in an intermediate state that partially satisfies a criterion. Here the entity starts in a neutral state — it's the logical structure of "not X" that always evaluates to True when nothing has happened.

**Detection**: After writing any criterion of the form `if <thing> NOT in <state>: award_points`, ask: "Is this true before the agent does anything?" If yes, add an activation guard that checks a positive main-task action first.

**Applies to**: Any verifier with correctness/adversarial criteria that reward restraint — litigation hold tasks (don't over-tag), access control tasks (don't over-grant), data deletion tasks (don't over-delete), compliance tasks (don't modify the exempt document). Common in legal, security, compliance, and records management task domains.

---

### 215. REST API Collection-Write Operations May Replace Rather Than Append

**The Problem**: REST API endpoints that appear to add an item to a collection (named `AddACE`, `AddMember`, `AddTag`, `AddPermission`, `AddToGroup`, etc.) may silently *replace the entire collection* with the new item rather than appending. The operation name gives no indication of this behavior — it looks additive but is destructive.

**Classic example** (Nuxeo `Document.AddACE` via `@op`):
```bash
# Seed user A with Everything permission on Projects
curl -X POST ".../Projects/@op/Document.AddACE" \
    -d '{"params":{"user":"lnovak","permission":"Everything"}}'

# Seed user B with ReadWrite permission on Projects
curl -X POST ".../Projects/@op/Document.AddACE" \
    -d '{"params":{"user":"dpatel","permission":"ReadWrite"}}'

# Result: Projects local ACL now contains ONLY dpatel — lnovak was silently removed!
```

**Consequence in task design**: If setup_task.sh seeds N users/items on the same resource using N separate calls to such an endpoint, only the last call's data will be present. All prior calls are silently overwritten. Setup appears to succeed (each call returns HTTP 200/OK), but the resulting state contains only one of the intended N entries.

**How to detect this before writing setup scripts**: Make two test calls to the endpoint with different entities, then read back the collection state and verify both entities are present:
```bash
# Test whether endpoint appends or replaces:
curl -X POST ".../resource/@op/AddItem" -d '{"params":{"user":"alice"}}'
curl -X POST ".../resource/@op/AddItem" -d '{"params":{"user":"bob"}}'
curl -s ".../resource/@collection" | jq '.'
# If only "bob" appears → the operation replaces, not appends
# If both "alice" and "bob" appear → the operation appends
```

**The Fix**: If the endpoint replaces, restructure setup to either:
1. **One resource, one call**: Assign only one entity per resource so replace behavior is equivalent to a clean set. Design the task accordingly (one user per workspace, not multiple).
2. **Use a batch endpoint**: Many APIs have a bulk-assign endpoint that accepts a list — check the API docs for `SetACL`, `SetPermissions`, `BatchAddMembers`, etc.
3. **Use a different endpoint**: The `@acl` direct management endpoint may allow PUT with a full ACL list, bypassing the replace-per-call limitation.

**Why documentation often doesn't mention this**: Replace-on-write is a deliberate design choice by some APIs (atomic state transitions rather than delta operations), but it is rarely called out explicitly in method-level documentation. It only becomes apparent when you test with multiple sequential calls.

**Applies to**: Any `setup_task.sh` that uses a REST API to seed multi-entity collections — ACL/permission lists, group memberships, tag sets, watchlists, notification subscriptions, or any resource where multiple entries are managed through a single endpoint. Particularly common in enterprise content management (Nuxeo, Alfresco), IAM systems, and document management platforms.

---

### 216. The "Already-Handled Entity" Noise Pattern for Very Hard Multi-Entity Tasks

**The Pattern**: When a very hard task requires the agent to take action on a subset of N entities from a larger pool M (e.g., "prescribe for untreated hypertensive patients," "administer missing vaccines," "resolve medication conflicts"), seeding 1–2 entities that already satisfy the target condition — without needing any action — forces the agent to evaluate state before acting rather than apply operations blindly to all matching entities.

**Why this matters**: Without noise entities, an agent can succeed with a "find all matching, apply to all" heuristic — no genuine reasoning required. With noise entities already in the correct end-state (the medication already prescribed, the vaccine already given, the conflict already resolved), the agent must:
1. Inspect each entity's current state
2. Distinguish "needs action" from "already done"
3. Act selectively — and not double-act on already-handled entities

**How it differs from contamination injection**: Contamination injection seeds *wrong items* in a valid collection (agent must classify and remove them). The already-handled noise pattern seeds *correctly-resolved entities* in a pool that still needs remediation. The agent challenge is discrimination in the opposite direction: "who still needs this, vs. who already has it?"

**Implementation**:
```
Pool:           5 patients all have diagnosis I10
Noise (2):      pids 25, 26 — already have antihypertensive medication ← already correct
Targets (3):    pids 22, 23, 24 — no medication ← need action
```
The verifier only scores the 3 target pids. Noise pids are not scored (agent not penalized for acting on them, but not rewarded either — they're neutral checks against over-automation).

**Design guidance**:
- Noise entities should be 25–40% of the pool (1–2 out of 4–5): enough to require discrimination, not enough to obscure the task goal
- Choose noise states that are *plausibly already done* by a prior clinician/colleague/system — realistic professional context, not artificial "gotchas"
- Document noise entity status in task.json metadata and README so verifiers and test writers know which pids/records are targets vs. noise
- Verifiers must check only target entities — do not penalize the agent for doing the right thing on a noise entity that turned out not to need it
- Verifiers should never award points for correctly *skipping* noise entities (that would make the task gameable by skipping everything)

**When to use**: Any very_hard multi-entity task where the natural agent shortcut is "apply the action to all entities matching the diagnosis/role/status." Particularly valuable in: clinical EHR (patient panels), CRM (account portfolios), ticketing (issue queues), HR systems (employee cohorts), and inventory/catalog management.

**Applies to**: Any environment with a population of similar entities where a subset needs targeted intervention.

---

### 217. Inferring DB Schema from Existing Setup Scripts When the Environment Is Not Bootable

**The Problem**: When developing tasks for a database-backed environment (EHR, CRM, LMS, ITSM), you often need to know exact table names, column names, data types, and foreign key relationships to write correct INSERT/UPDATE/DELETE statements in `setup_task.sh`. Booting the environment just to run `DESCRIBE table_name` can be impractical — especially during initial development when the boot process is slow or the environment is unavailable.

**The Observation**: The existing `setup_task.sh` scripts for an environment contain the authoritative schema in the form of INSERT/UPDATE/DELETE statements. These statements were written and tested against the real running environment — they reflect the actual schema.

**How to extract the schema**:
```bash
# See all tables that existing tasks interact with
grep -rh "INSERT INTO\|UPDATE\|DELETE FROM" benchmarks/cua_world/environments/<env>/tasks/*/setup_task.sh | sort -u

# See exact column list for a specific table
grep -A5 "INSERT INTO \`demographics\`" benchmarks/cua_world/environments/<env>/tasks/*/setup_task.sh | head -20

# Find the primary key / unique identifier
grep "WHERE pid=" benchmarks/cua_world/environments/<env>/tasks/*/setup_task.sh | head -5

# Find foreign key patterns (provider_id, practice_id conventions)
grep -oh "provider_id.*[0-9]" benchmarks/cua_world/environments/<env>/tasks/*/setup_task.sh | head -5
```

**What this gives you**:
- Column names and exact order (from INSERT column lists)
- Data types implied by quoted vs. unquoted values
- Required vs. optional fields (columns always vs. sometimes present)
- Value format conventions (dates as `'YYYY-MM-DD'`, booleans as `'y'`/`'n'`, etc.)
- Foreign key values actually used (provider_id=2, practice_id=2 in most NOSH tasks)

**Caveats**:
- Application updates may change the schema after existing tasks were written — if the app has been updated, validate critical columns against the actual DB before finalizing new tasks
- Column order in INSERT statements must match the column list exactly — do not assume alphabetical or intuitive ordering
- If existing tasks use a helper function (`nosh_query`, `omrs_insert`, etc.) that wraps the raw SQL, read the helper source to understand the actual statement structure

**Rule**: Before writing any INSERT/UPDATE/DELETE in a new setup script, grep existing setup scripts for the same table. If the table appears in 3+ existing scripts, the schema is well-validated and you can trust it. If it appears in only 1, double-check with a live environment before deploying.

---

### 218. Derive Offline Verifier Test Data from Live Export Output, Not from the Verifier Code

**The Problem**: When building offline test fixtures for a verifier (using mock `copy_from_env`, as described in `13_file_content_verification_and_offline_testing.md` Gap 2), it is tempting to construct the mock JSON by reading the verifier's `result.get(...)` calls and supplying those keys. This produces mock data that matches the verifier but not necessarily the real export — and the bug is invisible: both the do-nothing test and the full-completion test return the "right" score for the wrong reason.

**Concrete example**: The verifier reads `result.get("employees", [])`. You pass `{"employees": [...]}` in your mock. The export script actually writes `{"target_employees": [...]}`. The verifier silently gets `[]` on a live run and returns score=0 for every scenario — but your offline tests all passed. You only discover this after deploying.

**The Fix**: Run the export script at least once on the live environment (in the do-nothing state, immediately after setup) and capture the actual JSON output. Use that exact output as the basis for all mock fixtures:

```bash
# After running setup, run export and capture JSON
sudo bash /workspace/tasks/<task_name>/export_result.sh
cat /tmp/<task_name>_result.json   # <-- this is your mock template
```

Then copy-paste that JSON as the basis for your offline test's do-nothing fixture. For partial and full-completion tests, modify only the fields the agent is expected to change.

**Why this matters**: The export script is the contract between the VM and the verifier. It is the only authoritative source of the result structure. The verifier code tells you what the *intended* structure is, but only the export output tells you what is *actually* produced.

**Rule**: Never write an offline test fixture without first running the export script on a live environment and reading its actual output. If a live environment is unavailable, at minimum read `export_result.sh` line by line and trace every key that is written to the result dict — then verify each key name exactly matches what the verifier reads.

---

### 219. Verify Browser Pre-Positioning URLs by Clicking Through the UI

**The Problem**: Setup scripts for browser-based environments call a function like `ensure_firefox` or `navigate_to` to pre-position the browser at a specific page before the agent starts. The URL passed to this function is often copied from documentation, example tasks, or reasonable inference — without actually verifying it opens the correct page in the specific running installation.

URL formats are not stable across versions or installations of the same application:
- A path-style URL (`/app/employees`) introduced in version N may not exist in all version-N installations (e.g., if a prerequisite module is missing or the routing config differs).
- An XML-ID fragment URL (`#action=module.xml_id`) resolves to a numeric action ID at runtime; that ID is correct only if the XML ID is registered in the specific database being used.
- Even the same version can produce different URLs depending on installed modules, company configuration, or database state.

**Concrete example**: Odoo 17 introduced `/odoo/employees` as the path for the employee list. The specific Odoo 17 installation used for testing returned a 404 for that URL; the correct URL for that installation was still the legacy hash-based format `#action=hr.open_view_employee_list_my`.

**The Fix**: Before finalizing any `ensure_firefox` URL in a setup script, verify it manually:
1. Connect to the running environment (VNC, SSH with X forwarding, or the `visual_grounding` tool).
2. Click through the application UI to reach the desired starting page.
3. Copy the URL from the browser's address bar.
4. Use that exact URL in the setup script.

```bash
# Good: URL copied from address bar after clicking to Employees list
ensure_firefox "http://localhost:8069/web#action=202&cids=1"

# Risky: URL inferred from documentation or other environment's task
ensure_firefox "http://localhost:8069/odoo/employees"   # may 404
```

**Additional check**: After running the setup script once, copy the screenshot it takes to local and inspect it with the `visual_grounding` tool. Confirm the browser shows the intended starting page, not an error or a redirect to the app's default page (login, dashboard, inbox, etc.).

**Rule**: Never hard-code a browser navigation URL in a setup script without first verifying it by navigating there manually in the live environment and reading the resulting address bar URL.


**Applies to**: Any environment with a relational database backend — MySQL/MariaDB (NOSH, OpenEMR), PostgreSQL (OpenMRS, Odoo), SQLite, or any system accessed via shell commands in setup scripts.

---

### 220. Never Hardcode Auto-Incremented FK/PK IDs in Setup or Export Scripts

**The Problem**: Relational databases assign integer primary keys (and therefore foreign keys that reference them) by auto-increment. The same logical record — a department named "Engineering", a job title named "Software Engineer", a leave type named "Annual Leave" — may have ID=3 in one environment build and ID=7 in another, depending on insertion order during initial seeding.

If `setup_task.sh` or `export_result.sh` hardcodes these integers, tasks break silently when the environment is rebuilt or migrated:

```bash
# BAD: hardcoded department ID that may differ between builds
orangehrm_db_query "UPDATE hs_hr_employee SET work_unit=4 WHERE employee_id='EMP009'"
# If the Engineering dept was assigned ID=7 in this build, this assigns the wrong dept
```

**The Fix**: Always resolve integer IDs at runtime by querying with a stable natural key (name, code, slug, or any other unique non-generated column):

```bash
# GOOD: resolve at runtime using the stable name or code column
ENG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_subunit WHERE unit_id='ENG'" | tr -d '[:space:]')
orangehrm_db_query "UPDATE hs_hr_employee SET work_unit=${ENG_ID} WHERE employee_id='EMP009'"
```

**How to identify the stable natural key**: Inspect the table for columns that are:
- Not `AUTO_INCREMENT` (check with `SHOW CREATE TABLE tablename`)
- Unique and human-meaningful (department code, product SKU, leave type name)
- Set by the application installer, not by seeding order

**Applies to**: Any setup or export script that writes to or reads from a relational database table with auto-incremented PKs. Common examples: department/subunit IDs, job title IDs, leave type IDs, user group IDs, product category IDs. Does not apply to natural-key tables where the name itself is the PK (e.g., a `code` column used as PK).

**Implementation pattern for export scripts**: When the export result must record a human-readable value (e.g., department name), JOIN against the referenced table rather than embedding an assumed name:

```bash
# BAD: assumes the ID maps to a known name
DEPT_ID=$(db_query "SELECT work_unit FROM hs_hr_employee WHERE employee_id='EMP009'")
# Hard to know if DEPT_ID=4 means Engineering without another lookup

# GOOD: JOIN to get the human-readable name directly
DEPT_NAME=$(db_query "SELECT s.name FROM hs_hr_employee e
  JOIN ohrm_subunit s ON e.work_unit=s.id
  WHERE e.employee_id='EMP009'")
echo "\"emp009_dept\": \"${DEPT_NAME}\"" >> /tmp/result.json
# Verifier can now do: data["emp009_dept"].lower() == "engineering"
```

---

### 221. Boolean Values from Bash Are Strings — Verifiers Must Accept Both Forms

**The Problem**: Bash cannot produce JSON boolean literals (`true`, `false`) natively. When an export script writes a boolean-like condition to JSON via `if/then/else echo`, the result is the *string* `"true"` or `"false"`:

```bash
# In export_result.sh — this writes the string "true", not JSON true
if mysql ...; then DEVOPS_EXISTS="true"; else DEVOPS_EXISTS="false"; fi
cat > /tmp/result.json << EOF
{
  "devops_engineer_exists": "${DEVOPS_EXISTS}"
}
EOF
# Produces: {"devops_engineer_exists": "true"}  ← string, not boolean
```

Python's `json.load` reads `"true"` as the string `"true"`, not the Python boolean `True`. A verifier that tests `data.get("devops_engineer_exists") is True` will always fail, even when the agent created the job title.

**The Fix**: Verifiers must accept both forms for any field that export scripts write as an if/else echo:

```python
# BAD: only accepts the Python boolean True
if data.get("devops_engineer_exists") is True:
    score += 25

# GOOD: accepts both the Python bool and the bash-produced string
devops_exists = data.get("devops_engineer_exists", False)
if devops_exists is True or str(devops_exists).lower() == "true":
    score += 25
```

**Alternative fix in the export script**: Use Python inline to write proper JSON booleans rather than bash string substitution:

```bash
# In export_result.sh — use Python to produce real JSON booleans
DEVOPS_COUNT=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e \
  "SELECT COUNT(*) FROM ohrm_job_title WHERE job_title='DevOps Engineer' AND is_deleted=0")
python3 - << PYEOF
import json
result = {"devops_engineer_exists": int("${DEVOPS_COUNT}") > 0}  # real bool
with open("/tmp/result.json", "w") as f:
    json.dump(result, f)
PYEOF
```

**Rule of thumb**: Prefer the Python-in-bash approach when writing more than 2-3 boolean fields — the result is proper JSON with no type ambiguity. Use the dual-form verifier check as a defensive fallback whenever the export script uses bash if/else string assignment.

**Applies to**: Any task in any environment where `export_result.sh` uses bash conditionals to set boolean fields. This includes every Linux/Mac desktop environment that writes result JSON via shell scripts rather than a dedicated JSON-aware tool.

---

### 236. Entity Attribute Differentiation in Multi-Entity Tasks

**The Problem**: When a task requires creating multiple entities of the same type (e.g., 4 user accounts, 5 database records, 3 configuration entries), a common design produces entities that are structurally identical — only the name changes. The agent can solve this by repeating the exact same workflow N times, which tests mechanical stamina but not comprehension.

**The Better Pattern**: Vary a critical attribute across entities so the agent must read and apply different values per entity. This transforms a repetitive task into one that tests whether the agent tracks per-entity requirements.

**Example — weak design (homogeneous)**:
```
Create 4 user accounts: alice, bob, carol, dave. All with role EXAM_ADMIN, all active.
```
Agent strategy: repeat the same form fill 4 times, changing only the username.

**Example — strong design (differentiated)**:
```
Create 4 user accounts:
  alice  → EXAM_ADMIN
  bob    → EXAM_ADMIN
  carol  → EXAM_SUPPORTER  (different role)
  dave   → INSTITUTIONAL_ADMIN  (different role)
```
Agent strategy: must read each entity's required role and select the correct value from a dropdown — cannot blindly repeat the same action.

**Verification advantage**: The verifier can check per-entity attribute correctness, creating a natural partial-credit gradient. An agent that assigns all entities the same attribute (the "lazy repeat" shortcut) scores partial on the count criterion but fails the differentiation criterion.

**Design checklist**:
1. Identify which attribute varies across entities (role, category, status, priority, type)
2. Use at least 3 distinct values across N entities (not just 2 — binary variation is too easy)
3. Include at least one "minority" entity whose attribute differs from the majority (tests whether agent defaults to the most common value)
4. Verify each entity's attribute independently, not just the count

**Scoring pattern**:
```python
# Separate criteria: entity existence (count) vs. entity correctness (attribute)
# C1: all N entities exist → X pts (partial for fewer)
# C2: each entity has correct attribute → Y pts (partial for some correct)
```

This separation means an agent that creates all entities with the wrong attributes scores C1 but fails C2, producing a meaningful partial score that reflects what was actually done.

**Applies to**: Any task requiring creation or modification of 3+ entities of the same type — user provisioning, record creation, product catalog entry, configuration profiles, appointment scheduling, inventory entries. The differentiation attribute can be any field that has multiple valid values in the application's domain.

---

### 237. Deliberate Omission as a Correctness Criterion

**The Problem**: Nearly all task designs test whether the agent *did* something — created a record, filled a field, enabled a setting. But some professional workflows require the agent to deliberately *not* do something: not enable a feature, not check a checkbox, not fill an optional field. This "correctness by restraint" pattern is a powerful difficulty lever that most task designs miss.

**Why it's hard for agents**: Agents have an action bias — they tend to fill in every visible field and enable every available option. A task that requires leaving a setting at its default (or explicitly disabled) state tests whether the agent understands the *why* behind configuration choices, not just the *how*.

**Example**: A GDPR compliance task requires creating a connection configuration. The UI offers a "fallback URL" field. A naïve agent fills it in (more configuration = more complete, right?). But GDPR data minimisation requires *not* enabling fallback — fewer data transfer paths. The agent must understand that leaving the field empty is the correct action.

**How to verify omission**: The verifier checks that the relevant field/setting is empty, null, disabled, or at its default value. This is straightforward — but you must guard against the do-nothing false positive (Anti-Pattern 9 in `14_task_design_antipatterns.md`).

**Critical safeguard**: An omission criterion must always be paired with a positive-action criterion on the *same entity*. If the entity doesn't exist at all, the omission check is vacuously true (field is empty because the record was never created). Gate the omission check behind entity existence:

```python
# WRONG: omission check without gate
fallback_empty = result.get('fallback_url', '') == ''
if fallback_empty:
    score += 10  # Do-nothing agent gets free points!

# RIGHT: omission check gated on entity existence
config_exists = result.get('config_id') is not None
fallback_empty = result.get('fallback_url', '') == ''
if config_exists and fallback_empty:
    score += 10  # Only awards points if agent created the config AND left fallback empty
```

**Design pattern**:
1. The task description states a domain requirement that implies restraint (security policy, compliance rule, minimalism principle)
2. The application UI offers an optional feature that conflicts with that requirement
3. The agent must create the entity but deliberately skip or disable the conflicting option
4. The verifier checks: entity exists (positive) AND conflicting option is absent (omission)

**When to use**: Tasks involving security hardening, compliance (GDPR, HIPAA, SOX), minimalist configurations, access control (don't grant excessive permissions), or any domain where "less is more." The pattern naturally elevates difficulty because it requires domain reasoning, not just UI navigation.

**Applies to**: Any environment where the application offers optional settings, toggles, or fields that an agent might fill in by default. Web admin panels, configuration management tools, EHR systems (don't order unnecessary tests), financial software (don't enable risky trading options), and infrastructure tools (don't open unnecessary ports) all have natural omission criteria.

---

### 238. Live Do-Nothing Tests Validate the Full Pipeline, Not Just the Verifier

**The Problem**: Lesson 180 correctly states that offline verifier tests are sufficient for validating *scoring logic*. But offline tests mock `copy_from_env` with hand-crafted JSON — they cannot validate that `setup_task.sh` produces the correct baseline state, that `export_result.sh` generates valid JSON with the right field names and data types against the real database schema, or that the three scripts compose correctly end-to-end. These pipeline integration bugs are common and only manifest in the live environment.

**Real examples of bugs that offline tests cannot catch**:
- SQL query uses a column name that doesn't exist in the actual database schema (export script silently produces empty results)
- `setup_task.sh` seeds data with wrong date format for the application's locale, causing the application to reject it
- Export script's `LIKE '%KEYWORD%'` query matches pre-existing data from the environment's demo dataset, producing false positives in the baseline
- Bash variable interpolation in the export script's JSON heredoc breaks when a database value contains special characters
- Firefox launch in `setup_task.sh` fails because the snap/native detection logic doesn't match the VM's actual Firefox installation

**The recommendation**: Run a live do-nothing test for **every** task, not just the first one. The pattern from Lesson 29 (one VM boot for all tasks) makes this efficient — after the initial ~100s boot, each additional task's setup+export+verify cycle takes only ~10-20s.

**Minimal live do-nothing test**:
```python
env = from_config('benchmarks/cua_world/environments/<env_name>', task_id='<task_name>')
obs = env.reset(seed=42, use_cache=True, cache_level='pre_start', use_savevm=True)
obs2, reward, done, info = env.step([], mark_done=True)
vr = info.get('verifier', {})
assert vr.get('passed') is False, f"Do-nothing should fail but got: {vr}"
print(f"Score: {vr.get('score')}, Feedback: {vr.get('feedback')}")
env.close()
```

**What to check in the output**:
1. `passed` is `False` — the do-nothing invariant holds
2. `score` matches your expected do-nothing score (0 for clean-slate tasks, > 0 for contamination-injection tasks where seeded state satisfies some criteria)
3. `feedback` mentions every criterion by name — confirms all criteria are being evaluated, not short-circuiting
4. No Python tracebacks or JSON parse errors in the log output — confirms export script produced valid JSON

**Relationship to Lesson 180**: Lesson 180 is about verifier *logic* testing — that is correctly scoped to offline. This lesson is about *pipeline integration* testing — that requires the live environment. Both are necessary; they test different things. Do offline first (fast, deterministic), then live (slower, catches integration bugs).

**Applies to**: Every task in every environment. The cost is low (~2 minutes per task with cached checkpoints) and the failure modes it catches — schema mismatches, SQL errors, bash escaping, file path issues — are among the most common task creation bugs.
