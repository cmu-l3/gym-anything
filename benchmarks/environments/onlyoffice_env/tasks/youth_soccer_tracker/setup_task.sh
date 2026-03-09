#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Youth Soccer Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the template spreadsheet with partial data
TEMPLATE_PATH="$WORKSPACE_DIR/soccer_progress_template.xlsx"

cat > /tmp/create_soccer_template.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Player Progress"

# Add headers
headers = ["Player Name", "Sessions Attended", "Total Sessions", "Attendance %", 
           "Passing (1-5)", "Shooting (1-5)", "Teamwork (1-5)", "Coach Notes"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Add player names
players = [
    "Emma Rodriguez",
    "Marcus Johnson", 
    "Aisha Patel",
    "Tyler Kim",
    "Sofia Martinez",
    "Jordan Lee",
    "Mia Thompson",
    "Carlos Santos"
]

# Add partial/incorrect attendance data (realistic - coach didn't track perfectly)
# Correct should be: Emma=6, Marcus=8, Aisha=5, Tyler=7, Sofia=7, Jordan=6, Mia=8, Carlos=4
partial_attendance = [7, None, 4, None, 6, 7, None, 3]  # Some wrong, some missing

for i, player in enumerate(players, start=2):
    ws[f'A{i}'] = player
    if partial_attendance[i-2] is not None:
        ws[f'B{i}'] = partial_attendance[i-2]
    ws[f'C{i}'] = 8  # Total sessions

# Column widths for readability
ws.column_dimensions['A'].width = 18
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 15
ws.column_dimensions['G'].width = 15
ws.column_dimensions['H'].width = 30

wb.save(sys.argv[1])
print(f"Soccer progress template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_soccer_template.py
python3 /tmp/create_soccer_template.py "$TEMPLATE_PATH"
chown ga:ga "$TEMPLATE_PATH"

echo "✅ Template spreadsheet created at: $TEMPLATE_PATH"

# Create the coaching notes file on desktop
NOTES_PATH="/home/ga/Desktop/coaching_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
YOUTH SOCCER TEAM - SEASON PROGRESS NOTES
==========================================
Preparing for Parent Conferences - Complete the spreadsheet!

ATTENDANCE NOTES (8 sessions total):
- Emma Rodriguez: missed Sept 15, Sept 22 (so 6 sessions)
- Marcus Johnson: perfect attendance (8 sessions)
- Aisha Patel: missed Sept 8, Sept 29, Oct 6 (so 5 sessions)
- Tyler Kim: missed Oct 13 (so 7 sessions)
- Sofia Martinez: missed Sept 15 (so 7 sessions)
- Jordan Lee: missed Sept 8, Oct 20 (so 6 sessions)
- Mia Thompson: perfect attendance (8 sessions)
- Carlos Santos: missed Sept 22, Sept 29, Oct 6, Oct 13 (so 4 sessions)

SKILL OBSERVATIONS (rate on 1-5 scale):

Emma Rodriguez:
- Passing: 4 (strong, accurate passes)
- Shooting: 2 (needs significant work on power and accuracy)
- Teamwork: 5 (always encouraging teammates, great team player)

Marcus Johnson:
- Passing: 4 (good distribution)
- Shooting: 5 (excellent natural shooter, most goals this season)
- Teamwork: 2 (tends to ball-hog, needs to share more)

Aisha Patel:
- Passing: 3 (developing, improving each week)
- Shooting: 2 (weak, needs confidence)
- Teamwork: 4 (very supportive of others)

Tyler Kim:
- Passing: 4 (solid all-around player)
- Shooting: 3 (consistent, not spectacular)
- Teamwork: 4 (good team communication)

Sofia Martinez:
- Passing: 2 (needs work on technique)
- Shooting: 4 (surprising shooting talent, best attribute)
- Teamwork: 3 (shy, but trying to speak up more)

Jordan Lee:
- Passing: 3 (solid fundamentals)
- Shooting: 3 (inconsistent but improving)
- Teamwork: 4 (good team player, follows instructions)

Mia Thompson:
- Passing: 5 (natural athlete, excellent technique)
- Shooting: 4 (strong shooter, very athletic)
- Teamwork: 5 (leads by example, helps struggling players)

Carlos Santos:
- Passing: 2 (struggles with basics, needs practice)
- Shooting: 2 (weak fundamentals)
- Teamwork: 5 (never gives up, amazing attitude despite challenges)

REMINDER: Calculate attendance % using formula (Sessions Attended / Total Sessions)
Save completed file as: soccer_progress_final.xlsx
NOTESEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Coaching notes created at: $NOTES_PATH"

# Launch ONLYOFFICE with the template spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$TEMPLATE_PATH' > /tmp/onlyoffice_soccer_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_soccer_task.log || true
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

# Also open the notes file in a text editor for easy reference
echo "Opening coaching notes in text editor..."
su - ga -c "DISPLAY=:1 xdg-open '$NOTES_PATH' 2>/dev/null &" || true
sleep 2

echo "=== Youth Soccer Tracker Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  You are a youth soccer coach preparing for parent conferences."
echo "  The template spreadsheet is open with 8 players listed."
echo "  The coaching notes file is also open for reference."
echo ""
echo "📋 Instructions:"
echo "  1. Read the coaching_notes.txt file on your desktop"
echo "  2. Correct/complete the attendance data in column B (Sessions Attended)"
echo "  3. Add formulas in column D to calculate Attendance % (B/C * 100 or B/C)"
echo "  4. Enter skill ratings (1-5) in columns E, F, G for each player"
echo "  5. Add brief coach notes in column H for each player"
echo "  6. Save the file as: /home/ga/Documents/Spreadsheets/soccer_progress_final.xlsx"
echo ""
echo "Expected attendance (from notes):"
echo "  Emma: 6, Marcus: 8, Aisha: 5, Tyler: 7, Sofia: 7, Jordan: 6, Mia: 8, Carlos: 4"