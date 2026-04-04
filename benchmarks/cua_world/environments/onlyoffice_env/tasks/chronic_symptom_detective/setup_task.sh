#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Chronic Symptom Detective Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy raw data spreadsheet
SHEET_PATH="$WORKSPACE_DIR/migraine_notes_raw.xlsx"

cat > /tmp/create_messy_data.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys
import random

wb = Workbook()
ws = wb.active
ws.title = "Raw Notes"

# Create messy, realistic raw notes simulating 3 weeks of phone notes
# Each row is a day with inconsistent formatting and scattered information

notes_data = [
    # Week 1
    ["March 3", "Migraine - bad one, 8/10", "Only 5 hrs sleep", "3 coffees", "Very stressed about deadline"],
    ["3/5", "No headache", "7 hours sleep", "normal caffeine", ""],
    ["March 7th", "Migraine severity 6", "6.5 hrs", "had wine and cheese at dinner", "long screen day 10hrs"],
    ["3/8", "Fine", "8 hours", "", ""],
    ["Mar 9", "MIGRAINE 9/10 horrible", "slept ok 7hrs", "too much coffee - 4 cups", "stress level high"],
    ["3/10", "", "7.5 hrs sleep", "2 coffees", "weather changed - barometric pressure drop"],
    ["3/11", "No migraine", "good sleep 8 hrs", "", "relaxing weekend"],
    
    # Week 2
    ["3/12", "Headache starting evening - 4/10", "only 5.5 hours!", "chocolate in afternoon", "period started"],
    ["", "", "", "", ""],  # Empty row (realistic messiness)
    ["March 14", "Migraine all day 7/10", "5 hours terrible sleep", "regular caffeine 2 cups", "high stress + screen time 11hrs"],
    ["3/15", "ok", "7 hrs", "", ""],
    ["3/16", "slight headache 3/10", "6 hrs", "wine at book club", "screen time normal"],
    ["March 17", "no headache", "8.5 hours good sleep", "skipped coffee", "low stress"],
    ["3/18", "MIGRAINE 8/10", "5 hrs sleep again", "4 coffees to stay awake", "screen time 12hrs", "stress 9/10"],
    
    # Week 3
    ["3/19", "better but tired", "7 hrs", "2 coffees", ""],
    ["Mar 20", "Migraine moderate 6/10", "6 hrs", "had aged cheese + wine", "weather: rain coming in"],
    ["3/21", "no migraine!", "8 hrs great sleep", "1 coffee", "good day, low stress"],
    ["3/22", "headache 5/10", "5.5 hrs", "regular caffeine 2-3 cups", "very stressful work day", "screen 10hrs"],
    ["March 23", "ok today", "7.5 hrs", "", "stress moderate"],
    ["3/24", "Migraine 7/10", "poor sleep 5 hrs", "chocolate + wine combo", "period day 2, high stress 8/10"],
    ["3/25", "no headache", "better sleep 8 hrs", "less caffeine 1 cup", "feeling better, stress low"],
]

# Write notes in a messy format (inconsistent column placement)
for row_idx, note_row in enumerate(notes_data, start=1):
    for col_idx, value in enumerate(note_row, start=1):
        # Occasionally shift columns to simulate messy note-taking
        if row_idx > 5 and random.random() < 0.15 and col_idx > 1:
            actual_col = col_idx + random.choice([0, 1])
        else:
            actual_col = col_idx
        
        if value:  # Only write non-empty values
            ws.cell(row=row_idx, column=actual_col, value=value)

# Add some scattered metadata to make it more realistic
ws['G1'] = "📱 Phone notes from past 3 weeks"
ws['G2'] = "Need to organize before doctor appt!"
ws['G3'] = "Dr. Chen wants to see patterns"

ws['H5'] = "Forgot to track some days 😕"

# Make it look handwritten/messy (no formatting)
# This simulates copy-pasted phone notes

wb.save(sys.argv[1])
print(f"Raw migraine notes spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_messy_data.py
python3 /tmp/create_messy_data.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Messy raw data spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_symptom_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_symptom_task.log || true
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

echo "=== Chronic Symptom Detective Task Setup Complete ==="
echo "📋 SCENARIO:"
echo "  Sarah has chronic migraines and needs to organize 3 weeks of messy"
echo "  phone notes before her doctor appointment. The data is scattered and"
echo "  inconsistent - dates in different formats, notes in various columns."
echo ""
echo "📝 YOUR TASK:"
echo "  1. Create a new sheet called 'Symptom Log' (or similar)"
echo "  2. Set up structured columns:"
echo "     - Date (properly formatted)"
echo "     - Migraine (Yes/No)"
echo "     - Severity (1-10 scale)"
echo "     - Sleep Hours"
echo "     - Caffeine (cups or amount)"
echo "     - Stress Level (1-10 or description)"
echo "     - Screen Time (hours)"
echo "     - Notes (additional observations)"
echo ""
echo "  3. Transfer and clean at least 15 days of data from the raw notes"
echo "     - Convert dates to consistent format (not 'March 3rd')"
echo "     - Extract severity numbers from text ('8/10' → 8)"
echo "     - Organize sleep hours, caffeine, stress consistently"
echo ""
echo "  4. Create analysis section with formulas:"
echo "     - Total migraine count (use COUNTIF or similar)"
echo "     - Average severity when migraines occur (use AVERAGEIF)"
echo "     - Comparison stats (e.g., avg sleep on migraine vs non-migraine days)"
echo ""
echo "  5. Format professionally:"
echo "     - Bold headers"
echo "     - Align data appropriately"
echo "     - Clear section separators"
echo ""
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: Look for patterns like 'Migraine 8/10', 'only 5 hrs sleep',"
echo "   '3 coffees', etc. in the raw notes. Extract and organize them."