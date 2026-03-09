#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Youth Soccer Carpool Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with minimal starting content
SHEET_PATH="$WORKSPACE_DIR/soccer_carpool_april.xlsx"

cat > /tmp/create_carpool_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Carpool Schedule"

# Add a title and scenario description
ws['A1'] = "Lightning Bolts Carpool Coordination - April 2024"
ws['A1'].font = Font(size=14, bold=True)

ws['A3'] = "Create a carpool schedule for the team's April practices and games."
ws['A4'] = "Include: dates, times, event type, driver assignments, passengers, and contact info."
ws['A5'] = "Track driver counts to ensure fair distribution."

# Add some reference information for context
ws['A7'] = "Team Families:"
ws['A8'] = "1. Johnson Family (Emma) - 555-0101"
ws['A9'] = "2. Smith Family (Noah) - 555-0102"
ws['A10'] = "3. Garcia Family (Sofia) - 555-0103"
ws['A11'] = "4. Williams Family (Liam) - 555-0104"
ws['A12'] = "5. Martinez Family (Mia) - 555-0105"

ws['A14'] = "Field Location: Riverside Sports Complex (25 min drive)"

# Leave space for the actual carpool schedule to be created
ws['A16'] = ">>> Create your carpool schedule below <<<"
ws['A16'].font = Font(italic=True, color="808080")

wb.save(sys.argv[1])
print(f"Carpool spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_carpool_sheet.py
python3 /tmp/create_carpool_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_carpool_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_carpool_task.log || true
    # Don't exit - might recover
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - might recover
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Youth Soccer Carpool Task Setup Complete ==="
echo "📝 SCENARIO:"
echo "   You're a parent coordinating carpools for the Lightning Bolts youth soccer team."
echo "   The team has practices and games throughout April at Riverside Sports Complex."
echo "   Five families are participating. You need to create a fair rotation schedule."
echo ""
echo "📋 REQUIREMENTS:"
echo "   1. Create a schedule with at least 8 events (practices/games)"
echo "   2. Include columns for: Date, Time, Event Type, Driver, Passengers, Contact"
echo "   3. Assign a parent driver for each event"
echo "   4. List which kids each driver is picking up"
echo "   5. Include emergency contact numbers"
echo "   6. Add a formula to count how many times each parent drives (for fairness)"
echo "   7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIPS:"
echo "   - Use COUNTIF formula to track driver assignments"
echo "   - April 2024 has ~4 weeks = 8-12 practice/game opportunities"
echo "   - Typical practice: Mon/Wed evenings, Games: Saturday mornings"
echo "   - Family contact info is provided in the template for reference"