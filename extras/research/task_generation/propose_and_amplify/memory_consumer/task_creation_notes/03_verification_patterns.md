> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Verification Patterns for Robust Tasks

## Overview

Verification is the most critical part of task design. A weak verifier allows agents to game the task; a strong verifier ensures meaningful evaluation. This document provides patterns for creating adversarial-proof verification.

---

## The Verification Pipeline

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Agent Finishes │ ──> │  export_result  │ ──> │   verifier.py   │
│     Task        │     │     .sh         │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │                        │
                               │                        │
                               v                        v
                        /tmp/result.json         {"passed": bool,
                        (inside VM)               "score": int,
                                                  "feedback": str}
```

**Key insight**: The export script runs IN the VM with full access. The verifier runs OUTSIDE with only the exported JSON.

---

## Pattern 1: Baseline Recording

**Problem**: Pre-existing data can be claimed as task completion.

**Solution**: Record initial state and verify CHANGES.

### In setup_task.sh:
```bash
# Record initial counts
INITIAL_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM appointments WHERE pid=3")
echo "$INITIAL_APPT_COUNT" > /tmp/initial_appt_count

# Record which specific records exist (for more granular checking)
openemr_query "SELECT id FROM appointments WHERE pid=3" > /tmp/initial_appt_ids

# Record timestamp
date +%s > /tmp/task_start_timestamp
```

### In export_result.sh:
```bash
# Compare against baseline
INITIAL_COUNT=$(cat /tmp/initial_appt_count)
CURRENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM appointments WHERE pid=3")
NEW_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))

echo "New appointments created: $NEW_COUNT"
```

### In verifier.py:
```python
# Verify NEW work was done
initial = result.get('initial_count', 0)
current = result.get('current_count', 0)

if current <= initial:
    return {"passed": False, "score": 0, "feedback": "No new records created"}

# Award points for new work
score += 20
```

---

## Pattern 2: Wrong-Target Rejection

**Problem**: Agent might complete the task for the wrong entity (wrong patient, wrong file).

**Solution**: Critical fail (score=0) if wrong target.

### In task.json metadata:
```json
{
  "metadata": {
    "patient_pid": 3,
    "patient_fname": "Jayson",
    "patient_lname": "Fadel"
  }
}
```

### In verifier.py:
```python
def verify_task(traj, env_info, task_info):
    # Get expected target from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid')

    # Copy and parse result
    # ...

    # CRITICAL CHECK: Right target?
    actual_pid = result.get('patient_pid')
    if actual_pid != expected_pid:
        return {
            "passed": False,
            "score": 0,  # ZERO points for wrong target
            "feedback": f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got pid={actual_pid}"
        }

    # Continue with other checks only if correct target
    # ...
```

**Important**: This check should come FIRST, before any points are awarded.

---

## Pattern 3: Multi-Criterion Scoring

**Problem**: Single pass/fail doesn't capture partial progress.

**Solution**: Break verification into weighted criteria — one per independent subtask.

For a genuinely hard task, each criterion should correspond to a meaningfully distinct subtask (not just different fields of the same single action). The scoring structure should reflect the breadth of what was required:

```python
def verify_task(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    # CRITICAL: Wrong target = immediate zero (before any points)
    if result.get('target_id') != expected_id:
        return {"passed": False, "score": 0, "feedback": "Wrong target"}

    # Subtask 1: [First independent requirement] (N points)
    if result.get('subtask_1_complete'):
        score += N
        subscores["subtask_1"] = True
        feedback_parts.append("Subtask 1 complete")

    # Subtask 2: [Second independent requirement] (N points)
    if result.get('subtask_2_complete'):
        score += N
        subscores["subtask_2"] = True
        feedback_parts.append("Subtask 2 complete")

    # Subtask 3: [Third independent requirement] (N points)
    # ...

    # Pass requires completing the majority of subtasks
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No subtasks completed",
        "subscores": subscores
    }
```

**Note on scoring design**: If all your criteria are about a single action (correct drug name, correct dose, correct quantity — all describing the same prescription), that is still a single-action task regardless of how many criteria you add. Each criterion should verify a *different* thing the agent had to do.

---

## Pattern 4: Value Range Validation

**Problem**: Agents might enter unrealistic values that technically "complete" the task.

**Solution**: Validate values are within realistic ranges.

### Examples:
```python
# Blood pressure validation
bp_systolic = result.get('bp_systolic', 0)
bp_diastolic = result.get('bp_diastolic', 0)

if 70 <= bp_systolic <= 200 and 40 <= bp_diastolic <= 130:
    score += 15
    feedback_parts.append(f"Valid BP: {bp_systolic}/{bp_diastolic}")
else:
    feedback_parts.append(f"Invalid BP values: {bp_systolic}/{bp_diastolic}")

# Temperature validation (in Fahrenheit)
temp = result.get('temperature', 0)
if 95.0 <= temp <= 105.0:
    score += 10
    feedback_parts.append(f"Valid temp: {temp}°F")

# Date validation (within acceptable range)
appt_date = result.get('appointment_date', '')
today = datetime.now().date()
max_date = today + timedelta(days=14)

if today <= parse_date(appt_date) <= max_date:
    score += 15
    feedback_parts.append(f"Valid date: {appt_date}")
```

---

## Pattern 5: Text/Keyword Matching

**Problem**: Need to verify free-text fields contain relevant content.

**Solution**: Use flexible pattern matching with multiple accepted terms.

### Example:
```python
# Check if reason mentions hypertension follow-up
reason = result.get('reason', '').lower()
title = result.get('title', '').lower()
combined = f"{reason} {title}"

# Multiple valid keywords
hypertension_terms = ['hypertension', 'htn', 'blood pressure', 'bp']
followup_terms = ['follow-up', 'followup', 'follow up', 'f/u', 'recheck']

has_hypertension = any(term in combined for term in hypertension_terms)
has_followup = any(term in combined for term in followup_terms)

if has_hypertension or has_followup:
    score += 15
    feedback_parts.append("Appropriate reason documented")
else:
    feedback_parts.append("Reason doesn't indicate hypertension follow-up")
```

---

## Pattern 6: File Existence and Content Verification

**Problem**: Task requires creating a file with specific content.

**Solution**: Check existence, size, and content patterns.

### In export_result.sh:
```bash
OUTPUT_FILE="/home/ga/Desktop/patient_summary.txt"

FILE_EXISTS="false"
FILE_LENGTH=0
HAS_PATIENT_NAME="false"
HAS_DOB="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_LENGTH=$(wc -c < "$OUTPUT_FILE")

    # Check for required content
    if grep -qi "Mariana.*Hane\|Hane.*Mariana" "$OUTPUT_FILE"; then
        HAS_PATIENT_NAME="true"
    fi

    if grep -qE "1978.?06.?24|June.*24.*1978" "$OUTPUT_FILE"; then
        HAS_DOB="true"
    fi
fi

cat > /tmp/result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_length": $FILE_LENGTH,
    "has_patient_name": $HAS_PATIENT_NAME,
    "has_dob": $HAS_DOB
}
EOF
```

### In verifier.py:
```python
# File must exist
if not result.get('file_exists'):
    return {"passed": False, "score": 0, "feedback": "Output file not created"}

# File must be substantial
if result.get('file_length', 0) < 500:
    feedback_parts.append(f"File too short: {result['file_length']} chars")
else:
    score += 15

# Must contain required info
if result.get('has_patient_name'):
    score += 20
if result.get('has_dob'):
    score += 15
