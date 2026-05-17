> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Windows Environment Patterns

## Overview

When the target environment is a Windows VM (Windows 10/11), several conventions differ fundamentally from Linux-based environments. This document covers the key adaptations required for task scripts, verification, and testing.

---

## 1. Scripts Are PowerShell, Not Bash

**All task scripts use `.ps1` (PowerShell), not `.sh` (bash).**

```
tasks/<task_name>/
├── task.json
├── README.md
├── setup_task.ps1          ← NOT setup_task.sh
├── export_result.ps1       ← NOT export_result.sh
└── verifier.py             ← same as Linux
```

**`task.json` hooks must invoke PowerShell explicitly:**
```json
{
  "hooks": {
    "pre_task":  "powershell -ExecutionPolicy Bypass -File C:\\workspace\\tasks\\<task>\\setup_task.ps1",
    "post_task": "powershell -ExecutionPolicy Bypass -File C:\\workspace\\tasks\\<task>\\export_result.ps1"
  }
}
```

**`chmod +x` is NOT required** — PowerShell scripts don't need execute permissions. The `-ExecutionPolicy Bypass` flag handles this.

**`#!/bin/bash` shebang is NOT used** — PowerShell scripts begin with comments or code directly.

---

## 2. Timestamp Recording in PowerShell

Record the task start time as a Unix timestamp (integer seconds since epoch):

```powershell
# Record Unix timestamp AFTER cleaning output files (anti-gaming)
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_<task>.txt" -Encoding ASCII -Force
```

Read it back in the same script or export script:
```powershell
$taskStart = 0
$startTsFile = "C:\Users\Docker\task_start_ts_<task>.txt"
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}
```

**Critical ordering**: Always delete output files FIRST, then record the timestamp. If you record the timestamp before deleting, a stale file deleted after recording will still have `mtime < task_start`, but any new file created at the exact same second as the timestamp will appear as "pre-task" due to integer truncation.

```powershell
# CORRECT ordering:
# 1. Delete stale output files
foreach ($f in @("C:\Users\Docker\Desktop\output.jpg", "C:\Users\Docker\Documents\project.ext")) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}
# 2. THEN record timestamp
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_<task>.txt" -Encoding ASCII -Force
```

---

## 3. File Existence and Modification Time Check

Use a reusable helper function in `export_result.ps1`:

```powershell
function Get-FileResult {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        return @{
            exists     = $true
            size_bytes = [long]$fi.Length
            mtime_unix = $mtime
            is_new     = ($mtime -gt $taskStart)   # integer comparison — no sub-second false positives
        }
    }
    return @{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false }
}
```

This handles the sub-second precision issue (Lesson 15 of `05_learnings_best_practices.md`) natively: both `$mtime` and `$taskStart` are integers, so `$mtime -gt $taskStart` is always a safe comparison.

---

## 4. JSON Generation in PowerShell

Use `ConvertTo-Json` with sufficient depth for nested structures:

```powershell
$resultPath = "C:\Users\Docker\<task_name>_result.json"

$result = [ordered]@{
    task         = "<task_name>"
    task_start   = $taskStart
    output_file  = (Get-FileResult "C:\Users\Docker\Desktop\output.jpg")
    project_file = (Get-FileResult "C:\Users\Docker\Documents\project.ext")
}

# depth=5 handles nested hashtables (file info dicts inside the main dict)
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
```

**Use `[ordered]@{}` not `@{}`** — PowerShell hashtables are unordered by default; `[ordered]` preserves insertion order, making result JSON easier to read.

---

## 5. Result JSON Path Convention for Windows

Store the result JSON in the user's home directory, not `/tmp/` (which doesn't exist on Windows):

```
C:\Users\Docker\<task_name>_result.json
```

In `verifier.py`, reference with escaped backslashes:
```python
RESULT_PATH = "C:\\Users\\Docker\\<task_name>_result.json"
```

---

## 6. Launching Applications in the Interactive Desktop Session

> **Important:** The Windows environment has a **full graphical desktop** accessible via VNC. Agents interact with it visually (screenshots + mouse/keyboard). The limitation below applies only to **setup/export hook scripts** that run over SSH — not to the agent's own interaction with the desktop.

SSH hook scripts on Windows run in Session 0 (a special non-interactive session with no GUI access). To launch a GUI application from a hook script so it appears on the interactive desktop, use `schtasks /IT`:

