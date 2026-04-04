#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Appliance Warranty Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet for the warranty tracker
SHEET_PATH="$WORKSPACE_DIR/appliance_warranty_tracker.xlsx"

cat > /tmp/create_warranty_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Warranties"

# Start with a blank sheet - the agent should create the structure
# Just add a small instruction note that they can delete
ws['A1'] = "Create your appliance warranty tracker here"
ws['A2'] = "(Suggested columns: Appliance Name, Brand/Model, Purchase Date, Warranty Years, Warranty Expires, Status)"

# Make instruction cells italic and gray  
ws['A1'].font = Font(italic=True, color="666666")
ws['A2'].font = Font(italic=True, color="666666", size=9)

wb.save(sys.argv[1])
print(f"Blank warranty tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_warranty_sheet.py
python3 /tmp/create_warranty_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_warranty_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_warranty_task.log || true
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

echo "=== Appliance Warranty Tracker Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Your dishwasher broke at 10 PM and you spent 30 minutes searching for"
echo "warranty info in a shoebox of receipts. Create a tracking system so this"
echo "never happens again!"
echo ""
echo "📝 YOUR TASK:"
echo "1. Create column headers in row 1:"
echo "   A: Appliance Name"
echo "   B: Brand/Model"
echo "   C: Purchase Date"
echo "   D: Warranty (Years)"
echo "   E: Warranty Expires"
echo "   F: Status"
echo ""
echo "2. Enter data for 3-4 home appliances (starting at row 2)"
echo "   Suggested appliances: Refrigerator, Dishwasher, Washing Machine, Microwave"
echo "   Use realistic dates - mix some that are expired, some active, some expiring soon"
echo "   Example data:"
echo "     - Refrigerator | Samsung RF28R7351SG | 2022-03-15 | 2"
echo "     - Dishwasher | Bosch SHPM78Z55N | 2023-06-20 | 1"
echo "     - Washing Machine | LG WM4000HWA | 2021-11-10 | 3"
echo ""
echo "3. In column E (Warranty Expires), create formulas to calculate expiration:"
echo "   Formula: =DATE(YEAR(C2)+D2, MONTH(C2), DAY(C2))"
echo "   Or simpler: =C2 + (D2*365)"
echo "   Copy formula down to all appliance rows"
echo ""
echo "4. In column F (Status), create conditional formulas:"
echo "   =IF(E2 < TODAY(), \"EXPIRED\", IF(E2 < TODAY()+90, \"EXPIRING SOON\", \"ACTIVE\"))"
echo "   Copy formula down to all appliance rows"
echo ""
echo "5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIPS:"
echo "  - To enter dates, type in format: 2024-01-15 or 01/15/2024"
echo "  - Click and drag the small square at bottom-right of a cell to copy formulas"
echo "  - Test your formulas - do the expiration dates look correct?"