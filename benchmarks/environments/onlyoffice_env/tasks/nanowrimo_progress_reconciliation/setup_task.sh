#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up NaNoWriMo Progress Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy raw data spreadsheet
SHEET_PATH="$WORKSPACE_DIR/nano_wordcount_raw.xlsx"

cat > /tmp/create_nano_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys
from datetime import datetime, timedelta

wb = Workbook()
ws = wb.active
ws.title = "Raw Data"

# Add headers
ws['A1'] = "Date"
ws['B1'] = "Day"
ws['C1'] = "Project"
ws['D1'] = "Words Written"
ws['E1'] = "Notes"

# Make headers bold
for cell in ws[1]:
    cell.font = Font(bold=True)

# Starting date (November 1st)
start_date = datetime(2024, 11, 1)

# Raw data with multiple entries per day, some missing days
# Project Alpha: Days 1-13 (~14,950 words)
# Project Beta: Days 14-18 (~9,500 words)
# Total: ~24,450 words

raw_entries = [
    # Day 1
    (1, "Project Alpha", 1200, "Morning writing session"),
    # Day 2
    (2, "Project Alpha", 1400, "Evening burst"),
    # Day 3 - Multiple sessions
    (3, "Project Alpha", 800, "Morning"),
    (3, "Project Alpha", 650, "Late night"),
    # Day 4
    (4, "Project Alpha", 1250, "Afternoon write-in"),
    # Day 5
    (5, "Project Alpha", 950, "Coffee shop session"),
    # Day 6 - Multiple sessions
    (6, "Project Alpha", 1100, "Morning sprint"),
    (6, "Project Alpha", 600, "Evening continuation"),
    # Day 7 - MISSING (forgot to log)
    # Day 8
    (8, "Project Alpha", 1350, "Caught up after missing day"),
    # Day 9
    (9, "Project Alpha", 1150, "Library session"),
    # Day 10
    (10, "Project Alpha", 800, "Short session - busy day"),
    # Day 11 - MISSING (life happened)
    # Day 12
    (12, "Project Alpha", 1500, "Weekend writing marathon"),
    # Day 13
    (13, "Project Alpha", 1200, "Final Alpha push - feeling stuck"),
    # Day 14 - Switched projects!
    (14, "Project Beta", 1850, "NEW PROJECT! Fresh excitement!"),
    # Day 15
    (15, "Project Beta", 2100, "Flow state achieved"),
    # Day 16
    (16, "Project Beta", 1900, "Still going strong"),
    # Day 17 - Multiple sessions
    (17, "Project Beta", 1600, "Morning sprint"),
    (17, "Project Beta", 750, "Evening session"),
    # Day 18
    (18, "Project Beta", 1300, "Today's progress so far"),
]

# Write data
row = 2
for day_num, project, words, notes in raw_entries:
    date = start_date + timedelta(days=day_num - 1)
    ws[f'A{row}'] = date.strftime("%Y-%m-%d")
    ws[f'B{row}'] = day_num
    ws[f'C{row}'] = project
    ws[f'D{row}'] = words
    ws[f'E{row}'] = notes
    row += 1

# Add task instructions at the top of a second sheet
instructions = wb.create_sheet("TASK INSTRUCTIONS", 0)
instructions['A1'] = "NaNoWriMo Progress Dashboard - Task Instructions"
instructions['A1'].font = Font(bold=True, size=14)

instructions['A3'] = "SITUATION:"
instructions['A3'].font = Font(bold=True)
instructions['A4'] = "• You're on Day 18 of NaNoWriMo (write 50,000 words in 30 days)"
instructions['A5'] = "• You started with Project Alpha but got stuck at ~15,000 words"
instructions['A6'] = "• On Day 14, you switched to Project Beta (a completely different story)"
instructions['A7'] = "• Your word count data is MESSY (multiple sessions per day, missing days)"
instructions['A8'] = "• You need to know: CAN YOU STILL HIT 50,000 WORDS BY DAY 30?"

instructions['A10'] = "YOUR TASK:"
instructions['A10'].font = Font(bold=True)
instructions['A11'] = "Create a Progress Dashboard (on the Raw Data sheet or a new sheet) that shows:"
instructions['A12'] = "1. Total words written across BOTH projects"
instructions['A13'] = "2. Current daily average (total words ÷ 18 days)"
instructions['A14'] = "3. Words remaining to hit 50,000"
instructions['A15'] = "4. Required daily pace for the remaining 12 days"
instructions['A16'] = "5. Status: 'ON TRACK' or 'BEHIND' (threshold: 30,000 words by Day 18)"

instructions['A18'] = "REQUIREMENTS:"
instructions['A18'].font = Font(bold=True)
instructions['A19'] = "• Consolidate multiple entries from the same day into daily totals"
instructions['A20'] = "• Use FORMULAS (not manual calculations)"
instructions['A21'] = "• Use BOLD HEADERS for sections"
instructions['A22'] = "• Use COLOR/FORMATTING to highlight the status (green=on track, red=behind)"
instructions['A23'] = "• Include a cumulative total column"
instructions['A24'] = "• Make it SCANNABLE - you're stressed and need clarity NOW!"

instructions['A26'] = "HINT: Check the 'Raw Data' sheet for all your word counts!"
instructions['A26'].font = Font(italic=True)

# Adjust column widths
for col in ['A', 'B', 'C', 'D', 'E']:
    instructions.column_dimensions[col].width = 70

ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 8
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 35

wb.save(sys.argv[1])
print(f"NaNoWriMo raw data spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_nano_sheet.py
python3 /tmp/create_nano_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_nano_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_nano_task.log || true
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

echo "=== NaNoWriMo Progress Reconciliation Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "  You're on Day 18 of NaNoWriMo (50,000 words in 30 days)"
echo "  You switched from Project Alpha to Project Beta on Day 14"
echo "  Your word count data is scattered and messy"
echo ""
echo "❓ THE QUESTION:"
echo "  Can you still hit 50,000 words by Day 30?"
echo "  What daily pace do you need for the remaining 12 days?"
echo ""
echo "📝 YOUR TASK:"
echo "  1. Consolidate the messy data (multiple entries per day)"
echo "  2. Calculate total words written (~24,450 across both projects)"
echo "  3. Calculate current daily average"
echo "  4. Determine if you're ON TRACK or BEHIND (threshold: 30,000 words)"
echo "  5. Calculate required daily pace: (50,000 - total) ÷ 12 days remaining"
echo ""
echo "✨ FORMATTING:"
echo "  • Use bold headers for sections"
echo "  • Use formulas (not manual entry)"
echo "  • Color-code the status (green/red)"
echo "  • Create a cumulative total column"
echo ""
echo "💾 Save with Ctrl+S when done"
echo ""
echo "Expected results:"
echo "  • Total words: ~24,450"
echo "  • Status: BEHIND (need 30,000 by Day 18)"
echo "  • Required pace: ~2,130 words/day for remaining 12 days"