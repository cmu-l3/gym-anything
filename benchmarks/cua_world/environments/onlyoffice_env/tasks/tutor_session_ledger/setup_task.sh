#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tutoring Session Ledger Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the rough notes file with messy tutor data
NOTES_PATH="$WORKSPACE_DIR/tutor_rough_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
TUTORING SESSIONS - FALL SEMESTER
Need to organize this for taxes!!

ALEX M:
- Sept 10, 15, 22, 29 (all 1.5 hrs @ $60/hr)
- Oct 6, 13 (1.5 hrs each)
- Oct 20 (2 hrs - ran long, only charged for 1.5)
- Parent paid $540 via check (covers through Oct 13)
- Still owes for Oct 20

JAMIE R:
- Started Aug 28
- Every Tuesday 2-3:30pm through Oct 31 (that's 10 sessions)
- Rate: $65/hr
- Mom Venmo'd $975 on Oct 1 "for everything"

TAYLOR S:
- Sept 5, 12, 19 (2 hrs each @ $60/hr)
- Sept 26, Oct 3, 10, 17 (2 hrs each)
- OOPS - been charging $55/hr by mistake since Sept 26!!
- They've paid through Oct 10 correctly (even though at wrong rate)
- Owe for Oct 17

MORGAN P:
- Weekend only: Sept 9, 16, 23, 30, Oct 7, 14, 21
- 1 hour sessions @ $70/hr (weekend premium)
- Paid in full through Oct 14
- Oct 21 session not paid yet

CASEY L:
- Intensive: Sept 1, 3, 8, 10, 15, 17, 22, 24, 29
- 1.5 hrs each @ $60/hr
- Paid $405 so far (only covers 4.5 sessions!)
- Multiple payments: $180, $135, $90

RILEY K:
- Oct 4, 11, 18, 25 (just started)
- 2 hrs @ $60/hr
- Parent asked about package pricing?
- Paid for first two sessions ($240), others pending

MY RATES:
Standard: $60/hr
High demand students: $65/hr
Weekend premium: $70/hr

TODO:
- Fix the Taylor undercharging issue
- Collect from Alex and Taylor for most recent sessions
- Figure out how much Casey still owes!
- Follow up with Riley about package discount
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Rough notes created at: $NOTES_PATH"

# Create blank starter spreadsheet
SHEET_PATH="$WORKSPACE_DIR/session_ledger.xlsx"

cat > /tmp/create_ledger.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = 'Session Ledger'

# Add a title and basic instructions
ws['A1'] = 'Tutoring Session Ledger - Fall Semester'
ws['A1'].font = Font(size=14, bold=True)

ws['A3'] = 'Reference: See tutor_rough_notes.txt for session data'
ws['A4'] = 'Create a comprehensive ledger with:'
ws['A5'] = '  - Session details (student, date, hours, rate, billed, paid, balance)'
ws['A6'] = '  - Student summary section (totals per student)'
ws['A7'] = '  - Business totals (total hours, revenue, outstanding)'
ws['A8'] = '  - Note billing issues (undercharging, unpaid sessions)'

# Leave rest blank for agent to fill
wb.save(sys.argv[1])
print(f"Blank ledger created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_ledger.py
python3 /tmp/create_ledger.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank ledger created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_tutor_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_tutor_task.log || true
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

echo "=== Tutoring Session Ledger Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read the rough notes at: $NOTES_PATH"
echo "  2. Create a professional session ledger in: $SHEET_PATH"
echo "  3. Include:"
echo "     - Session log (student, date, hours, rate, amount billed, paid, balance)"
echo "     - Student summaries (total hours, total billed, total paid, outstanding)"
echo "     - Business totals (all students combined)"
echo "     - Identify/note billing issues (Taylor undercharged, Casey underpaid, etc.)"
echo "  4. Use formulas for all calculations"
echo "  5. Save the file (Ctrl+S)"
echo ""
echo "Key data to extract from notes:"
echo "  - 6 students: Alex M, Jamie R, Taylor S, Morgan P, Casey L, Riley K"
echo "  - ~40 total sessions across all students"
echo "  - Various rates: \$60/hr (standard), \$65/hr (high demand), \$70/hr (weekend)"
echo "  - Multiple billing issues to identify and track"