#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Audiobook Speed Experiment Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with partial experimental data
SHEET_PATH="$WORKSPACE_DIR/audiobook_experiment_raw.xlsx"

cat > /tmp/create_audiobook_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Experiment Data"

# Add headers with bold formatting
headers = ["Date", "Book Title", "Genre", "Speed", "Duration (min)", 
           "Chapters Completed", "Comprehension Score", "Comfort Level", "Notes"]

for col_num, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_num, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Add partial experimental data (9 entries, with some missing data)
# User will need to add 3-4 more from text notes
data_rows = [
    ["5/10/2024", "The Midnight Library", "Fiction", "1.25x", 50, 4, 8, 7, "Comfortable pace"],
    ["5/11/2024", "Sapiens", "Non-Fiction", "1.0x", 45, 2, 9, 9, "Too slow but clear"],
    ["5/13/2024", "The Midnight Library", "Fiction", "1.5x", 42, 4, 9, 8, "Good speed for fiction"],
    ["5/14/2024", "Thinking Fast and Slow", "Non-Fiction", "1.0x", 50, 2, 10, 8, "Felt slow"],
    ["5/16/2024", "The Martian", "Fiction", "1.5x", 40, 3, 8, 8, "Enjoyable"],
    ["5/17/2024", "Sapiens", "Non-Fiction", "1.5x", 38, 2, 7, 6, "Too fast for concepts"],
    ["5/19/2024", "Project Hail Mary", "Fiction", "1.25x", 48, 3, 9, 8, "Could go faster"],
    ["5/20/2024", "Atomic Habits", "Non-Fiction", "1.25x", 45, 2, 8, 8, "Comfortable"],
    ["5/21/2024", "The Martian", "Fiction", "1.75x", 35, 3, 7, 6, "Slightly too fast"],
]

for row_idx, row_data in enumerate(data_rows, start=2):
    for col_idx, value in enumerate(row_data, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

# Adjust column widths for readability
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 14
ws.column_dimensions['I'].width = 25

wb.save(sys.argv[1])
print(f"Audiobook experiment spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_audiobook_sheet.py
python3 /tmp/create_audiobook_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Create the additional notes text file
NOTES_PATH="$WORKSPACE_DIR/experiment_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
Audiobook Speed Experiment - Additional Notes
==============================================

Session from 5/12/2024:
Tried "Atomic Habits" at 1.75x - way too fast, couldn't keep up with the concepts. 
Stopped after 15 minutes. Comprehension maybe 4/10. Comfort level 3/10. Not comfortable at all.
Only got through 1 chapter before giving up.

Session from 5/15/2024:
"Project Hail Mary" at 1.5x was PERFECT! Finished 3 chapters in 45 minutes during my commute. 
Still caught every joke and plot point. Comprehension definitely 9/10, comfort 9/10. 
This feels like the sweet spot for fiction books!

Session from 5/18/2024:
Back to non-fiction - "Thinking Fast and Slow" at 1.25x. 
Comfortable (8/10 comfort) but feels a bit slow - I think I could go faster. 
Comprehension is excellent though (9/10). Did 2 chapters in 50 minutes.

---

GENERAL THOUGHTS:
- Fiction seems to handle faster speeds better - less need to pause and think
- Non-fiction needs processing time but 1.0x is definitely too slow for my taste
- Need to calculate actual time savings to see if this optimization is worth it
- Target: Find speed where comprehension stays above 8/10
- Would love to know how much time I could save over a year if I optimize this
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Notes file created at: $NOTES_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_audiobook_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_audiobook_task.log || true
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

echo "=== Audiobook Speed Experiment Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "CONTEXT: You're testing different audiobook speeds to optimize your"
echo "45-minute daily commute. Your data is scattered and incomplete."
echo ""
echo "YOUR TASKS:"
echo ""
echo "1. DATA CONSOLIDATION (30%)"
echo "   • Open experiment_notes.txt (in same folder)"
echo "   • Transfer the 3 missing sessions into the spreadsheet"
echo "   • Parse informal notes into structured rows"
echo "   • Ensure all 12+ sessions are recorded"
echo ""
echo "2. ADD CALCULATED COLUMNS (25%)"
echo "   • Column J: 'Baseline Time' - Duration * Speed (e.g., 45 min at 1.5x = 67.5 min at 1.0x)"
echo "   • Column K: 'Time Saved (min)' - Baseline Time minus Actual Duration"
echo "   • Column L: 'Efficiency Score' - (Time Saved * Comprehension Score / 10)"
echo "   • USE FORMULAS, not hardcoded values!"
echo ""
echo "3. CREATE ANALYSIS SUMMARY SHEET (25%)"
echo "   • Create new sheet named 'Analysis Summary'"
echo "   • Calculate: Average Comprehension by Speed (1.0x, 1.25x, 1.5x, 1.75x)"
echo "   • Calculate: Average Comprehension by Genre (Fiction vs Non-Fiction)"
echo "   • Calculate: Total Time Saved across all sessions"
echo "   • Identify: Optimal speed for each genre (highest efficiency with comprehension ≥ 8)"
echo ""
echo "4. WRITE RECOMMENDATIONS (20%)"
echo "   • In Analysis Summary sheet, add 'Recommendations' section"
echo "   • Recommend optimal speed for Fiction (with data justification)"
echo "   • Recommend optimal speed for Non-Fiction (with data justification)"
echo "   • Project annual time savings (assume ~250 listening days/year)"
echo ""
echo "5. SAVE THE WORKBOOK (Ctrl+S)"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Files: audiobook_experiment_raw.xlsx & experiment_notes.txt"
echo "Pass threshold: 75/100 points"