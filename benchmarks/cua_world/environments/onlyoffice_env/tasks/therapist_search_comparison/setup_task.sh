#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Therapist Search Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with partial therapist data
SHEET_PATH="$WORKSPACE_DIR/therapist_comparison.xlsx"

cat > /tmp/create_therapist_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Therapist Search"

# Add headers with formatting
headers = ["Therapist Name", "Specialty", "In-Network?", "Session Cost", 
           "Availability", "Telehealth?", "Phone Status", "Notes"]

for col, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Add therapist data (partial - costs are blank for user to fill)
therapists = [
    ["Dr. Sarah Mitchell", "Anxiety/Depression", "Yes", None, "2 weeks", "Yes", 
     "Called back", "Warm, professional phone manner"],
    ["James Chen, LMFT", "Trauma/PTSD", "No", None, "Next week", "Yes", 
     "Left voicemail", "Specializes in EMDR"],
    ["Dr. Patricia Gomez", "CBT Specialist", "Yes", None, "4 weeks waitlist", "No", 
     "Spoke with office", "Highly recommended by PCP"],
    ["Rachel Kim, LCSW", "Family Systems", "Yes", None, "1 month", "Yes", 
     "Called back", "Very experienced, calm demeanor"],
    ["Dr. Michael Torres", "EMDR/Trauma", "No", None, "3 days", "Both", 
     "Spoke directly", "Available soon, flexible schedule"]
]

for row_idx, therapist_data in enumerate(therapists, start=2):
    for col_idx, value in enumerate(therapist_data, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

# Add instruction rows below data
ws.cell(row=8, column=1, value="Instructions:")
ws.cell(row=9, column=1, value="1. Fill in Session Cost from reference notes")
ws.cell(row=10, column=1, value="2. Create Monthly Cost column (Session Cost × 4)")
ws.cell(row=11, column=1, value="3. Create Priority Score column")
ws.cell(row=12, column=1, value="4. Add summary statistics below")
ws.cell(row=13, column=1, value="5. Add Status column and sort by priority")

# Adjust column widths
ws.column_dimensions['A'].width = 22
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 13
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 14
ws.column_dimensions['H'].width = 30

wb.save(sys.argv[1])
print(f"Therapist comparison spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_therapist_sheet.py
python3 /tmp/create_therapist_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Create reference notes file with cost information and scoring criteria
NOTES_PATH="$WORKSPACE_DIR/../reference_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
THERAPIST SEARCH - REFERENCE NOTES
====================================

COST INFORMATION FROM YOUR CALLS:
----------------------------------
Your insurance copay for in-network providers: $30 per session

Dr. Sarah Mitchell: In-network (copay applies: $30)
James Chen, LMFT: Out-of-network, charges $180/session
Dr. Patricia Gomez: In-network (copay applies: $30)
Rachel Kim, LCSW: In-network (copay applies: $30)
Dr. Michael Torres: Out-of-network, charges $200/session


PRIORITY SCORING CRITERIA:
--------------------------
Use these criteria to create a Priority Score column:

+3 points: In-network status (much more affordable)
+2 points: Availability within 2 weeks (you need help soon)
+2 points: Specializes in anxiety/trauma (your primary concerns)
+1 point: Good phone impression/communication (spoke directly or warm callback)
+1 point: Telehealth available (convenience factor)

Example:
- Dr. Sarah Mitchell: In-network (+3), 2 weeks (+2), Anxiety specialty (+2), 
  Good phone (+1), Telehealth (+1) = 9 points

Your goal: Calculate scores for each therapist to help make a decision.


YOUR SITUATION:
---------------
- Budget constrained (prefer in-network)
- Need care within next 2-3 weeks if possible
- Struggling with anxiety and some past trauma
- Work from home, so telehealth is very convenient

NOTESEOF

chown ga:ga "$NOTES_PATH"
echo "✅ Reference notes created at: $NOTES_PATH"

# Open the reference notes in a text editor for easy reference
echo "Opening reference notes in text editor..."
su - ga -c "DISPLAY=:1 gedit '$NOTES_PATH' > /tmp/gedit_notes.log 2>&1 &" || true
sleep 2

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_therapist_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_therapist_task.log || true
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

echo "=== Therapist Search Comparison Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You're searching for a therapist and have notes scattered everywhere."
echo "  Time to organize this information so you can make a clear decision!"
echo ""
echo "📝 YOUR TASKS:"
echo "  1. Review the reference_notes.txt file (opened in text editor)"
echo "  2. Fill in the Session Cost column using the cost info from notes"
echo "  3. Create a new column 'Monthly Cost' with formula: =D2*4 (and copy down)"
echo "  4. Create a 'Priority Score' column using the scoring criteria from notes"
echo "  5. Below the data, add summary rows:"
echo "     - Average In-Network Cost"
echo "     - Average Out-of-Network Cost"
echo "  6. Add a 'Status' column with values like: Top Choice, Backup, Waiting, Ruled Out"
echo "  7. Sort the data by Priority Score (highest first)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: The reference notes have all the cost information and scoring criteria!"
echo ""