```

---

## Pattern 7: Database Query Verification

**Problem**: Need to verify specific database state.

**Solution**: Query for exact expected values.

### In export_result.sh:
```bash
# Query for specific medication in specific patient
MED_CHECK=$(openemr_query "
    SELECT id, drug, dosage
    FROM prescriptions
    WHERE patient_id=7
    AND drug LIKE '%amox%'
    ORDER BY id DESC
    LIMIT 1
")

if [ -n "$MED_CHECK" ]; then
    MED_ID=$(echo "$MED_CHECK" | cut -f1)
    MED_DRUG=$(echo "$MED_CHECK" | cut -f2)
    MED_DOSE=$(echo "$MED_CHECK" | cut -f3)
    MED_FOUND="true"
else
    MED_ID=""
    MED_DRUG=""
    MED_DOSE=""
    MED_FOUND="false"
fi
```

---

## Anti-Pattern: What NOT to Do

### ❌ Checking only for existence:
```python
# BAD: Pre-existing data passes
result = query("SELECT * FROM prescriptions")
return len(result) > 0
```

### ❌ No target validation:
```python
# BAD: Any patient works
result = query("SELECT * FROM prescriptions ORDER BY id DESC LIMIT 1")
return result is not None
```

### ❌ Single criterion:
```python
# BAD: No partial credit, easy to game
if record_exists:
    return {"passed": True, "score": 100}
else:
    return {"passed": False, "score": 0}
```

### ❌ Vague text matching:
```python
# BAD: Too permissive
if 'medication' in result.lower():
    return {"passed": True}
```

---

## Verification Testing Checklist

Before finalizing a verifier, test these scenarios:

| Scenario | Expected Result |
|----------|-----------------|
| Agent does nothing | Score: 0, Passed: False |
| Agent completes wrong target | Score: 0, Passed: False |
| Agent partially completes | Score: 20-50, Passed: False |
| Agent completes with wrong values | Score: varies, Passed: False |
| Agent fully completes correctly | Score: 80-100, Passed: True |

Test do-nothing and partial scenarios by direct DB/file manipulation rather than by manually completing the task. The full-completion scenario does NOT need to be tested by the task creator — see `06_task_creation_checklist.md` Phase 5.

---

## Pattern 8: Independent File Re-Analysis (Anti-Tamper)

**Problem**: The export script runs inside the VM and could be manipulated by a clever agent. If the verifier only trusts the JSON from `export_result.sh`, an agent could edit the export script to report fake results.

**Solution**: Have the verifier independently copy the output file from the VM and re-parse it, rather than relying solely on the export JSON.

### In verifier.py:
```python
def verify_task(traj, env_info, task_info):
    score = 0
    # Step 1: Get export JSON (used as initial signal)
    result = parse_export_json(...)

    # Step 2: INDEPENDENTLY copy and re-analyze the actual output file
    try:
        copy_from_env("/home/ga/output.xml", "/tmp/local_copy.xml")
        tree = ET.parse("/tmp/local_copy.xml")
        root = tree.getroot()
        # Perform independent structural analysis on YOUR copy
        sections = root.findall(".//Section")
        entries = root.findall(".//Entry")
        # Award points based on YOUR parsing, not the export JSON
        if len(sections) >= 5:
            score += 15
    except Exception as e:
        # Fall back to export JSON if file copy fails
        logger.warning(f"Independent analysis failed: {e}")
```

**Why**: This creates a two-layer verification. The export JSON provides a quick summary; the independent re-analysis catches any discrepancy. Especially important for desktop applications where output is a file (XML, CSV, config, project file) rather than a database record.

---

## Pattern 9: Structural Complexity Gates

**Problem**: For "build from scratch" tasks (no pre-existing data), an agent could create a minimal file that passes basic existence checks. A near-empty config or project file technically "exists" but doesn't represent meaningful work.

**Solution**: Require minimum structural complexity thresholds that are impossible to meet without genuine effort.

### In verifier.py:
```python
# Minimum complexity gates for a "build from scratch" task
content = open(output_file).read()
line_count = len(content.splitlines())
file_size = os.path.getsize(output_file)

# For structured files (XML, JSON, YAML): count meaningful elements
# Adapt element names to whatever format your app uses
if output_file.endswith('.xml'):
    tree = ET.parse(output_file)
    section_count = len(tree.findall('.//Section'))
    element_count = len(tree.findall('.//*'))
elif output_file.endswith('.json'):
    data = json.load(open(output_file))
    element_count = len(str(data))  # rough proxy

complexity_ok = (
    line_count >= 50 and      # Substantial file
    element_count >= 20 and   # Non-trivial structure
    file_size >= 2000         # Not a stub
)

if complexity_ok:
    score += 10  # "Structural complexity" criterion
else:
    feedback_parts.append(f"Insufficient complexity: {line_count} lines, {element_count} elements")
```

**When to use**: Any task where the agent creates a structured file from scratch (project files, configurations, documents, spreadsheets). Not needed for tasks that modify existing records.

---

## Pattern 10: Multi-File Cross-Referencing

**Problem**: Some tasks require the agent to produce multiple output files that must be internally consistent (e.g., a project file that references a data CSV, a config that references a template, a build script that references source files).

**Solution**: Verify both files exist AND cross-reference their contents.

### In verifier.py:
```python
# Example: project file references a data file
import json, csv, os

# Parse the main project file
with open(project_file) as f:
    project = json.load(f)

data_ref = project.get("data_source", "")

# The referenced filename must match the actual data file
data_filename = os.path.basename(data_file)
if data_filename in data_ref:
    score += 10  # Cross-reference check passes
else:
    feedback_parts.append(
        f"Project references '{data_ref}' but data file is '{data_filename}'"
    )

# Also validate the data file content independently
with open(data_file) as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    required_columns = {'id', 'value', 'category'}
    if required_columns.issubset(set(reader.fieldnames or [])):
        score += 10
```

**When to use**: Any task that produces multiple related output files. Check that references between files are consistent, not just that each file individually looks correct. Common examples: config + data, template + content, script + input file.

---

## Pattern 11: Output File Size as an Analytical Completeness Signal

**Problem**: For tasks where the agent produces a free-form text or HTML output file (analysis reports, investigation summaries, exported logs), verifying that specific keywords appear is necessary but not sufficient. An agent can write a file with a few keywords but produce a trivially incomplete analysis. A one-line HTML file with the word "Frequency" passes keyword checks but represents minimal work.

**Solution**: Add a minimum file size criterion that acts as a proxy for analytical completeness. Different size thresholds correspond to different expected levels of work:

| Output type | Minimal output | Comprehensive output |
|------------|---------------|---------------------|
| Single-command analysis (1 FREQ) | ~1-3 KB | — |
| Multi-command report (5-10 commands) | ~5-10 KB | >10 KB |
| Comprehensive investigation (20+ commands) | ~15-20 KB | >20-30 KB |
| Full outbreak/surveillance report | ~30+ KB | >50 KB |

### In export_result.ps1 (Windows):
```powershell
$fi = Get-Item "C:\Users\Docker\analysis_report.html"
$result["html_size_bytes"] = [long]$fi.Length
```

### In verifier.py:
```python
# Tiered size check: full credit for comprehensive, partial for adequate
size = result.get('html_output', {}).get('size_bytes', 0)
if size > 20000:
    score += 10
    feedback_parts.append(f"Report is comprehensive ({size} bytes).")
elif size > 5000:
    score += 5
    feedback_parts.append(f"Report is moderate size ({size} bytes); expected >20KB for complete analysis.")
else:
    feedback_parts.append(f"Report is too small ({size} bytes) — analysis appears incomplete.")
```

**Important caveats**:
- Size is a *proxy*, not a direct measure of quality. Use it in combination with keyword checks — never alone.
- Set thresholds based on what a reasonable correct output would produce, not arbitrarily. Run the analysis yourself or estimate based on command count × typical output size per command.
- Do NOT make size a mandatory pass condition (don't score=0 if file is small). It should be one criterion among several.
- Different file types have different size profiles: HTML output from GUI analysis tools is verbose (tags add overhead); plain-text CSVs are compact. Calibrate accordingly.

**When to use**: Any task where the agent produces a report, analysis HTML, or log file by running a sequence of commands. Particularly effective for analysis software (Epi Info Classic Analysis, SPSS, SAS, statistical tools) where running more commands directly produces more output bytes.

---

## Pattern 12: Content Volume Gate

**Purpose**: For tasks that require agents to *build* a minimum quantity of items (slides, records, pages, entries, shapes), enforce that minimum as a **blocking gate** before awarding any score for secondary quality criteria. This prevents an agent from gaming secondary criteria (charts, notes, text quality) without performing the primary construction work.

**The problem without a gate**: Suppose a task requires 12 slides, 3 charts, and speaker notes, and the starting file already has 5 slides. An agent that only adds charts and notes (without reaching 12 slides) could accumulate enough points to pass:
```
5 slides (below minimum) →  0 pts
3 charts                  → 30 pts
notes on 5 slides         → 10 pts
PDF export                → 10 pts
                            50 pts  ← passes if threshold is 45!
```
The gate collapses this exploit: if slides < minimum_qualifying_count → return score 0 immediately.

**The gate threshold is NOT the same as the full-credit threshold**: Set the blocking gate at a value meaningfully above the starting-file count but below the full-credit requirement. This allows agents that made genuine partial progress to still receive partial credit on other dimensions, while blocking trivial do-nothing submissions.

```
Starting file has N items  →  gate at ~1.5–2× N  (or halfway to full-credit target)
Full-credit target is M    →  gate at ceil(M * 0.6) or at N + buffer
```

Example for a 12-slide target starting from a 5-slide stub:
- Gate: `slide_count < 8` (blocks stub-unchanged submissions)
- Full credit: `slide_count >= 12`
- Partial credit: `slide_count >= 9`

### Implementation pattern

```python
# GATE: Minimum content volume before any other criteria are scored.
# Prevents scoring secondary quality criteria (charts, notes, formatting)
# when the agent has not performed the primary construction work.
volume_count = metrics["slide_count"]  # or record_count, page_count, etc.
min_qualifying = metadata.get('min_qualifying_items', 8)

if volume_count < min_qualifying:
    return {
        "passed": False,
        "score": 0,
        "feedback": (
            f"GATE FAIL: Only {volume_count} item(s) — minimum {min_qualifying} required "
            "to qualify for scoring. Complete the primary construction task first."
        ),
        "debug": {"volume_count": volume_count},
    }

score = 0
# ... rest of scoring proceeds only if gate passed
```

**When to apply**: Any task whose description contains phrases like:
- "expand this N-slide draft into a complete M-slide presentation"
- "add X more records/entries to reach at least Y total"
- "build a complete document from the provided stub"
- "extend the baseline to cover all required sections"

**When NOT to apply**: Repair/fix tasks (the starting file already has the correct structure), pure content-accuracy tasks (the number of items is fixed and correct), or analysis tasks (the agent interprets data rather than producing items).

---

## Pattern 13: ZIP-based Office Format Parsing

**Purpose**: For tasks whose output is a ZIP-based document format (ODP, PPTX, DOCX, XLSX, ODT, ODS), prefer direct `zipfile + regex/string-search` parsing over third-party library parsing (odfpy, python-pptx, openpyxl). This gives more reliable and transparent detection of embedded objects, charts, transitions, notes, and structural elements.

**Why libraries fail for verification**:
- Libraries parse to object models that may silently omit or merge embedded OLE objects (e.g., charts stored in `Object N/` subdirectories within the ZIP).
- Library APIs differ by version; a library installed in the host verifier environment may differ from the version inside the VM.
- Libraries raise exceptions on files with minor non-conformance, causing entire verifications to fail silently.
- Regex/string search on raw XML is deterministic and version-independent.

### ODP/PPTX internal structure cheat sheet

| What to detect | Where in the ZIP | How to detect |
|----------------|-----------------|---------------|
| Slide count (ODP) | `content.xml` | Count `<draw:page ` occurrences |
| Embedded charts (ODP) | `Object N/content.xml` (for each N) | Look for `chart:chart` in file content |
| Embedded charts (PPTX) | `ppt/charts/chart*.xml` | File existence (one file per chart) |
| Speaker notes (ODP) | Inside each `<draw:page>` block | Find `<presentation:notes>`, strip XML tags, check text length |
| Speaker notes (PPTX) | `ppt/notesSlides/notesSlide*.xml` | Find `<a:t>` tags, check combined text length |
| Slide transitions (ODP) | `<draw:page>` attributes | `presentation:transition-style=` attribute or `<presentation:transition` child |
| Slide transitions (PPTX) | `ppt/slides/slide*.xml` | `<p:transition` element |
| Shapes on a slide (ODP) | `<draw:page>` section | Count `draw:custom-shape`, `draw:connector`, `draw:rect`, `draw:ellipse`, `draw:polygon`, `draw:path`, `draw:line` tags; exclude `<presentation:notes>` section first |
| Text content | `content.xml` | Strip XML tags with `re.sub(r'<[^>]+>', ' ', xml)` |

### Implementation skeleton

```python
import zipfile, re

def _parse_odp(odp_path: str) -> dict:
    metrics = {"slide_count": 0, "chart_count": 0, "notes_slides": 0, "error": None}
    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            names = z.namelist()
            content = z.read('content.xml').decode('utf-8', errors='replace')

            # Slides
            slides = [s for s in re.split(r'(?=<draw:page\b)', content)
                      if s.strip().startswith('<draw:page')]
            metrics["slide_count"] = len(slides)

            # Charts (embedded OLE objects)
            for name in names:
                if re.match(r'^Object \d+/content\.xml$', name):
                    obj = z.read(name).decode('utf-8', errors='replace')
                    if 'chart:chart' in obj:
                        metrics["chart_count"] += 1

            # Notes
            for slide in slides:
                m = re.search(r'<presentation:notes\b[^>]*>(.*?)</presentation:notes>',
                              slide, re.DOTALL)
                if m:
                    text = re.sub(r'<[^>]+>', ' ', m.group(1)).strip()
                    if len(text) > 25:
                        metrics["notes_slides"] += 1

    except zipfile.BadZipFile as e:
        metrics["error"] = f"Bad ZIP: {e}"
    except Exception as e:
        metrics["error"] = f"Parse error: {e}"
    return metrics
```

**Tip — shape counting**: Always strip the `<presentation:notes>` section from a slide's XML before counting shapes. Notes sections can contain `draw:frame` elements that inflate the shape count and produce false positives for flowchart/diagram detection:

```python
def _count_shapes(slide_xml: str) -> int:
    slide_no_notes = re.sub(
        r'<presentation:notes\b.*?</presentation:notes>', '', slide_xml, flags=re.DOTALL
    )
    tags = ['draw:custom-shape','draw:connector','draw:rect',
            'draw:ellipse','draw:polygon','draw:path','draw:line']
    return sum(len(re.findall(rf'<{re.escape(t)}\b', slide_no_notes)) for t in tags)
```

**When to use**: Any verifier whose task output is `.odp`, `.pptx`, `.docx`, `.xlsx`, `.odt`, or `.ods`. The same zipfile approach works for all of them — only the internal file paths and XML namespaces differ.

---

## Pattern 14: Multi-Key Fallback Parsing for Unknown Config Key Names

**Problem**: Many desktop applications store settings in a JSON or XML config file, but the exact key names used internally are uncertain — different app versions may use different names for the same concept (`bandpassLowCut` vs `bp_lowCut` vs `lowerBandpass`), or the format may be discoverable only by running the app and inspecting the output, which can't be done during task design. Hardcoding a single expected key name makes the verifier brittle: one naming difference causes a false zero.

**Solution**: Try multiple candidate key names for each logical setting, in priority order. Fall back to regex on the raw text if all structured lookups fail.

### In export_result.sh (Python block):
```python
python3 << 'PYEOF'
import json, re, sys, os

config_path = "/home/ga/Documents/MyApp/Settings/UserProfile.json"
result = {
    "config_exists": False,
    "bandpass_low": None,
    "bandpass_high": None,
    "notch_hz": None,
    "expert_mode": None,
}

if os.path.exists(config_path):
    result["config_exists"] = True
    try:
        with open(config_path) as f:
            cfg = json.load(f)
        raw = json.dumps(cfg)  # for regex fallback

        # Try multiple candidate key names per logical setting
        def first_val(d, *keys):
            for k in keys:
                if k in d:
                    return d[k]
            return None

        result["bandpass_low"]  = first_val(cfg,
            "bandpassLowCut", "bp_lowCut", "lowerBandpass",
            "bandpass_low", "bandpassLow", "bpLow")

        result["bandpass_high"] = first_val(cfg,
            "bandpassHighCut", "bp_highCut", "upperBandpass",
            "bandpass_high", "bandpassHigh", "bpHigh")

        result["notch_hz"]      = first_val(cfg,
            "notchFilterFreq", "notchFreq", "notch_hz",
            "notchHz", "notchFilter", "notch_frequency")

        result["expert_mode"]   = first_val(cfg,
            "expertModeEnabled", "expertMode", "isExpertMode",
            "expert_mode_enabled")

        # Regex fallback for any value still missing
        if result["bandpass_low"] is None:
            m = re.search(r'"(?:bandpass|bp)[^"]*[Ll]ow[^"]*"\s*:\s*([\d.]+)', raw)
            if m:
                result["bandpass_low"] = float(m.group(1))

    except json.JSONDecodeError:
        # Completely unknown format — search raw text
        m = re.search(r'bandpass.*?low.*?:\s*([\d.]+)', open(config_path).read(), re.I)
        if m:
            result["bandpass_low"] = float(m.group(1))

import json as _j
print(_j.dumps(result))
PYEOF
```

### In verifier.py:
```python
# Verify logical value, not key name
bp_low = result.get("bandpass_low")
if bp_low is not None and abs(bp_low - 8.0) < 2.0:   # "about 8 Hz"
    score += 20
    feedback_parts.append(f"Bandpass low ≈ 8 Hz (got {bp_low})")
else:
    feedback_parts.append(f"Bandpass low not set correctly (got {bp_low})")
```

**Key principles**:
- Always try at least 3–4 candidate key names per logical setting (camelCase variants, snake_case, abbreviated).
- Keep the raw JSON string available for regex fallback.
- Validate the *logical value* (is it approximately correct?) rather than requiring an exact match.
- For widget/feature detection in nested or array-structured configs, search the entire raw JSON string for the widget display name as a last resort.

**When to use**: Any task involving a desktop application's settings or config file where you cannot inspect the exact schema before writing the verifier. Common for: Java/Swing apps, scientific tools, and any closed-source software where the settings format is not publicly documented.

---

## Pattern 15: Proxy-Based Verification for GUI-Only Feature Activation

**Problem**: Some GUI features are activated purely in-memory (modes toggled via menu or keyboard shortcut, UI panels shown/hidden, expert/developer modes). These activations leave no direct trace in a database or config file — the only evidence is behavioral: new capabilities become available, additional UI elements appear, or side effects (files produced, screenshots enabled) occur.

**Solution**: Verify the feature through its observable side effects rather than trying to detect the activation directly.

### Common proxy signals and how to capture them:

| Feature to verify | Observable proxy | How to measure |
|-------------------|-----------------|----------------|
| Expert/developer mode activated | New capabilities enabled (e.g., a screenshot hotkey, extra menu items) | Count screenshots before and after; check for new screenshot files |
| Audio/video recording started then stopped | Recording file exists in output directory | File existence + minimum size check (too-small file = recording barely started) |
| A widget/panel added to a layout | Settings file contains widget name | Search settings JSON text for widget display name |
| A specific filter applied | Settings file contains filter parameters | Parse config with multi-key fallback (Pattern 14) |
| Application restarted after config change | App window still visible + config file newer than task start | `wmctrl -l` check + mtime comparison |

### Example — Expert Mode via screenshot count proxy:

**In setup_task.sh:**
```bash
# Record screenshot count BEFORE task starts
SCREENSHOT_DIR="/home/ga/Documents/MyApp/Screenshots"
INITIAL_SCREENSHOTS=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOTS" > /tmp/<task_name>_initial_screenshot_count
```

**In export_result.sh:**
```bash
INITIAL_SS=$(cat /tmp/<task_name>_initial_screenshot_count 2>/dev/null || echo "0")
FINAL_SS=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SCREENSHOTS=$((FINAL_SS - INITIAL_SS))
# Write to result JSON
```

**In verifier.py:**
```python
new_screenshots = result.get("new_screenshot_count", 0)
if new_screenshots >= 1:
    score += 20
    feedback_parts.append(f"Expert Mode confirmed active ({new_screenshots} new screenshot(s))")
else:
    feedback_parts.append("No new screenshots — Expert Mode may not have been activated")
```

### Example — Recording completeness via file size:
```python
recording_size = result.get("new_recording_size_bytes", 0)
if recording_size >= 10_000:          # substantial recording
    score += 30
elif recording_size >= 1_000:         # recording started but barely any data
    score += 10
    feedback_parts.append("Recording file exists but is very small — was it stopped too quickly?")
else:
    feedback_parts.append("No valid recording file found")
```

**Key principles**:
- Size thresholds for "recording completeness" depend on the app's output rate. Calibrate by running the recording yourself for the minimum expected duration and checking the resulting file size.
- Never use proxy-only verification for the *primary* task criterion. Proxies should be secondary corroborating checks. The primary check should be the direct evidence (settings file, output file, database record).
- Document in the task README exactly which proxy signals the verifier uses, so future maintainers can understand why screenshot counts matter.

**When to use**: Any task involving: toggling application modes (expert/developer/advanced), activating recording or capture sessions, or enabling features that manifest behaviorally rather than in persistent data.

---

## Pattern 16: Coordinate Proximity Matching for Geographic Data

**Problem**: Tasks involving geographic locations (ground stations, GPS waypoints, map markers, sensor locations, weather station coordinates) require verifying that the agent entered the correct lat/lon values. However, coordinates are floating-point numbers and agents may enter them at different precision than expected (`42.1292` vs `42.13` vs `42.1292000000001`). All three represent the same physical location; exact equality fails for all of them.

**Solution**: Accept any coordinate pair within an ε-degree proximity radius. For city/station-level tasks, 0.5° is a reasonable default. For high-precision tasks (airfield runways, antenna arrays), tighten to 0.05°.

### In export_result.sh:
```bash
# Export all files of the expected type and their raw coordinate fields
python3 << 'PYEOF'
import os, configparser, json

CONFIG_DIR = os.path.expanduser("~/.config/MyApp")
stations = []

for fname in os.listdir(CONFIG_DIR):
    if fname.endswith(".station"):
        cfg = configparser.ConfigParser()
        cfg.read(os.path.join(CONFIG_DIR, fname))
        try:
            lat = float(cfg["STATION"]["LAT"])
            lon = float(cfg["STATION"]["LON"])
            alt = float(cfg["STATION"].get("ALT", "0"))
            stations.append({"file": fname, "lat": lat, "lon": lon, "alt": alt})
        except (KeyError, ValueError):
            pass

print(json.dumps({"stations": stations}))
PYEOF
```

### In verifier.py:
```python
def _find_station_by_coords(stations, target_lat, target_lon, tolerance=0.5):
    """Return the closest station within tolerance degrees, or None."""
    for s in stations:
        if abs(s["lat"] - target_lat) <= tolerance and abs(s["lon"] - target_lon) <= tolerance:
            return s
    return None

# Usage in scoring:
stations = result.get("stations", [])
erie = _find_station_by_coords(stations, 42.1292, -80.0851)
if erie:
    score += 20
    feedback_parts.append(f"Erie station found (lat={erie['lat']}, lon={erie['lon']})")
else:
    feedback_parts.append("Erie station not found within 0.5° of expected location")
```

**Tolerance calibration**:
| Use case | Recommended tolerance |
|----------|----------------------|
| City-level (ground stations, weather sites) | 0.5° (~55 km) |
| Airport / district level | 0.1° (~11 km) |
| Precise facility (antenna, runway) | 0.05° (~5.5 km) |
| Street-level or survey-grade | 0.001° (~110 m) |

**When to use**: Any task where agents enter latitude/longitude, easting/northing, or any continuous geographic coordinate. Common domains: satellite tracking, aviation, weather station networks, field survey tools, GIS software, navigation apps.

---

## Pattern 17: Scan-by-Content for Agent-Named Files

**Problem**: Many desktop apps store items as individual files on disk — one file per station, one per module, one per scene, one per profile. The agent is free to choose the filename when it creates the item. A verifier that requires a specific filename (e.g., `Erie.station`) will fail whenever the agent uses a different but equally valid name (`Erie_PA.station`, `erie_station.station`, `EriePennsylvania.station`).

**Solution**: Scan all files matching the expected extension or directory, and check each for content properties. Succeed if *any* file satisfies the criterion; fail only if none do.

### In export_result.sh:
```bash
# Scan all files of the expected type; identify each by content, not name
python3 << 'PYEOF'
import os, configparser, json

TARGET_DIR = os.path.expanduser("~/.config/MyApp/modules")
modules = []

for fname in os.listdir(TARGET_DIR):
    if not fname.endswith(".mod"):
        continue
    cfg = configparser.ConfigParser()
    cfg.read(os.path.join(TARGET_DIR, fname))
    try:
        sat_field = cfg["MODULE"]["SATELLITES"]
        norad_ids = [int(x) for x in sat_field.split(";") if x.strip().isdigit()]
        modules.append({"file": fname, "norad_ids": norad_ids})
    except (KeyError, ValueError):
        pass

print(json.dumps({"modules": modules}))
PYEOF
```

### In verifier.py:
```python
modules = result.get("modules", [])

# Check: does ANY module contain the expected satellites?
# Don't require a specific filename.
required_ids = {25544, 27607, 40967}

for mod in modules:
    if required_ids.issubset(set(mod["norad_ids"])):
        score += 20
        feedback_parts.append(f"Module '{mod['file']}' contains all required satellites")
        break
else:
    feedback_parts.append(f"No module found containing all of: {sorted(required_ids)}")
```

**Extended: searching by partial name or content keyword**:
```python
# If the task says "create a WeatherSats module", look for any file whose
# name contains "weather" or "wx" (case-insensitive) — not a specific filename.
weather_module = next(
    (m for m in modules if any(kw in m["file"].lower() for kw in ["weather", "wx"])),
    None
)
if weather_module:
    score += 15
else:
    feedback_parts.append("No module with 'weather' or 'wx' in its name found")
```

**When to use**: Any task where the agent creates named objects that persist as files — ground station files, module/scene/preset files, user profiles, project files, export outputs with agent-chosen names. Do NOT use this pattern when the task description explicitly specifies the required filename (in that case, requiring the exact filename IS part of the task).

**Important**: After identifying the file by content, you can still check secondary properties (correct values within the file, correct alt/wx/location fields, etc.) using the same scan-and-match approach.

---

## Pattern 18: Plain-Text Structured File Verification via Regex

**Problem**: Many environments store application state in plain-text structured files — VRML world files (robotics simulators), SDF/URDF (ROS), INI configs, YAML parameter files, custom DSL formats — that are neither databases (Pattern 7) nor ZIP-based binary formats (Pattern 13). The output file is human-readable but has its own syntax. Libraries may not exist for the format, or may not be installed in the host environment.

**Solution**: Copy the file from the VM via `copy_from_env`, read it as a string, and use regex to extract numeric field values for range checks. Do not parse the entire structure — target only the specific fields the task requires.

### In verifier.py:
```python
import re, tempfile, os

def verify_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    output_path = task_info.get('metadata', {}).get('output_path')
    score = 0
    feedback_parts = []

    with tempfile.NamedTemporaryFile(delete=False, suffix='.conf') as f:
        tmp = f.name
    try:
        copy_from_env(output_path, tmp)
        content = open(tmp, 'r', errors='replace').read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read output file: {e}"}
    finally:
        try: os.unlink(tmp)
        except: pass

    # Criterion 1: File is non-empty and parseable
    if len(content) > 100:
        score += 10
        feedback_parts.append("Output file exists and is non-trivial")

    # Criterion 2: Extract a numeric field (VRML-style: "fieldName value")
    m = re.search(r'\btimestep\s+(\d+)', content)
    timestep = int(m.group(1)) if m else None
    if timestep is not None and timestep <= 64:
        score += 30
        feedback_parts.append(f"Timestep fixed to {timestep}")
    else:
        feedback_parts.append(f"Timestep not corrected (got {timestep})")

    # Criterion 3: Extract a floating-point field
    m = re.search(r'\bgravity\s+([-\d.]+)', content)
    gravity = float(m.group(1)) if m else 0.0
    if abs(gravity) >= 9.0:
        score += 30
        feedback_parts.append(f"Gravity is physically valid ({gravity})")

    # Criterion 4: Check presence of a required structural element (node, section, tag)
    if re.search(r'\bGPS\b', content):
        score += 30
        feedback_parts.append("Required GPS node present")

    return {"passed": score >= 70, "score": score, "feedback": " | ".join(feedback_parts)}
```

### Common format-specific regex patterns:

| Format | Field pattern | Example |
|--------|--------------|---------|
| VRML / Webots `.wbt` | `r'\bfieldName\s+([\d.]+)'` | `basicTimeStep 32` |
| YAML | `r'^key:\s*([\d.]+)'` (multiline) | `max_range: 100.0` |
| INI / `.conf` | `r'^key\s*=\s*([\d.]+)'` (multiline) | `mass=12.5` |
| SDF / URDF / ROS XML | use `xml.etree.ElementTree` | `<mass>12.5</mass>` |
| Custom DSL | `r'keyword\s*[=:]\s*([\d.]+)'` | varies |

**For XML-based text formats** (SDF, URDF, ROS launch files, etc.) prefer `xml.etree.ElementTree.parse()` over regex — the structure is well-defined enough for a real parser.

**Key principles**:
- Always read the file as a string first; make a single regex pass per criterion rather than loading a library that may not exist.
- Extract the numeric value and apply a range check — do not just check for keyword presence (that can pass with a file that has the right keyword but wrong value).
- For very_hard tasks where the agent determines correct values independently, use range checks (`value <= 64`, `abs(gravity) >= 9.0`) rather than exact equality. See Principle 5 notes in `01_core_principles.md` for the rationale.
- Always add structural presence checks (does the file contain expected node types, required sections, mandatory fields?) as separate criteria from value-correctness checks.

**When to use**: Any task whose output is a plain-text world/config/parameter file — robotics simulators (Webots VRML, Gazebo SDF, ROS YAML), scientific software configs, game engine scenes, audio/video processing parameter files, simulation tool configs. Not needed for SQLite databases (Pattern 7), binary office formats (Pattern 13), or apps with scripting APIs (use those directly).

---

## Pattern 19: GT-in-Setup — Precomputing Expected Outputs for Multi-Entity Analysis Tasks

**Problem**: Some tasks require the agent to compute a derived value (count, distance, area, percentage, classification) for each of many entities (N countries, N states, N tracts, N rows). Pattern 1 (Baseline Recording) records what *exists* to detect new work. But for analysis tasks, you also need to know what the *correct computed result* should be for each entity, so you can measure accuracy — not just detect whether new work occurred.

**Solution**: In `setup_task.sh`, after downloading the input data but before recording the task start timestamp, run a Python block that computes the full expected output and saves it as a structured JSON ground truth file (`/tmp/gt_<task_name>.json`).

### In setup_task.sh:
```bash
# GT is computed from the SAME data files the agent will use
python3 << 'PYEOF'
import json

# Load the input data (same files staged for the agent)
with open("/home/ga/data/input_features.geojson") as f:
    features = json.load(f)["features"]
with open("/home/ga/data/reference.geojson") as f:
    references = json.load(f)["features"]

# Compute expected output for each entity
entity_stats = {}
for ref in references:
    name = ref["properties"]["name"]
    count = sum(1 for feat in features if point_in_polygon(feat, ref))
    entity_stats[name] = {"count": count, "status": "present" if count > 0 else "absent"}

gt = {
    "entity_stats": entity_stats,
    "expected_entity_count": len(entity_stats),
    "computed_at": "setup_time"   # distinguishes from agent-time computation
}
with open("/tmp/gt_task_name.json", "w") as f:
    json.dump(gt, f, indent=2)
print(f"GT computed: {len(entity_stats)} entities")
PYEOF

# IMPORTANT: Record task start timestamp AFTER GT computation
date +%s > /tmp/task_name_start_ts
```

### In export_result.sh:
```bash
# Compare agent output against precomputed GT
python3 << 'PYEOF'
import json, sys

with open("/tmp/gt_task_name.json") as f:
    gt = json.load(f)
with open("/home/ga/exports/agent_output.geojson") as f:
    agent_data = json.load(f)

gt_stats = gt["entity_stats"]
total_gt = len(gt_stats)
correct = 0

for feat in agent_data["features"]:
    name = feat["properties"].get("name", "")
    if name in gt_stats:
        agent_val = feat["properties"].get("count", -1)
        if abs(agent_val - gt_stats[name]["count"]) <= 1:
            correct += 1

accuracy = int(100 * correct / total_gt) if total_gt > 0 else 0
print(f"accuracy={accuracy}")
PYEOF
```

**Key distinctions from Pattern 1 (Baseline Recording)**:
| | Baseline Recording (Pattern 1) | GT-in-Setup (Pattern 19) |
|--|--|--|
| Purpose | Detect that NEW work was done | Measure accuracy of computed values |
| What is recorded | Initial state (counts, timestamps) | Expected output per entity |
| Used for | Change detection | Value comparison |
| Typical tasks | CRUD (create/edit/delete) | Analysis (aggregate/classify/compute) |

**Critical rule: GT must be computed from the SAME data the agent will use.** If the input data is a live feed (API, real-time data), download it ONCE in setup, save to a fixed path, compute GT from that path, and point the task description to that path. Never let the agent independently re-download live data that may have changed since GT was computed.

**When to use**: Any task where the agent produces computed values per entity — statistical analysis (counts, sums, averages per group), spatial analysis (distance/area/overlap per polygon), financial analysis (totals per account), epidemiological analysis (rates per region). Essentially: any task where "correctness" means "numerically close to the true value", not just "something new was created".

---

## Pattern 20: Percentage Accuracy Scoring and Classification Fairness for Many-Entity Tasks

**Problem 1 — Percentage accuracy**: When checking computed values across N entities (≥ 10), requiring 100% exact match is too strict. Legitimate sources of small discrepancies include: different projection CRS (affecting area/distance by <1%), different spatial join methods (edge-case features near boundaries), floating-point accumulation, and minor differences in downloaded data versions. Requiring exact match over-penalizes correct approaches.

**Problem 2 — Classification fairness**: Many tasks require computing both an intermediate value (e.g., hospital count within 5 km) AND a derived classification (e.g., access tier: low/medium/high). If the verifier scores the classification by comparing directly to the GT classification, an agent that computed a slightly off intermediate value gets double-penalized: once for the intermediate value, and again for the classification that depended on it. This is unfair and inflates the penalty for a single root-cause error.

### Solution 1: Percentage accuracy thresholds

Instead of exact match, require that ≥ X% of entities fall within a ± tolerance of GT:

```python
# In export_result.sh Python block, or verifier.py:

total_gt = len(gt_stats)
correct = 0
for entity_name, gt_vals in gt_stats.items():
    if entity_name not in agent_map:
        continue
    agent_val = agent_map[entity_name].get("computed_field", None)
    if agent_val is None:
        continue
    # ±1 tolerance for integer counts, ±3.0 for percentages, ±1.0 km for distances
    if abs(float(agent_val) - gt_vals["computed_field"]) <= TOLERANCE:
        correct += 1

accuracy_pct = int(100 * correct / total_gt) if total_gt > 0 else 0
```

**Calibrating thresholds**:
| Output type | Tolerance | Pass threshold |
|--|--|--|
| Integer counts (points in polygon) | ±1 | ≥ 60% |
| Distances in km | ±1.0 km | ≥ 60% |
| Area percentages | ±3.0 percentage points | ≥ 55% |
| Ratios / densities | ±10% relative error | ≥ 60% |

The pass threshold for accuracy criteria (e.g., ≥ 60%) should be lower than perfect because accuracy scoring is inherently continuous — an agent that gets 58/100 entities right deserves more than 0 points. Use partial credit for ranges below the pass threshold.

### Solution 2: Re-derive classification from agent's own intermediate values

When a classification field depends on an intermediate computed field, score the classification by re-deriving what it *should* be from the agent's own intermediate value — not from GT:

```python
# BAD: comparing directly to GT classification (double-penalizes a slightly-off count)
gt_tier = gt_stats[name]["access_tier"]
agent_tier = agent_props.get("access_tier", "")
if agent_tier == gt_tier:
    correct_classifications += 1

# GOOD: re-derive expected classification from agent's own count
agent_count = agent_props.get("hosp_count_5km", 0)
# Apply the same classification rule stated in the task description:
if agent_count >= 3:
    expected_tier = "high"
elif agent_count >= 1:
    expected_tier = "medium"
else:
    expected_tier = "low"

agent_tier = agent_props.get("access_tier", "").lower().strip()
if agent_tier == expected_tier:
    correct_classifications += 1
```

**Why this matters**: Using this approach, the "count accuracy" criterion and the "classification accuracy" criterion become truly independent. An agent that computed all counts correctly but labeled the tiers wrong loses points only on classification. An agent that computed some counts slightly wrong but applied the classification rules correctly gets full credit on classification. This makes scoring more informative and more fair.

**When to use Pattern 20**:
- Any task producing computed values across ≥ 10 entities (use percentage accuracy, not exact match)
- Any task with a derived classification that depends on a separately-scored intermediate value (use re-derivation for fairness)
- Any analysis task producing output at polygon/region/entity granularity: GIS analysis, statistical reports, coverage assessments, equity studies, surveillance summaries

---

## Pattern 21: Best-Candidate Selection for Multi-Criterion Scoring

**Problem**: Pattern 17 checks if *any* new artifact satisfies each criterion independently — which can produce inflated scores by mixing attributes across different artifacts. For example: search A has the right content but isn't scheduled; search B is scheduled but has wrong content. If each criterion is checked against "any" artifact, both criteria pass and the score is 40 — even though neither artifact fully accomplishes the task.

**Solution**: Select the single **best candidate** artifact using a composite scoring function, then evaluate **all** criteria against that one artifact. This ensures the score reflects what the agent's *intended* output looks like, not a cherry-picked combination.

### The pattern:

```python
def score_candidate(artifact):
    """Rank candidates by how many core criteria they satisfy — used for selection only."""
    sc = 0
    content = artifact.get('search', '') or artifact.get('content', '')
    low = content.lower()
    if 'target_index' in low:   sc += 1   # correct data source
    if has_required_logic(low): sc += 1   # core content check
    if artifact.get('is_scheduled'): sc += 1  # meta property
    return sc

def verify_task(traj, env_info, task_info):
    new_artifacts = result.get('new_artifacts', [])

    # Criterion 1: anything new was created
    if not new_artifacts:
        return {"passed": False, "score": 0, "feedback": "No new artifacts created"}
    score += 20

    # Pick the BEST candidate — evaluate all remaining criteria against it
    best = max(new_artifacts, key=score_candidate)

    # Criterion 2: correct data source
    if 'target_index' in best.get('content', '').lower():
        score += 20

    # Criterion 3: correct logic
    if has_required_logic(best.get('content', '')):
        score += 20

    # Criterion 4: scheduled/automated
    if best.get('is_scheduled'):
        score += 20

    # Criterion 5: has configuration property (cron, threshold, etc.)
    if best.get('config_property'):
        score += 20
```

**Contrast with Pattern 17** (scan-by-content): Pattern 17 is for hard criteria — "does any artifact contain exactly these satellite IDs?" — where the match is binary and any match counts. Pattern 21 is for multi-dimensional scoring — "what does the agent's best attempt look like across all dimensions?" — where you want all dimensions measured against the same artifact.

**When to use**: Any task requiring the agent to create a configurable artifact (saved search, alert, dashboard, scheduled job, pipeline, automation rule) where the artifact has both *content* criteria (what it queries/computes) and *configuration* criteria (how it is set up — scheduled, named, thresholded). Common in: SIEM/log analysis tools (Splunk, Elastic), monitoring platforms (Grafana, Datadog), workflow tools (Airflow, Jenkins), project management tools (Jira automation rules).

---

## Pattern 22: Pass Threshold Calibration Against Meta-Criteria

**Problem**: In a task with N criteria, some criteria are **core** (they test whether the artifact's *content* solves the problem) and some are **meta** (they test *how* it was built — is it scheduled? does it have a threshold? does it have a name?). Meta-criteria can be satisfied by ANY artifact, regardless of whether its content is correct.

If PASS_THRESHOLD is too low, an agent can create a plausible-looking but off-topic artifact and pass:
- Example: 5-criterion task, threshold = 60 (3/5). A scheduled alert on the wrong data source satisfies criterion 1 (new artifact) + criterion 4 (is_scheduled) + criterion 5 (has_cron) = 60 — **passes** despite completely wrong content.

**Solution**: Set PASS_THRESHOLD high enough that an agent must satisfy **at least all core content criteria** plus at least one meta criterion to pass.

### Calibration rule:

```
PASS_THRESHOLD ≥ (number_of_core_criteria / total_criteria) × 100 + 1 meta criterion's worth
```

In practice, for 5 criteria with 3 core and 2 meta:
- Core only: 60 → not enough (meta-criteria alone could get you here)
- Core + 1 meta: 80 → correct pass threshold
- Use PASS_THRESHOLD = 80

```python
# 5 criteria × 20pts each = 100 total
POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 80  # requires 4/5 — at minimum the 3 core + 1 meta

# Core criteria (content-based — cannot be gamed by off-topic artifacts):
#   (2) searches correct data source   [20pts]
#   (3) implements correct logic       [20pts]
# Meta criteria (structure-based — can be satisfied with any artifact):
#   (4) is_scheduled                   [20pts]
#   (5) has_cron_or_threshold          [20pts]
# Base criterion:
#   (1) something new was created      [20pts]  ← always required
```

**Testing for threshold correctness**: After writing the verifier, explicitly test the "wrong-content-but-meta-correct" scenario:

```python
# Wrong content (web logs for a security task), but fully configured:
wrong_data = {"new_artifacts": [{
    "content": "index=web_logs status=500 | stats count",  # wrong index
    "is_scheduled": True,
    "cron_schedule": "*/15 * * * *"
}]}
result = verify_task([], {"copy_from_env": make_copy_fn(wrong_data)}, {})
assert not result['passed'], f"Wrong-content artifact must NOT pass, got score={result['score']}"
```

If this test fails (wrong content passes), lower the threshold is the symptom; the fix is to raise PASS_THRESHOLD until the wrong-content scenario fails.

**When to use**: Any multi-criterion task where some criteria test structural/meta properties (scheduling, naming, file size, count, format) that can be satisfied independently of whether the core task was accomplished. Common pitfall environments: scheduling tools, monitoring platforms, CMS/report builders, any tool where artifacts have both content and configuration dimensions.

---

## Anti-Pattern: Preservation Criteria on Do-Nothing

**Problem**: A verifier criterion that checks "existing state was not damaged" (files preserved, records not deleted, settings unchanged) will **always pass on a do-nothing agent**, because the agent never touched anything. This inflates the do-nothing score above zero.

This is especially common in contamination injection and cleanup tasks, where one criterion rewards removing bad items and another rewards preserving good items. The preservation criterion is satisfied trivially by inaction.

**Example of the bug**:
```python
# BAD: do-nothing agent scores 20 free points
if ct_files_still_present:
    score += 20  # "CT files preserved"
```

An agent that takes zero actions leaves all files untouched — including the contaminants — and earns 20 points for "preserving" the legitimate files it never interacted with.

**Solution**: Gate preservation criteria behind an action check. Only award "preserved existing state" points if the agent demonstrably took at least one relevant action (removed at least one contaminant, edited at least one file, modified at least one record).

```python
# GOOD: preservation only scored if agent took cleanup action
removed = result.get("contaminants_removed", 0)

if removed == 0:
    feedback.append("No cleanup action taken — preservation not scored (0/20)")
elif ct_files_still_present:
    score += 20
    feedback.append("CT files preserved after cleanup (20/20)")
```

**General rule**: Any criterion whose passing condition is already true in the initial state MUST be gated behind evidence that the agent acted. Ask yourself: "Would a do-nothing agent satisfy this criterion?" If yes, add a gate.

**Where this commonly appears**:
- Contamination cleanup: "legitimate items preserved" (trivially true if nothing was deleted)
- Error correction: "no new errors introduced" (trivially true if nothing was changed)
- Configuration repair: "other settings unchanged" (trivially true if nothing was touched)
- File management: "original directory structure intact" (trivially true if nothing was moved)

---

## Pattern 22: Criterion-Feature Mapping (Enforcing Multi-Feature Usage)

When a task requires the agent to use N distinct application features, the verifier must structurally enforce this — stating "use 4 features" in the description is not enough. The enforcement mechanism is: **each scoring criterion should verify a different feature**.

If all 5 criteria test the same feature (e.g., all check furniture placement), you have a single-feature task disguised as multi-criterion scoring. An agent can max the score by deeply using one feature and ignoring the others.

**Design rule**: Map features to criteria so that skipping any feature costs significant points (at least 15-20 pts out of 100).

```
Feature A (e.g., furniture placement) → C1 (25 pts) + C4 (20 pts)
Feature B (e.g., wall creation)       → C2 (20 pts)
Feature C (e.g., label placement)     → C3 (15 pts)
Feature D (e.g., door placement)      → C2 (shared, 20 pts)
```

**Why this matters**: Agents that discover they can score 70/100 using a single feature will take that shortcut. When each feature anchors its own criterion, there is no path to passing without exercising multiple features.

**Self-check**: For each criterion in your verifier, ask: "Which distinct application feature must the agent have used to satisfy this?" If two criteria have the same answer, consider merging them and using the freed criterion to test a different feature.

---

## Pattern 23: Structural Baseline Deltas for Creation Tasks

When a task starts from a partially-stripped file (e.g., a building shell with walls but no furniture, a presentation template with slides but no content), the baseline must record counts of **all preserved structural element types**, not just the stripped content.

Without this, the export cannot distinguish between structural elements that existed before the agent started and new ones the agent added.

**The pattern**:

1. **In `setup_task.sh`**: After creating the starter file, parse it and record counts of every element type that the agent might add more of:
   ```python
   baseline = {
       'stripped_element_count': 0,          # what was removed (furniture, content)
       'preserved_type_A_count': count_A,    # what was kept (walls, slides, layers)
       'preserved_type_B_count': count_B,    # (rooms, sections, sheets)
       'starter_md5': md5_hash
   }
   ```

2. **In `export_result.sh`**: Parse the final file, count all element types, and compute deltas:
   ```python
   new_type_A = current_count_A - baseline['preserved_type_A_count']
   new_type_B = current_count_B - baseline['preserved_type_B_count']
   ```

3. **In `verifier.py`**: Score based on deltas (`new_type_A >= 3`), never raw counts.

**Why raw counts fail**: If the starter file has 12 walls, a do-nothing agent already has 12 walls. A verifier checking `wall_count >= 3` passes trivially. Checking `new_walls >= 3` requires the agent to actually create walls.

---

## Pattern 24: Scoring Calibration — Use Partial Completion to Validate Weights Before Finalizing

Before shipping a verifier, compute what score a **strategically partial** submission would receive: one that completes only the "easy" criteria (e.g., correct name, creates the required record) but skips the harder ones (e.g., routing settings, unit preferences, safety options). If this partial score meets or exceeds the pass threshold, the task can be gamed by doing the minimum work.

**The calibration process:**

1. Identify the lowest-effort subset of criteria an agent might plausibly complete (typically: the structural gate + the most obvious visible criterion).
2. Compute the score for that subset manually.
3. If `partial_score >= pass_threshold`, either:
   - Increase weights on the harder criteria
   - Lower the pass threshold
   - Add a second gate that rejects purely structural submissions

**Example:**
```
Task: Configure a vehicle profile and update 4 routing settings
Easy criteria: name (20pts) + type (15pts) + fuel/year/emission (15pts) = 50pts
Pass threshold: 65pts   ← 50 < 65, so partial completion fails ✓

If routing criteria were only 5pts each (20pts total) and profile were 45pts:
Easy criteria: 45pts
Pass threshold: 50pts   ← 45 < 50, barely safe but risky

If profile were 60pts and routing were 5pts each (20pts total):
Easy criteria: 60pts
Pass threshold: 65pts   ← 60 < 65, safe ✓
But an agent doing everything except one routing setting: 60+5+5+5=75 → passes
← dangerous: motivates skipping the hardest routing criteria
```

**Rule of thumb**: The score from completing only the gate + 1 easy criterion should be no more than 50% of the pass threshold. The score from completing all easy criteria but none of the "hard" ones (settings, configuration, secondary changes) should be at least 10 points below the pass threshold.

**This calibration is also useful during the partial completion test in Phase 5.** If your injected partial result (completing only easy criteria) scores above the pass threshold, your weights need rebalancing before the task is released.

**This applies broadly**: CAD files (layers, groups preserved), spreadsheets (sheets preserved, cells stripped), databases (tables preserved, rows cleared), presentations (slide structure preserved, content stripped).

---

## Pattern 25: Pilot-Inspect Output File Format Before Writing Verifiers for Workbook-Producing Apps

**Problem**: Desktop applications that save "projects", "workbooks", or "documents" often use a custom binary or partially-binary file format — even when the file extension looks standard (`.zip`, `.json`, `.xml`). Pattern 13 handles ZIP-based office formats where all inner entries are plaintext XML. But many applications use ZIPs with inner entries that are zlib-compressed binary, custom-encoded blobs, or proprietary serialized objects. Writing a verifier that searches only plaintext entries will silently miss all content stored in compressed entries, producing a verifier that always scores zero.

**Real example**: Oracle Analytics Desktop saves workbooks as `.dva` files. These are ZIP archives, but the workbook content lives in `.arc` entries that are zlib-compressed — not plaintext. The dataset metadata is in `.json` entries (plaintext), but canvas names and calculated column names are exclusively in the `.arc` entries. A verifier that only reads `.json` entries from the ZIP will never find any canvas or column names.

**Solution: Always pilot-inspect the actual output file format before writing a single line of verifier code.**

### Pilot inspection procedure

In your pilot trajectory, produce the smallest possible valid output file (create one workbook, rename one canvas, add one calculated column), then retrieve it via `copy_from_env` and inspect with Python:

```python
import zipfile, zlib, os

path = "/tmp/test_output.ext"   # retrieved from VM

# Step 1: Is it a ZIP?
print("Is ZIP:", zipfile.is_zipfile(path))

with zipfile.ZipFile(path, 'r') as zf:
    for name in zf.namelist():
        data = zf.read(name)
        print(f"\n--- {name} ({len(data)} bytes) ---")

        # Step 2: Try plaintext
        try:
            text = data.decode('utf-8', errors='strict')
            print("  UTF-8 plaintext, first 300 chars:", text[:300])
            continue
        except UnicodeDecodeError:
            pass

        # Step 3: Try zlib decompression
        try:
            text = zlib.decompress(data).decode('utf-8', errors='replace')
            print("  zlib-compressed, first 300 chars after decompress:", text[:300])
            continue
        except zlib.error:
            pass

        # Step 4: Unknown binary
        print("  Binary, first bytes:", data[:32].hex())
```

Repeat for each inner entry until you understand how the app stores the content the verifier needs to check.

### Implementing the verifier once format is known

For apps with zlib-compressed inner entries (e.g., OAD `.dva` files with `.arc` entries):

```python
import zipfile, zlib

def _load_workbook_text(path):
    """Read all readable text from a workbook ZIP, decompressing binary inner entries."""
    if not zipfile.is_zipfile(path):
        return None, "Not a valid ZIP archive"
    import zlib
    all_text = []
    try:
        with zipfile.ZipFile(path, 'r') as zf:
            for name in zf.namelist():
                data = zf.read(name)
                # Try plaintext first (JSON, XML inner entries)
                try:
                    all_text.append(data.decode('utf-8', errors='strict'))
                    continue
                except (UnicodeDecodeError, AttributeError):
                    pass
                # Try zlib decompression (proprietary compressed entries)
                try:
                    decompressed = zlib.decompress(data)
                    all_text.append(decompressed.decode('utf-8', errors='replace'))
                except zlib.error:
                    pass  # skip truly opaque binary blobs
        return '\n'.join(all_text), None
    except Exception as e:
        return None, str(e)
```

Then text-search the combined output for canvas names, column IDs, configuration keys, etc.

### When to apply this pattern

Any task where:
- The application saves work as a non-standard or proprietary file format
- The verifier needs to check content within the saved file (not just its existence or size)
- The format is not one of the standard office formats already covered in Pattern 13

**Examples of apps likely to use this pattern**: BI/analytics tools (OAD `.dva`, Tableau `.twbx`), game engines (Unity `.unitypackage`, Godot `.tscn` in zip), CAD tools (Fusion 360 `.f3d`), audio DAWs, video editors, specialized scientific/engineering apps.

**The rule**: Do not assume any proprietary workbook format stores content as plaintext inside the ZIP. Always inspect first. Budget 30–60 minutes for format discovery in the pilot trajectory before writing the verifier.

---

## Pattern 26: Internal Save vs. Export — Ensuring Verifier Captures Current Agent State

**Problem**: Many desktop applications distinguish between two separate operations:
1. **Internal save** — persists the current state to the application's own internal format (Ctrl+S, File > Save). Does not produce an exportable artifact by itself.
2. **Export / Publish** — generates the output artifact (e.g., saves as `.dva`, exports to PDF, writes a PNG, etc.) from the **last internally saved state**, not necessarily the current unsaved state.

If the agent performs export without first doing an internal save, the exported file will capture the state from the previous internal save — potentially missing the agent's most recent work (a renamed canvas, a new visualization, a just-entered formula).

**Real example**: Oracle Analytics Desktop's "Export → Workbook Binary" operation exports the last-saved workbook state. If an agent renames a canvas but hasn't pressed Ctrl+S, the exported `.dva` still has the old canvas name. The verifier downloads the export, finds the old name, and scores 0 for that criterion — even though the agent "did the work."

### Implications for task design

When writing task descriptions for any app with this save/export split:
- **Do not tell the agent which button to click** (very_hard tasks have no UI hints), but **do ensure the success criteria require only what the export captures**, not ephemeral UI state.
- If the task requires the agent to produce an output file, the verifier implicitly requires that the agent saved internally before exporting — this is domain knowledge the agent must apply.
- Do NOT verify ephemeral application state (e.g., "the canvas tab is currently selected"). Verify only persistent artifacts (the exported file and its contents).

### Implications for verifier design

The verifier should:
1. Check the exported file's `mtime > task_start` (ensures it was produced during the task, not pre-existing).
2. Parse the exported file for expected content (canvas names, values, structure).
3. **Not** attempt to query the application's live state directly — this is fragile and environment-dependent.

If an exported file passes the `is_new` check but fails content checks, the most likely cause is that the agent exported without first internally saving. This is expected failure behavior, not a verifier bug.

### How to identify affected environments during onboarding

During the pilot trajectory, explicitly test the save-then-export sequence:
1. Make a change to the workbook.
2. Export without saving internally. Inspect the exported file.
3. Now save internally (Ctrl+S or equivalent), export again. Inspect the new file.
4. If step 3 produces different content than step 2, the app has this split — document it in `evidence_docs/README.md`.

**Apps commonly affected**: BI tools (OAD, Tableau, Power BI), creative suites (Adobe Illustrator, Inkscape), CAD (AutoCAD, SolidWorks), audio DAWs (saving a session vs. exporting a mix), video editors (saving a project vs. rendering the output).
