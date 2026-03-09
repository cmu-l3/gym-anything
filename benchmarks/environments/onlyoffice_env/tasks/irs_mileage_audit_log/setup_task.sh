#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IRS Mileage Audit Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the trip notes file with informal mileage records
NOTES_PATH="$WORKSPACE_DIR/mileage_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
MAYA'S Q1 2024 CLIENT TRIPS - NEED FOR IRS AUDIT

Home office address: 742 Maple St, Portland

Jan 5 - Met with TechStart Inc about website redesign, their office at 1840 Industrial Blvd (14 miles)
Jan 12 - Client presentation at Riverside Coffee (logo concepts for new bakery), 380 River Rd (8 miles)
Jan 19 - Creative Co office, 2200 NW Pettygrove St, discussed branding package (11 miles)
Jan 26 - Powell's Books meeting area, pitched book cover design to author client, 1005 W Burnside (6 miles)

Feb 2 - TechStart Inc follow-up meeting, 1840 Industrial Blvd (14 miles)
Feb 9 - Print consultation at SpeedyPrint, 5505 SE Foster Rd, reviewing brochure proofs (17 miles)
Feb 16 - Lunch meeting with bakery client at Riverside Coffee, 380 River Rd (8 miles)
Feb 23 - Creative Co, 2200 NW Pettygrove St, final branding presentation (11 miles)

Mar 1 - Photography session coordination at client's warehouse, 8800 SE Monterey Ave (19 miles)
Mar 8 - TechStart Inc final website review, 1840 Industrial Blvd (14 miles)
Mar 15 - Contract signing at attorney's office, 1000 SW Broadway Suite 1200 (5 miles)
Mar 22 - Portfolio review meeting at Urban Grind cafe, 555 NE Couch St (7 miles)

Standard mileage rate for 2024: $0.67 per mile
Total miles should be around 134 miles
Expected deduction around $89-90

IRS REQUIREMENTS (Publication 463):
- Date of each trip
- Specific business purpose (not just "meeting")
- Starting location
- Destination address
- Miles driven
NOTESEOF

chown ga:ga "$NOTES_PATH"
echo "✅ Trip notes created at: $NOTES_PATH"

# Create a blank spreadsheet for the mileage log
SHEET_PATH="$WORKSPACE_DIR/mileage_log_2024_q1.xlsx"

cat > /tmp/create_mileage_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Mileage Log"

# Just create a blank spreadsheet - agent needs to add headers and data
# Optional: Add a note in A1 to guide the agent
ws['A1'] = "IRS Mileage Log - Q1 2024"

wb.save(sys.argv[1])
print(f"Blank mileage log spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_mileage_sheet.py
python3 /tmp/create_mileage_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank mileage log created at: $SHEET_PATH"

# Launch ONLYOFFICE with the blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_mileage_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_mileage_task.log || true
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

echo "=== IRS Mileage Audit Log Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Maya is a freelance graphic designer who received an IRS audit notice."
echo "She needs to create an audit-ready mileage log for Q1 2024."
echo ""
echo "📝 INSTRUCTIONS:"
echo "  1. Read trip information from: $NOTES_PATH"
echo "  2. Create column headers for IRS-required fields:"
echo "     - Date"
echo "     - Business Purpose (specific, not vague)"
echo "     - Starting Location"
echo "     - Destination"
echo "     - Miles Driven"
echo "  3. Enter all 12 trips from the notes file"
echo "  4. Calculate total miles (should be 134)"
echo "  5. Calculate tax deduction (total miles × \$0.67)"
echo "  6. Format professionally (bold headers, borders, etc.)"
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "⚠️  IRS COMPLIANCE REQUIREMENTS:"
echo "  - Business purposes must be SPECIFIC (e.g., 'TechStart Inc website redesign consultation')"
echo "  - NOT vague like 'meeting' or 'client visit'"
echo "  - Include complete addresses for destinations"
echo "  - All trips start from home office: 742 Maple St, Portland"
echo ""