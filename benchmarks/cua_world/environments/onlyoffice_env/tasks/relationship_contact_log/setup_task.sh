#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Relationship Contact Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw notes text file
RAW_NOTES_PATH="$WORKSPACE_DIR/martha_notes_raw.txt"

cat > "$RAW_NOTES_PATH" << 'NOTESEOF'
========================================
SCATTERED NOTES - CALLS & TEXTS WITH AUNT MARTHA
========================================

Text screenshot 3/12: "The lady from church didn't show up again. 3rd week."

---

Call notes 3/15: 
Bathroom ceiling has brown stain. Spreading? Worried about cost. 
Can't climb ladder to check attic. 
Asked me to research handyman services in her area.

---

Mental note 3/18: 
Promised to mail her the cookbook she asked about at Christmas. 
Haven't done it yet. NEED TO DO THIS.

---

Text 3/22: "Dr moved my appointment to April 8th. Can you call me that evening?"

---

Call 3/25: 
Sounded tired. Said sleeping poorly for past week or so.
Mentioned knee hurts going up stairs to bedroom. 
Talked about neighbor's cat visiting - she loves this, seems to brighten her mood.
Asked about my kids - remembered their names and what they're doing.

---

Sticky note (date unknown): 
"Martha wants to know about that Medicare Advantage thing - pros/cons?"

---

Call 4/1: 
More worried about ceiling. Stain is definitely bigger. 
Water damage? She's stressed about this.
I said I'd call her landlord directly. HAVEN'T DONE THIS YET.

---

Text 4/3: "I signed up for the senior lunch program! First one is Thursday."

---

Call 4/8 (post-doctor appointment): 
Doctor visit went OK but A1C is up to 6.8 from 6.2 last time.
Doctor wants her to check blood sugar daily now. 
She's overwhelmed by the glucose meter - buttons confusing.
Said I'd find some YouTube video explainers that are senior-friendly.

---

Mental note 4/10: 
She mentioned birthday coming up - April 28th. 
Should send card by 4/20 to arrive in time. Maybe include photos of the kids?

---

Text 4/12: "Church lady called to apologize. She was sick. Feeling better about that."

---

NOTESEOF

chown ga:ga "$RAW_NOTES_PATH"
echo "✅ Raw notes created at: $RAW_NOTES_PATH"

# Create a starter spreadsheet with instructions
SHEET_PATH="$WORKSPACE_DIR/martha_contact_log.xlsx"

cat > /tmp/create_contact_log.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# Remove default sheet
if 'Sheet' in wb.sheetnames:
    del wb['Sheet']

# Create "Instructions" sheet
instructions_sheet = wb.create_sheet("Instructions", 0)
instructions_sheet['A1'] = "RELATIONSHIP CONTACT LOG TASK"
instructions_sheet['A1'].font = Font(size=16, bold=True)

instructions_sheet['A3'] = "Your Goal:"
instructions_sheet['A3'].font = Font(bold=True)
instructions_sheet['A4'] = "Transform the scattered notes in 'martha_notes_raw.txt' into a structured contact log."

instructions_sheet['A6'] = "Required Sheets to Create:"
instructions_sheet['A6'].font = Font(bold=True)
instructions_sheet['A7'] = "1. Contact Log - Track all conversations and communications"
instructions_sheet['A8'] = "   Columns: Date | Type | Summary | Mood/Energy Notes"

instructions_sheet['A10'] = "2. Action Items - Track promises and tasks you committed to"
instructions_sheet['A11'] = "   Columns: Task | Committed Date | Due Date | Status | Priority"

instructions_sheet['A13'] = "3. Follow-Up Concerns - Track ongoing issues to monitor"
instructions_sheet['A14'] = "   Columns: Category | Details | First Mentioned | Status"
instructions_sheet['A15'] = "   Categories: Health, Social, Home, Financial"

instructions_sheet['A17'] = "4. Important Dates - Track upcoming events and reminders"
instructions_sheet['A18'] = "   Columns: Date | Event Type | Details | Reminder Needed"

instructions_sheet['A20'] = "Source file: /home/ga/Documents/Spreadsheets/martha_notes_raw.txt"
instructions_sheet['A20'].font = Font(italic=True)

instructions_sheet['A22'] = "After creating all sheets with appropriate data, save with Ctrl+S"

# Adjust column width
instructions_sheet.column_dimensions['A'].width = 80

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_contact_log.py
python3 /tmp/create_contact_log.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Also create a text editor window showing the raw notes for easy reference
echo "Opening raw notes in a text editor for reference..."
su - ga -c "DISPLAY=:1 gedit '$RAW_NOTES_PATH' > /tmp/gedit_notes.log 2>&1 &" || true
sleep 2

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_contact_log_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_contact_log_task.log || true
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

echo "=== Relationship Contact Log Task Setup Complete ==="
echo ""
echo "📋 Context: You're maintaining long-distance contact with Aunt Martha (78, lives alone)"
echo "📝 Raw notes location: $RAW_NOTES_PATH"
echo "📊 Create structured spreadsheet with 4 sheets:"
echo "   1. Contact Log (conversations with dates, types, summaries, mood observations)"
echo "   2. Action Items (tasks you promised, with status tracking)"
echo "   3. Follow-Up Concerns (health/home/social issues to monitor)"
echo "   4. Important Dates (upcoming appointments, birthday, events)"
echo ""
echo "💡 Tip: The raw notes contain ~10 conversations/texts from 3/12 to 4/12"
echo "🎯 Goal: Extract all relevant information and organize systematically"
echo "💾 Save when complete: Ctrl+S"