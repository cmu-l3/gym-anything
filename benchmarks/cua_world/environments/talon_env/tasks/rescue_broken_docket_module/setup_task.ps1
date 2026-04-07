Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_rescue_broken_docket_module.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up rescue_broken_docket_module task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # -----------------------------------------------------------------------
    # 1. Delete stale outputs from previous runs BEFORE recording timestamp
    # -----------------------------------------------------------------------

    # Remove any previously created docket_module directory
    $targetDir = "$Script:TalonUserDir\docket_module"
    if (Test-Path $targetDir) {
        Remove-Item -Recurse -Force $targetDir
        Write-Host "Removed stale docket_module directory"
    }

    # Remove any previously generated report file
    $reportPath = "C:\Users\Docker\Desktop\TalonTasks\docket_report.txt"
    if (Test-Path $reportPath) {
        Remove-Item -Force $reportPath
        Write-Host "Removed stale docket_report.txt"
    }

    # Remove stale result JSON
    $resultFile = "C:\Users\Docker\rescue_broken_docket_module_result.json"
    if (Test-Path $resultFile) {
        Remove-Item -Force $resultFile
        Write-Host "Removed stale result JSON"
    }

    # -----------------------------------------------------------------------
    # 2. Record task start timestamp (AFTER cleanup)
    # -----------------------------------------------------------------------
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_rescue_broken_docket_module.txt", $timestamp)
    Write-Host "Task start time recorded: $timestamp"

    # -----------------------------------------------------------------------
    # 3. Ensure the court_docket.csv data file is available
    # -----------------------------------------------------------------------
    $csvSource = "C:\workspace\data\court_docket.csv"
    if (-not (Test-Path $csvSource)) {
        throw "Data file not found: $csvSource"
    }
    Write-Host "Verified CSV data exists at: $csvSource"

    # Ensure TalonTasks directory exists for report output
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\TalonTasks" | Out-Null

    # -----------------------------------------------------------------------
    # 4. Create the docket_module directory with buggy/incomplete files
    # -----------------------------------------------------------------------
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Write-Host "Created module directory: $targetDir"

    # -----------------------------------------------------------------------
    # Buggy file 1: docket_engine.py
    #   BUG A: Wrong CSV path (missing /data/ subdirectory)
    #   BUG B: Wrong datetime format string (%m/%d/%Y instead of %Y-%m-%d %H:%M)
    #   INCOMPLETE: Three TODO actions not yet implemented
    # -----------------------------------------------------------------------
    $pyContent = @'
from talon import Module, actions, app, clip
import csv
import os
from datetime import datetime

mod = Module()
mod.list("docket_field", desc="Court docket CSV column names")

# Path to the court docket CSV
DOCKET_CSV = "C:/workspace/court_docket.csv"

_cases = []
_fields = []