```powershell
# The env's task_utils.ps1 provides Ensure-DreamPlanReadyForTask or similar helpers
# that handle the Session 0 → Session 1 bridging via VBScript + schtasks.
# Always source task_utils.ps1 and call its environment-specific launcher:
. "C:\workspace\scripts\task_utils.ps1"
$ready = Ensure-<AppName>ReadyForTask
```

If no such helper exists, the general pattern is:
```powershell
# Create a VBScript that launches the app, then invoke via schtasks /IT
$vbs = @"
Set oShell = CreateObject("WScript.Shell")
oShell.Run "C:\Path\To\App.exe", 1, False
"@
$vbs | Out-File -FilePath "C:\Windows\Temp\launch_app.vbs" -Encoding ASCII
schtasks /Create /TN "LaunchApp" /TR "cscript C:\Windows\Temp\launch_app.vbs" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F | Out-Null
schtasks /Run /TN "LaunchApp" | Out-Null
```

**Why `/IT`**: The `/IT` flag runs the task only when the user is interactively logged on, ensuring the process has a visible desktop handle.

---

## 7. Accessing the PyAutoGUI TCP Server

The GymAnything Windows runtime starts a PyAutoGUI server on the guest at port 5555, forwarded to a dynamic host port. Scripts running in the VM can interact with the desktop via commands sent to this server. The `task_utils.ps1` provides `Invoke-PyAutoGUICommand` for this:

```powershell
. "C:\workspace\scripts\task_utils.ps1"

# Click at screen coordinates
Invoke-PyAutoGUICommand -Command @{ action = "click"; x = 640; y = 360 }

# Type text
Invoke-PyAutoGUICommand -Command @{ action = "typewrite"; text = "Hello World"; interval = 0.05 }
```

**Important**: The correct function name is `Invoke-PyAutoGUICommand` (not `Send-PyAutoGUI`). Check the actual `task_utils.ps1` in the environment's `scripts/` directory to confirm the function name before using it — it may differ across environments.

The agent (external) uses the VNC viewer for vision and the PyAutoGUI TCP server for interaction. The task scripts (setup and export) should avoid taking actions via PyAutoGUI — they should only use SSH-based commands.

---

## 8. Screenshot Capture for Windows Environments

For evidence collection scripts that need a screenshot of the Windows desktop:

```python
# Use the runner's built-in capture_screenshot method
screenshot_path = "evidence_docs/task_screenshot.png"
ok = env._runner.capture_screenshot(screenshot_path)

# The method tries:
#   1. PyAutoGUI TCP client screenshot (primary)
#   2. VNC framebuffer capture (fallback)
# Returns True if the screenshot was saved successfully.
```

Do NOT use `DISPLAY=:1 scrot` — that is Linux-only.

---

## 9. Script Structure Template

**`setup_task.ps1`** template:
```powershell
# Load shared helpers (provides Ensure-<App>ReadyForTask, etc.)
. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up <Task Name> ==="

# Kill any interfering background apps (e.g., Edge browser)
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# STEP 1: Delete stale output files (BEFORE recording timestamp)
$filesToClean = @(
    "C:\Users\Docker\Desktop\output_file.jpg",
    "C:\Users\Docker\Documents\project.ext"
)
foreach ($f in $filesToClean) { Remove-Item $f -Force -ErrorAction SilentlyContinue }

# STEP 2: Record task start timestamp AFTER cleanup
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_<task>.txt" -Encoding ASCII -Force

# STEP 3: Ensure application is running with the correct project loaded
$ready = Ensure-<App>ReadyForTask
if (-not $ready) {
    Write-Host "WARNING: Application did not load correctly"
}

Write-Host "=== Setup Complete ==="
```

**`export_result.ps1`** template:
```powershell
. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Exporting <Task Name> Result ==="

$resultPath  = "C:\Users\Docker\<task_name>_result.json"
$startTsFile = "C:\Users\Docker\task_start_ts_<task>.txt"

$taskStart = 0
if (Test-Path $startTsFile) {
    $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
}

function Get-FileResult {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $fi    = Get-Item $FilePath
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        return @{ exists=$true; size_bytes=[long]$fi.Length; mtime_unix=$mtime; is_new=($mtime -gt $taskStart) }
    }
    return @{ exists=$false; size_bytes=0; mtime_unix=0; is_new=$false }
}

$result = [ordered]@{
    task         = "<task_name>"
    task_start   = $taskStart
    output_jpg   = (Get-FileResult "C:\Users\Docker\Desktop\output_file.jpg")
    project_ext  = (Get-FileResult "C:\Users\Docker\Documents\project.ext")
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
Write-Host "=== Export Complete ==="
```

