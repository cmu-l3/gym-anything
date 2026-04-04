#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Freelance Contract Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Create the contract notes file
NOTES_PATH="$DOCS_DIR/contract_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
FREELANCE CONTRACT OFFERS - Need to decide by Friday!

OFFER 1: TechStart Solutions
- Spoke with Sarah on Monday
- They'll pay $85/hour
- Need me 15 hours per week
- Contract is for 12 weeks (through end of Q2)
- Net-30 payment terms
- Fully remote

OFFER 2: Morrison & Associates  
- Email from Friday
- Rate: $95/hour (highest!)
- But only 10 hrs/week available
- 8 week contract
- Net-60 payment (slower...)
- Hybrid - 2 days/week in office (30 min commute)

OFFER 3: BlueSky Consulting
- Phone call yesterday
- $75/hour (lower rate)
- 20 hours/week (most hours!)
- 16 week contract (longest duration)
- Net-15 payment terms (fastest)
- Fully remote
- Seems like steady work

OFFER 4: LocalTech Startup
- Text message this morning
- $80/hour
- 12 hours/week
- 10 week contract
- Pay on delivery each milestone (weekly)
- Office is downtown (45 min commute)
- Equity option mentioned but unclear

CONSTRAINTS:
- Can't do more than 35 hours/week total
- Offers 1 and 2 have some overlapping meeting times
- Need to respond to everyone by Friday 5 PM
NOTESEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Contract notes created at: $NOTES_PATH"

# Create a blank starter spreadsheet
SHEET_PATH="$WORKSPACE_DIR/contract_comparison.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Contract Comparison"

# Create completely blank spreadsheet - agent will structure it
# Just ensure it's a valid xlsx file

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_contract_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_contract_task.log || true
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

echo "=== Freelance Contract Comparison Task Setup Complete ==="
echo "📋 Scenario:"
echo "  You're a freelance consultant with 4 contract offers!"
echo "  Contract details are in: ~/Documents/contract_notes.txt"
echo ""
echo "📝 Your Task:"
echo "  1. Read the contract notes"
echo "  2. Create a comparison table with columns:"
echo "     - Client Name / Company"
echo "     - Hourly Rate"
echo "     - Hours per Week"
echo "     - Duration (Weeks)"
echo "     - Total Revenue (use formula!)"
echo "     - Additional info column (optional)"
echo "  3. Enter all 4 contract offers"
echo "  4. Use formulas to calculate Total Revenue = Rate × Hours × Weeks"
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Expected Totals:"
echo "  - TechStart: \$15,300"
echo "  - Morrison: \$7,600"
echo "  - BlueSky: \$24,000"
echo "  - LocalTech: \$9,600"