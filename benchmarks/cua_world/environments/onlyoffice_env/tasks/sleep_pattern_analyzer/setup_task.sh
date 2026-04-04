#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sleep Pattern Analyzer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw sleep notes text file
NOTES_PATH="$WORKSPACE_DIR/sleep_notes_raw.txt"

cat > "$NOTES_PATH" << 'EOF'
Day 1 (Mon 1/15): Bed 11:30pm, awoke 3x, up at 6:45am, felt 4/10, had coffee at 4pm, no exercise, 2hrs phone before bed
Day 2 (Tue 1/16): Bed 12:15am, awoke 2x, up at 7:00am, felt 5/10, coffee at noon, walked 30min, 1hr phone
Day 3 (Wed 1/17): Bed 11:00pm, awoke 4x, up at 6:30am, felt 3/10, coffee 2pm & 5pm, no exercise, 3hrs phone, stressed about work
Day 4 (Thu 1/18): Bed 10:45pm, awoke 1x, up at 6:45am, felt 6/10, coffee at 10am only, ran 45min, 30min phone, felt calm
Day 5 (Fri 1/19): Bed 1:00am, awoke 3x, up at 8:00am, felt 4/10, coffee at 3pm, no exercise, 4hrs phone (social media), stressful day
Day 6 (Sat 1/20): Bed 11:30pm, awoke 2x, up at 7:30am, felt 6/10, no caffeine!, walked 60min, 1hr phone, relaxed day
Day 7 (Sun 1/21): Bed 10:30pm, awoke 1x, up at 7:00am, felt 7/10, no caffeine, yoga 30min, read book (no phone), very relaxed
Day 8 (Mon 1/22): Bed 11:45pm, awoke 3x, up at 6:30am, felt 4/10, coffee at 1pm & 4pm, no exercise, 2hrs phone, work stress
Day 9 (Tue 1/23): Bed 11:00pm, awoke 2x, up at 7:00am, felt 5/10, coffee at noon, walked 40min, 1.5hrs phone
Day 10 (Wed 1/24): Bed 10:15pm, awoke 1x, up at 6:45am, felt 7/10, coffee at 9am only, exercise 60min, no evening phone, calm
Day 11 (Thu 1/25): Bed 12:30am, awoke 4x, up at 7:00am, felt 3/10, coffee at 5pm (!), no exercise, 3hrs phone, fight with partner
Day 12 (Fri 1/26): Bed 11:15pm, awoke 2x, up at 7:15am, felt 5/10, coffee at 2pm, walked 30min, 2hrs phone
Day 13 (Sat 1/27): Bed 10:45pm, awoke 1x, up at 7:30am, felt 7/10, no caffeine, hiked 90min, minimal phone, peaceful
Day 14 (Sun 1/28): Bed 10:00pm, awoke 0x (!), up at 7:00am, felt 8/10, no caffeine, yoga 45min, read book, very relaxed
EOF

chown ga:ga "$NOTES_PATH"
echo "✅ Sleep notes created at: $NOTES_PATH"

# Create a minimal blank spreadsheet as a starter template
STARTER_PATH="$WORKSPACE_DIR/starter.xlsx"

cat > /tmp/create_starter.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Just create a blank spreadsheet
ws['A1'] = ""

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter.py
python3 /tmp/create_starter.py "$STARTER_PATH"
chown ga:ga "$STARTER_PATH"

echo "✅ Starter spreadsheet created"

# Open the text file in a text editor for reference (in background)
echo "Opening text file for reference..."
sudo -u ga DISPLAY=:1 xdg-open "$NOTES_PATH" > /tmp/text_editor.log 2>&1 &
sleep 2

# Launch ONLYOFFICE Spreadsheet with the starter file
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$STARTER_PATH' > /tmp/onlyoffice_sleep_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sleep_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Sleep Pattern Analyzer Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  You have messy sleep diary notes at:"
echo "  $NOTES_PATH"
echo ""
echo "  Create a spreadsheet named 'sleep_analysis.xlsx' with:"
echo "  1. Columns (A-J): Date, Bedtime, Wake Time, Times Awoke, Sleep Quality,"
echo "     Total Hours in Bed (calculated), Caffeine After Noon?, Exercise Minutes,"
echo "     Screen Time Hours, Stress Level"
echo "  2. Enter all 14 days of data from the notes"
echo "  3. Calculate summary statistics below the table:"
echo "     - Average Sleep Quality (all days)"
echo "     - Average Sleep Quality on 'No Afternoon Caffeine' days"
echo "     - Average Sleep Quality on 'Exercise 30+ min' days"
echo "     - Average Sleep Quality on 'Screen Time ≤1hr' days"
echo "     - Overall Average Hours in Bed"
echo ""
echo "  Use formulas for calculations."
echo "  Save as: /home/ga/Documents/Spreadsheets/sleep_analysis.xlsx"
echo ""