**`verifier.py`** template (same as Linux, just different result path):
```python
import json, tempfile, os, logging

RESULT_PATH = "C:\\Users\\Docker\\<task_name>_result.json"

def verify_<task_name>(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, 'r', encoding='utf-8-sig') as f:   # utf-8-sig strips BOM
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try: os.unlink(tmp.name)
        except: pass

    def fi(key):
        v = result.get(key, {})
        return v if isinstance(v, dict) else {}

    score = 0
    feedback_parts = []

    # Check files: exists + is_new + size threshold
    output = fi('output_jpg')
    if output.get('exists') and output.get('is_new'):
        score += 20
        feedback_parts.append("Output file created.")
    # ... additional criteria ...

    passed = score >= 60
    return {"passed": passed, "score": min(score, 100), "feedback": " | ".join(feedback_parts)}
```

**Note: `encoding='utf-8-sig'`** — Windows PowerShell `Out-File -Encoding UTF8` writes a UTF-8 BOM. Using `utf-8-sig` in Python strips the BOM automatically, preventing JSON parse errors.

---

## 10. Common Windows-Specific Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Script uses `.sh` extension | Pre-task hook fails silently | Rename to `.ps1`, update hook path in `task.json` |
| Missing `-ExecutionPolicy Bypass` | Script blocked by PowerShell execution policy | Always use it in hook commands |
| Using `/tmp/` for result JSON | File not found by verifier | Use `C:\Users\Docker\` instead |
| `Out-File` writes UTF-8 BOM | `json.load()` raises parse error | Open with `encoding='utf-8-sig'` in Python |
| `ConvertTo-Json` without `-Depth` | Nested dicts truncated to `"System.Collections.Hashtable"` | Always add `-Depth 5` |
| App launched via SSH (Session 0) | App starts but has no window / crashes | Use `schtasks /IT` via `task_utils.ps1` helpers |
| `date +%s` in PowerShell | Syntax error (bash command) | Use `[int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()` |
| `Send-PyAutoGUI` not found | NameError in setup script | Correct function is `Invoke-PyAutoGUICommand`; always check actual task_utils.ps1 |
| `Invoke-PyAutoGUICommand -Command "hotkey" -Args @("ctrl","s")` | Parameter binding error; command silently ignored | Use hashtable syntax: `Invoke-PyAutoGUICommand -Command @{action="press"; keys="ctrl+s"} \| Out-Null` |
| `$ErrorActionPreference = "Stop"` in task scripts | Script aborts on first non-critical error (e.g., dialog dismissal failure), leaving task in bad state | Use `"Continue"` — task scripts must be resilient; non-fatal errors should log, not abort |

---

## 11. Spreadsheet File Verification (Excel / LibreOffice Calc)

For environments where the agent's output is a spreadsheet file (`.xlsx`, `.ods`), the verifier must read **computed values**, not formula strings. This requires specific handling beyond the standard JSON result pattern.

### Two-layer verification strategy

1. **Export layer** (`export_result.ps1`): Records file metadata (exists, is_new, size) and copies the xlsx to a known path.
2. **Verifier layer** (`verifier.py`): Independently copies the xlsx from the VM and parses it with `openpyxl` using `data_only=True`.

The verifier should NOT rely solely on the export JSON for numerical values — the agent could theoretically manipulate the export script. Independent re-parsing is the authoritative check.

### Verifier pattern for xlsx files

```python
import openpyxl, tempfile, os, json

RESULT_PATH = "C:\\Users\\Docker\\<task_name>_result.json"
XLSX_PATH   = "C:\\Users\\Docker\\Desktop\\ExcelTasks\\<file>.xlsx"

def verify_<task_name>(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    fb = []

    # Step 1: Read export JSON for is_new gate
    result = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, tmp_json.name)
        with open(tmp_json.name, encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}
    finally:
        try: os.unlink(tmp_json.name)
        except: pass

    # Step 2: Anti-gaming gate — file must be new (modified after task start)
    xlsx_info = result.get('xlsx_file', {})
    if not xlsx_info.get('is_new', False):
        return {"passed": False, "score": 0, "feedback": "File not modified after task start (do-nothing)."}

    # Step 3: Independently copy and parse the xlsx
    tmp_xlsx = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    ws = None
    try:
        copy_from_env(XLSX_PATH, tmp_xlsx.name)
        wb = openpyxl.load_workbook(tmp_xlsx.name, data_only=True)  # data_only=True reads computed values
        ws = wb["SheetName"]
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot parse xlsx: {e}"}
    finally:
        try: os.unlink(tmp_xlsx.name)
        except: pass

    # Step 4: Score criteria from cell values
    val = ws["C10"].value  # e.g., volume-weighted LDF
    if val is not None and 1.40 <= float(val) <= 1.45:
        score += 25
        fb.append(f"C1 PASS: VW LDF = {val:.4f}")
    else:
        fb.append(f"C1 FAIL: VW LDF = {val} (expected 1.40–1.45)")

    passed = score >= 60
    return {"passed": passed, "score": min(score, 100), "feedback": " | ".join(fb)}
```

### Key rules for spreadsheet verifiers

1. **Always use `data_only=True`** — without it, `cell.value` returns the formula string (e.g., `"=SUM(B4:B8)"`) not the computed result.

2. **`None` means uncomputed** — if `data_only=True` returns `None` for a formula cell, the xlsx was saved without calculating (e.g., saved by a script, not by Excel itself). Treat `None` as blank/wrong.

3. **Scan ranges, don't hardcode single cells** — agents may write formulas in adjacent cells rather than exactly the expected cell. Scan a region and find the first valid value:
   ```python
   def _find_in_range(ws, rows, cols, lo, hi):
       for r in rows:
           for c in cols:
               v = ws.cell(r, c).value
               try:
                   fv = float(v)
                   if lo <= fv <= hi:
                       return fv
               except (TypeError, ValueError):
                   pass
       return None
   ```

4. **Sheet names are case-sensitive in openpyxl** — use `wb.sheetnames` to discover available sheets before accessing by name.

5. **Set tolerance ranges from real computed values** (see Lesson 153 in `05_learnings_best_practices.md`) — derive expected ranges by running the real data through the formula, not from synthetic test data.

---

## 12. Word Document Verification (DOCX / OOXML)

For environments where the agent's output is a Word document (`.docx`), the verifier must inspect the underlying OOXML XML directly using Python's `zipfile` module. A `.docx` file is a ZIP archive containing structured XML files; no external library is required.

### Two-layer verification strategy

1. **Export layer** (`export_result.ps1`): Records file metadata (exists, is_new, size) for the output `.docx` file. Also triggers a final `Ctrl+S` save before collection.
2. **Verifier layer** (`verifier.py`): Independently copies the `.docx` from the VM using `copy_from_env`, opens it as a ZIP, parses `word/document.xml` (and other part files), and applies regex checks on the raw XML.

### Verifier pattern for .docx files

```python
import json, re, os, shutil, tempfile, zipfile, logging

RESULT_PATH = "C:\\Users\\Docker\\<task_name>_result.json"
DOCX_PATH   = "C:/Users/Docker/Desktop/WordTasks/<output>.docx"

logger = logging.getLogger(__name__)

def verify_<task_name>(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.mkdtemp(prefix="verify_task_")
    try:
        # Step 1: Read result JSON for is_new gate
        result = {}
        json_local = os.path.join(tmp, "result.json")
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, encoding="utf-8-sig") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read result JSON: {e}")

        if not result.get("output_file", {}).get("final_is_new", False):
            return {"passed": False, "score": 0,
                    "feedback": "FAIL: output file not saved after task started (is_new=False)"}

        # Step 2: Copy and validate the docx
        docx_local = os.path.join(tmp, "output.docx")
        copy_from_env(DOCX_PATH, docx_local)

        if not zipfile.is_zipfile(docx_local):
            return {"passed": False, "score": 0, "feedback": "Output is not a valid .docx file"}

        score = 0
        fb = []

        with zipfile.ZipFile(docx_local, "r") as zf:
            doc_xml = zf.read("word/document.xml").decode("utf-8", errors="replace")

            # --- heading style counts ---
            h1_count = len(re.findall(r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*1"', doc_xml))
            if h1_count == 0:   # Word may omit the space: "Heading1"
                h1_count = len(re.findall(r'<w:pStyle\b[^/]*w:val="[Hh]eading1"', doc_xml))

            h2_count = len(re.findall(r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*2"', doc_xml))
            if h2_count == 0:
                h2_count = len(re.findall(r'<w:pStyle\b[^/]*w:val="[Hh]eading2"', doc_xml))

            # --- Table of Contents field ---
            has_toc = bool(re.search(r'<w:instrText[^>]*>\s*TOC\b', doc_xml, re.IGNORECASE))
            if not has_toc:
                has_toc = bool(re.search(r'TOC\\', doc_xml))  # older TOC switch style

            # --- table count ---
            table_count = len(re.findall(r"<w:tbl\b", doc_xml))

            # --- tracked changes (should be zero after "Accept All") ---
            ins_count = len(re.findall(r"<w:ins\b", doc_xml))
            del_count = len(re.findall(r"<w:del\b", doc_xml))

            # --- footnotes ---
            footnote_count = 0
            if "word/footnotes.xml" in zf.namelist():
                fn_xml = zf.read("word/footnotes.xml").decode("utf-8", errors="replace")
                all_fn = len(re.findall(r"<w:footnote\b", fn_xml))
                footnote_count = max(0, all_fn - 2)  # Word always adds 2 separator footnotes

            # --- headers ---
            for name in zf.namelist():
                if "header" in name.lower() and name.endswith(".xml"):
                    hdr_xml = zf.read(name).decode("utf-8", errors="replace")
                    # check keywords: e.g., "meridian" in hdr_xml.lower()

            # --- footers ---
            for name in zf.namelist():
                if "footer" in name.lower() and name.endswith(".xml"):
                    ftr_xml = zf.read(name).decode("utf-8", errors="replace")
                    # check keywords: e.g., "confidential" in ftr_xml.lower()

            # --- custom styles ---
            if "word/styles.xml" in zf.namelist():
                styles_xml = zf.read("word/styles.xml").decode("utf-8", errors="replace")
                # check: re.search(r'MyCustomStyle', styles_xml)

        return {"passed": score >= 60, "score": score, "feedback": " | ".join(fb)}

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
```

### Key OOXML regex patterns

| What to check | XML part | Regex |
|---|---|---|
| Heading 1 style applied to paragraph | `word/document.xml` | `<w:pStyle\b[^/]*w:val="[Hh]eading\s*1"` (also try `"[Hh]eading1"` — Word omits the space in some builds) |
| Heading 2 style | `word/document.xml` | same pattern with `\s*2` |
| Table of Contents (instrText field) | `word/document.xml` | `<w:instrText[^>]*>\s*TOC\b` |
| Table presence | `word/document.xml` | `<w:tbl\b` |
| Table row count | `word/document.xml` | `<w:tr\b` |
| Tracked insertion remaining | `word/document.xml` | `<w:ins\b` (count should be 0 after "Accept All") |
| Tracked deletion remaining | `word/document.xml` | `<w:del\b` (count should be 0 after "Accept All") |
| Footnote count | `word/footnotes.xml` | `<w:footnote\b` — subtract 2 for Word's mandatory separator footnotes |
| Custom style defined | `word/styles.xml` | Search for style name string |
| Header content | `word/header1.xml`, `word/header2.xml`, etc. | Iterate `zf.namelist()` for names matching `"header"` and `".xml"` |
| Footer content | `word/footer1.xml`, etc. | Same pattern with `"footer"` |
| Specific text in body | `word/document.xml` | Plain `in` check on decoded XML (text between `<w:t>` tags is inline; regex on raw XML is sufficient for existence checks) |

### Rules and pitfalls

1. **Always check both space variants for heading styles** — Word 2010 sometimes omits the space between "Heading" and "1": `val="Heading1"` vs `val="Heading 1"`. Check both or use `\s*`.

2. **Footnote separator footnotes** — `word/footnotes.xml` always contains at least 2 `<w:footnote>` elements with `w:type="separator"` and `w:type="continuationSeparator"`. These are not user-created footnotes. Always subtract 2 (or filter by `w:type`) when counting user footnotes.

3. **Headers and footers may have multiple part files** — Word creates `word/header1.xml` (default), `word/header2.xml` (first page), `word/header3.xml` (even pages) and corresponding footer files. Iterate `zf.namelist()` rather than hardcoding a single filename.

4. **Text in document.xml is not plain text** — Paragraph text is split across multiple `<w:t>` elements (e.g., with revision markup, spell-check spans, or field codes). Regex on raw XML is sufficient for existence checks (`"sublicensable" in doc_xml.lower()`), but extracting clean running text requires stripping all tags (`re.sub(r"<[^>]+>", " ", doc_xml)`).

5. **TOC may use either `<w:instrText>` or a content control SDT** — Older Word documents use `<w:instrText> TOC \o "1-3" </w:instrText>`. Check both `<w:instrText[^>]*>\s*TOC\b` and `TOC\\` (the switch style used in SDT-wrapped TOCs).

6. **OOXML tracked changes injection** — To create a task artifact with pre-seeded tracked changes (for a "accept all tracked changes" task), you can programmatically inject `<w:del>` / `<w:ins>` OOXML into `word/document.xml` inside a Python script using `zipfile`: read the original XML, replace marker text with proper OOXML tracked-change elements, write back. The injected elements require `w:id`, `w:author`, and `w:date` attributes. Use monotonically increasing `w:id` values to avoid duplicate-ID Word repair dialogs on open.

7. **`is_new` gate is mandatory** — Always check `output_file.final_is_new` from the result JSON before attempting to copy the docx. If the agent never saved a new file, `copy_from_env` will either fail or return the pre-task seed file — causing false positives.

## 13. PowerShell Hook Stdout Encoding

Windows PowerShell defaults to OEM encoding (CP850 / Windows-1252) for console output. When the Gym-Anything framework captures hook stdout over SSH and attempts to decode it as UTF-8, any byte outside the ASCII range causes:

```
pre_task hook failed: 'utf-8' codec can't decode byte 0x83 in position ...
```

This happens even when the script itself succeeds. Common triggers: `dotnet build` progress bars, NuGet restore output with special characters, or progress spinners from any .NET CLI command.

**Fix — add this at the top of every setup_task.ps1 and export_result.ps1:**

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

Place these two lines immediately after `Set-StrictMode -Version Latest` and before any `dotnet` commands. This forces all console output to valid UTF-8, eliminating the false-failure warnings.

**Important**: The framework logs this as "hook failed" with a Python traceback, but the script may have actually completed and succeeded. Always verify by checking whether expected artifacts (e.g., the project directory, the solution file) were created — not just by whether the hook log is clean.

## 14. PowerShell `Set-Content` / `Out-File` Does Not Auto-Create Parent Directories

Unlike bash `echo > path/to/file` with `mkdir -p`, PowerShell's `Set-Content` and `Out-File` throw a terminating error if any parent directory in the path does not exist:

```
Set-Content: Could not find a part of the path 'C:\Users\Docker\source\repos\MyProject\Models\Foo.cs'
```

This silently aborts the rest of the setup script when `$ErrorActionPreference = "Stop"` is set (which it always should be).

**Fix — always create subdirectories explicitly before writing files:**

```powershell
# BAD — will fail if Models\ doesn't exist yet:
Set-Content "$ProjectDir\Models\Patient.cs" $patientClass

# GOOD — create the directory first:
New-Item -ItemType Directory -Force -Path "$ProjectDir\Models" | Out-Null
Set-Content "$ProjectDir\Models\Patient.cs" $patientClass
```

**Pattern for multi-subdirectory projects**: Create all subdirectories in a single block immediately after `New-Item ... -ItemType Directory` creates the project root, before any `Set-Content`/`Out-File` calls that write into subdirectories:

```powershell
New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectDir\Models" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectDir\Services" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectDir\Controllers" | Out-Null
# Now safe to Set-Content into any of those subdirs
```

## 15. Named Parameter Binding Trap in Shared PowerShell Utility Functions

Shared utility scripts (like `task_utils.ps1`) define functions with mandatory named parameters. Calling these functions with positional arguments silently binds the value to the wrong parameter, causing cryptic failures.

**Real example**: `Launch-VS2022Interactive` has the signature:

```powershell
function Launch-VS2022Interactive {
    param(
        [Parameter(Mandatory=$true)]  [string] $DevenvExe,
        [Parameter(Mandatory=$false)] [string] $SolutionPath = "",
        [Parameter(Mandatory=$false)] [int]    $WaitSeconds  = 20
    )
    ...
}
```

Calling it as `Launch-VS2022Interactive $SlnPath` passes the .sln path as `-DevenvExe`, causing VS to be launched with the wrong executable path (and failing silently or with a confusing error).

**Fix — always use named parameters for utility function calls:**

```powershell
# BAD:
Launch-VS2022Interactive $SlnPath

# GOOD:
$devenvExe = Find-VS2022Exe
Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $SlnPath -WaitSeconds 25
```

**General rule**: Before calling ANY function from a shared utility script, read its `param(...)` block to verify parameter names and order. Do not assume positional binding matches the intuitive call order. This is especially critical for functions that launch long-running processes (VS, applications), since a wrong argument may cause the launch to appear to succeed (process starts) while the workspace is in the wrong state.

---

## 16. Maximize Application Window Before Dialog Interactions

Many Windows desktop applications clip their dialog boxes to the application window's viewport. If the application is running in a non-maximized (windowed) state, dialog buttons at the bottom of the dialog — "Save", "OK", "Apply", "Confirm" — may be partially or completely outside the visible area and unclickable.

**Symptom**: A click at the expected dialog button coordinates produces no response, or the click lands on the window chrome/desktop behind the dialog.

**When this matters**: Any task that involves saving a file, confirming a dialog, or completing a multi-step wizard inside a windowed (non-maximized) application.

**Fix — maximize the application window early in the setup or pilot interaction:**

```python
# Via PyAutoGUI server: click the maximize button
# The maximize button is typically the middle of the three window control buttons (minimize / maximize / close)
# at the top-right of the window. On 1280x720 at default OAD window size:
import socket, json

def send_action(action, **kwargs):
    payload = json.dumps({"action": action, **kwargs})
    with socket.create_connection(("localhost", 5557), timeout=5) as s:
        s.sendall(payload.encode())
        return json.loads(s.recv(4096))

# Click the maximize button (discover coordinates via pilot screenshot + visual_grounding)
send_action("click", x=909, y=40)   # example: OAD maximize at 1280x720
```

Alternatively, use a keyboard shortcut if the application supports it (`Win+Up` maximizes the focused window on Windows 11):

```python
send_action("hotkey", keys=["win", "up"])
```

**When to discover coordinates**: During the pilot trajectory, take a screenshot immediately after the application opens and use `visual_grounding` to identify the maximize button's pixel coordinates at the exact resolution the task will run at. Record these coordinates in `evidence_docs/README.md` under the "UI Coordinates" section for the environment.

**General rule**: For any windowed desktop app in a Windows environment, **always maximize the window before interacting with any dialog** during pilot testing or in setup scripts that invoke GUI actions. Never assume the window opens maximized.

---

## 17. Discover GUI Automation Server Protocol by Reading the Server Source

The GymAnything Windows runtime includes a PyAutoGUI TCP server for programmatic GUI interaction, but the server's exact wire protocol — field names, supported action names, port assignment — may vary across environments or server versions. Do NOT assume a protocol based on documentation or examples from a different environment.

**What can vary:**
- The JSON key for the action type: may be `"action"`, `"type"`, `"cmd"`, or `"command"` depending on which server script is running.
- The set of supported action names: not all servers support all actions (`scroll`, `drag`, `rightClick`, etc.).
- The host port: the server always listens on a fixed guest port (commonly 5555), but the host-side forwarded port varies per run. Read it from `env_info` or the environment configuration.

**Correct approach — read the actual server script:**

```bash
# Over SSH, find and read the running server script:
ssh -p <host_port> Docker@localhost "Get-Process python* | Select-Object -First 1" 2>/dev/null
ssh -p <host_port> Docker@localhost "Get-Content 'C:\Windows\Temp\pyautogui_server.py'" 2>/dev/null
```

Look for:
1. The field it reads from the JSON request: `data.get("action")` vs `data.get("type")` etc.
2. The dispatch table: which action names map to which pyautogui calls.
3. The `host` and `port` it listens on.

**Only after reading the source** should you write or test any GUI automation code against this server. A single wrong field name causes every action to silently fail with no error (the server typically ignores unknown keys rather than returning an error).

**Document findings in `evidence_docs/README.md`**: Record the protocol field name, port, and supported actions once verified, so future task creators for the same environment do not repeat the discovery work.
