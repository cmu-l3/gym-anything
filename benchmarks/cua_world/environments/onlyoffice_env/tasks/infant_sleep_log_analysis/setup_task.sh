#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Infant Sleep Log Analysis Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create the messy sleep notes file on Desktop
NOTES_PATH="$DESKTOP_DIR/sleep_notes_raw.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
BABY SLEEP TRAINING NOTES - Please help me make sense of this!!
================================================================

*** FERBER METHOD (Started Sept 15) ***

Sept 15 - Ferber method night 1 - woke up 7 times!! cried 45 min total. so hard. pediatrician said to stick with it
9/16 Ferber - 6 wakeups, maybe 30 minutes? Lost track honestly
Sept 17 - only 4 times! 20 min. improvement?? or just luck?
Sept 18 - back to 6 wakings, 38 minutes - ugh regression
9-19 - 5 wakes / 33 min - slightly better

Sept 20 - GAVE UP ON FERBER. Too much crying. Trying chair method instead per mom's advice


*** CHAIR METHOD (Started Sept 20) ***

9-21 chair method night 1 - 8 wakeups (WORSE!!) 50 minutes crying. maybe I'm doing it wrong?
Sept 22 - 7 times, 42 min
9/23 - 8 wakings again, 48 minutes. exhausted.
Sept 24 - 7 wakes, 45 min
[Sept 25 - too tired to write anything down, just survived]
9-26 - think it was 6 times? maybe 40 min?
Sept 27 - 7 wakings, 44 minutes
9/28 - 8 times, 52 min - WORST NIGHT YET
Sept 29 - 6 wakes, 38 minutes
9-30 - 7 wakings, 43 min

Oct 1 - Chair method not working. Read about "pick up put down" - will try that


*** PICK UP PUT DOWN METHOD (Started Oct 1) ***

Oct 1 - started PUPD - 5 wakes, 35 min. Already better??
10/2 - 4 wakings! 28 minutes. is this real life?
Oct 3 - 5 times, 30 min
10-4 - only 3 wakings!! 22 minutes!! best night in MONTHS
Oct 5 - 4 wakes, 25 min
10/6 - 5 wakings, 32 min
Oct 7 - 4 times, 27 minutes
10-8 - 3 wakings, 20 min - another great night
Oct 9 - 5 wakes, 31 min
10/10 - 4 wakings, 26 minutes
Oct 11 - 4 times, 28 min
10-12 - 5 wakes, 30 min - this method seems to be working!

PEDIATRICIAN APPT TOMORROW (Oct 13) - need to show her this data in organized form!!
NOTESEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Sleep notes created at: $NOTES_PATH"

# Launch text editor with the notes file so it's visible for reference
echo "Opening sleep notes in text editor..."
su - ga -c "DISPLAY=:1 gedit '$NOTES_PATH' > /tmp/gedit_notes.log 2>&1 &"
sleep 2

# Launch ONLYOFFICE Spreadsheet with a blank file
SHEET_PATH="$WORKSPACE_DIR/sleep_training_analysis.xlsx"

# Create a blank spreadsheet as starting point
cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sleep Analysis"

# Add helpful hint in first cell
ws['A1'] = "Organize sleep training data here (see sleep_notes_raw.txt on Desktop)"

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_sleep_task.log 2>&1 &"

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

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

# Arrange windows side-by-side for easier reference
echo "Arranging windows for easier workflow..."
# Move gedit to left half
su - ga -c "DISPLAY=:1 wmctrl -r gedit -e 0,0,0,960,1080" 2>/dev/null || true
# Move ONLYOFFICE to right half
su - ga -c "DISPLAY=:1 wmctrl -r ONLYOFFICE -e 0,960,0,960,1080" 2>/dev/null || true
sleep 1

# Ensure ONLYOFFICE has focus
focus_onlyoffice_window

echo "=== Infant Sleep Log Analysis Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "You're a sleep-deprived parent who has been trying different sleep training"
echo "methods for your 7-month-old. Tomorrow is your pediatrician appointment and"
echo "you need to consolidate your messy notes into a clear analysis."
echo ""
echo "📋 INSTRUCTIONS:"
echo "1. Read the sleep notes from: sleep_notes_raw.txt (visible in text editor)"
echo "2. Create a structured spreadsheet with columns:"
echo "   - Date"
echo "   - Method (Ferber, Chair, or Pick-Up-Put-Down)"
echo "   - Night Wakings (number)"
echo "   - Wake Duration (minutes)"
echo "   - Notes (optional)"
echo "3. Enter data from all available days (handle missing days appropriately)"
echo "4. Create a SUMMARY section comparing the three methods:"
echo "   - Calculate AVERAGE night wakings for each method (use AVERAGE formula)"
echo "   - Calculate AVERAGE wake duration for each method (use AVERAGE formula)"
echo "5. Add a recommendation based on the data"
echo "6. Save as: sleep_training_analysis.xlsx"
echo ""
echo "⏰ You have limited time - the appointment is tomorrow!"