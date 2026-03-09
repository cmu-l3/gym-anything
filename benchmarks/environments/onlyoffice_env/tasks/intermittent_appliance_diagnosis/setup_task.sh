#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Intermittent Appliance Diagnosis Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with messy raw notes
SHEET_PATH="$WORKSPACE_DIR/washer_notes_raw.xlsx"

cat > /tmp/create_washer_log.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Raw Notes"

# Add header
ws['A1'] = "Date"
ws['B1'] = "Note"
ws['A1'].font = Font(bold=True)
ws['B1'].font = Font(bold=True)

# Column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 70

# Add messy raw notes (realistic scattered data)
raw_notes = [
    ["3/15/2024", "loud grinding noise during spin, had to stop it"],
    ["3/18/2024", "ran fine"],
    ["3/22/2024", "stopped halfway through, error F21 on display, had towels in it"],
    ["3/25/2024", "weird smell? or maybe just the detergent"],
    ["3/29/2024", "LEAKED water all over floor!!! heavy load of jeans"],
    ["4/2/2024", "noise again during spin cycle"],
    ["4/5/2024", "stopped mid-cycle, display blank, wouldn't restart for 10 mins"],
    ["4/8/2024", "fine"],
    ["4/12/2024", "grinding sound on spin, only had light load"],
    ["4/15/2024", "error F21 again, this time just regular clothes"],
    ["4/18/2024", "leaked a little, didn't notice until after"],
    ["4/22/2024", "made it through whole cycle ok"],
    ["4/25/2024", "stopped completely during rinse, had to drain manually"],
    ["4/29/2024", "error code E10, never seen that before"],
    ["5/3/2024", "loud noise, spin cycle, morning"],
    ["5/7/2024", "leaked during spin, medium load of mixed items"],
    ["5/10/2024", "worked fine all week"],
    ["5/14/2024", "grinding noise again, worse than before"],
    ["5/18/2024", "error F21 AGAIN during drain cycle"],
    ["5/22/2024", "small leak, spin cycle, bedsheets"]
]

for i, note in enumerate(raw_notes, start=2):
    ws[f'A{i}'] = note[0]
    ws[f'B{i}'] = note[1]
    ws[f'B{i}'].alignment = Alignment(wrap_text=True)

# Add task instructions at the bottom
ws['A24'] = "TASK INSTRUCTIONS:"
ws['A24'].font = Font(bold=True, size=12)

instructions = [
    "",
    "Create a diagnostic analysis spreadsheet with THREE sheets:",
    "",
    "1. INCIDENT LOG - Structured table with columns:",
    "   - Date (formatted as date)",
    "   - Days Since Last Incident (calculated with formula)",
    "   - Problem Category (Noise/Error Code/Leak/Stopped/Normal)",
    "   - Severity (Low/Medium/High)",
    "   - Cycle Phase (Spin/Rinse/Drain/etc.)",
    "   - Load Type (Heavy/Light/Medium/Unknown)",
    "   - Notes (cleaned up)",
    "   NOTE: Exclude 'ran fine' entries - only actual incidents",
    "",
    "2. PATTERN ANALYSIS - Summary with:",
    "   - Problem frequency table (Category | Count | %)",
    "   - Cycle phase breakdown",
    "   - Key statistics (total incidents, avg days between, most common problem)",
    "   - Pattern observations (at least 2 written observations)",
    "",
    "3. TECHNICIAN SUMMARY - One-page report with:",
    "   - Header with date range",
    "   - Problem overview (brief text)",
    "   - Most frequent issues (top 3 with counts)",
    "   - Critical observations (2-3 bullet points about patterns)",
    "",
    "Context: Machine is 6 years old, issues started ~3 months ago",
    "Error F21 = drain problem, Error E10 = water fill issue",
    "",
    "Save when complete (Ctrl+S)"
]

for i, instruction in enumerate(instructions, start=25):
    ws[f'A{i}'] = instruction

wb.save(sys.argv[1])
print(f"Washing machine log created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_washer_log.py
python3 /tmp/create_washer_log.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_washer_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_washer_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Intermittent Appliance Diagnosis Task Setup Complete ==="
echo "📋 Scenario: Washing machine has intermittent problems for 3 months"
echo "📝 Raw notes are scattered and messy - need to create diagnostic analysis"
echo ""
echo "Required outputs:"
echo "  Sheet 1: Incident Log (structured data, ~12-15 incidents, exclude 'ran fine')"
echo "  Sheet 2: Pattern Analysis (frequency tables, statistics, observations)"
echo "  Sheet 3: Technician Summary (one-page report for repair technician)"
echo ""
echo "💡 Key challenge: Identify patterns in when/how failures occur"
echo "   to help technician diagnose root cause without random part replacement"