def _load_docket():
    """Load court docket data from CSV."""
    global _cases, _fields
    _cases = []
    try:
        with open(DOCKET_CSV, newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            _fields = reader.fieldnames or []
            for row in reader:
                _cases.append(row)
        app.notify(f"Docket loaded: {len(_cases)} cases")
    except Exception as e:
        app.notify(f"Failed to load docket: {e}")


app.register("ready", _load_docket)


@mod.action_class
class DocketActions:
    def docket_search(field: str, value: str):
        """Search docket by field and value."""
        results = [c for c in _cases if value.lower() in c.get(field, '').lower()]
        if results:
            summary = f"Found {len(results)} case(s):\n"
            for r in results[:10]:
                summary += f"  {r['case_number']}: {r['defendant']} - {r['case_type']} ({r['status']})\n"
            if len(results) > 10:
                summary += f"  ... and {len(results) - 10} more\n"
            clip.set_text(summary)
            app.notify(f"Found {len(results)} case(s) - copied to clipboard")
        else:
            app.notify(f"No cases found for {field}={value}")

    def docket_upcoming(days: int):
        """Show hearings within N days from today."""
        today = datetime.now()
        upcoming = []
        for c in _cases:
            try:
                hearing = datetime.strptime(c['next_hearing'], '%m/%d/%Y')
                diff = (hearing - today).days
                if 0 <= diff <= days:
                    upcoming.append((diff, c))
            except ValueError:
                continue
        upcoming.sort(key=lambda x: x[0])
        if upcoming:
            summary = f"Upcoming hearings (next {days} days):\n"
            for diff, c in upcoming:
                summary += f"  [{diff}d] {c['case_number']}: {c['defendant']} in {c['courtroom']}\n"
            clip.set_text(summary)
            app.notify(f"{len(upcoming)} upcoming hearing(s) - copied to clipboard")
        else:
            app.notify(f"No hearings in the next {days} days")

    # TODO: Implement docket_judge_workload() - count cases per judge, display via app.notify()
    # TODO: Implement docket_high_priority() - list all Active + High priority cases
    # TODO: Implement docket_export_report() - write report to C:\Users\Docker\Desktop\TalonTasks\docket_report.txt
'@
    [System.IO.File]::WriteAllText("$targetDir\docket_engine.py", $pyContent)
    Write-Host "Created buggy docket_engine.py (wrong path, wrong date format, missing functions)"

    # -----------------------------------------------------------------------
    # Buggy file 2: docket.talon
    #   BUG C: Calls user.docket_find but Python defines docket_search
    #   BUG D: Uses {user.docket_fields} (plural) but Python declares mod.list("docket_field") (singular)
    #   INCOMPLETE: Missing voice commands for the three TODO actions
    # -----------------------------------------------------------------------
    $talonContent = @'
-
docket search <user.docket_fields> for <user.text>:
    user.docket_find(docket_fields, text)

docket upcoming <number> days:
    user.docket_upcoming(number)

# TODO: Add voice commands for docket_judge_workload, docket_high_priority, docket_export_report
'@
    [System.IO.File]::WriteAllText("$targetDir\docket.talon", $talonContent)
    Write-Host "Created buggy docket.talon (wrong action name, wrong list name, missing commands)"

    # -----------------------------------------------------------------------
    # Incomplete file 3: docket_fields.talon-list
    #   BUG D (continued): Header says user.docket_fields but Python declares docket_field
    #   INCOMPLETE: Only 5 of 10 CSV columns mapped
    # -----------------------------------------------------------------------
    $listContent = @'
list: user.docket_fields
-
case number: case_number
defendant: defendant
judge: judge
status: status
priority: priority
'@
    [System.IO.File]::WriteAllText("$targetDir\docket_fields.talon-list", $listContent)
    Write-Host "Created incomplete docket_fields.talon-list (wrong header name, 5 of 10 columns)"

    # -----------------------------------------------------------------------
    # 5. Launch Talon Voice and dismiss startup dialogs
    # -----------------------------------------------------------------------
    Write-Host "Launching Talon Voice..."
    Launch-TalonInteractive
    Start-Sleep -Seconds 5

    # Dismiss EULA dialog (appears on every fresh launch after checkpoint restore)
    Write-Host "Dismissing Talon EULA dialog..."
    $eulaPositions = @(@(627, 433), @(648, 458), @(700, 511), @(717, 552))
    foreach ($pos in $eulaPositions) {
        $result = PyAutoGUI-Click -X $pos[0] -Y $pos[1]
        Write-Host "  EULA click ($($pos[0]),$($pos[1])): $result"
        Start-Sleep -Seconds 2
    }

    # Dismiss audio error notification (X button)
    Start-Sleep -Seconds 3
    Write-Host "Dismissing audio notification..."
    $result = PyAutoGUI-Click -X 1242 -Y 572
    Write-Host "  Audio notification click: $result"
    Start-Sleep -Seconds 2

    Write-Host "Talon launched and dialogs dismissed."

    # -----------------------------------------------------------------------
    # 6. Open the primary buggy file in Notepad++ so the agent can edit it
    # -----------------------------------------------------------------------
    Open-FileInteractive -FilePath "$targetDir\docket_engine.py" -WaitSeconds 8

    # Also open File Explorer at the module directory for navigation
    Open-FolderInteractive -FolderPath $targetDir -WaitSeconds 3

    # -----------------------------------------------------------------------
    # 7. Minimize terminal windows
    # -----------------------------------------------------------------------
    Minimize-TerminalWindows

    Write-Host "=== rescue_broken_docket_module task setup complete ==="
    Write-Host "=== Module dir: $targetDir (3 buggy/incomplete files) ==="
    Write-Host "=== CSV data:   $csvSource (80 court cases) ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
