#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Water Damage Insurance Claim Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create an initial spreadsheet with instructions
SHEET_PATH="$WORKSPACE_DIR/water_damage_claim.xlsx"

cat > /tmp/create_claim_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Insurance Claim"

# Add instruction text in a separate area (will be deleted by agent ideally)
ws['A1'] = "INSURANCE CLAIM INVENTORY - WATER DAMAGE INCIDENT"
ws['A1'].font = Font(bold=True, size=14)

ws['A3'] = "Instructions: Document all water-damaged items from the burst pipe incident."
ws['A4'] = "Your insurance adjuster needs this within 72 hours."
ws['A5'] = "Required information for each item:"
ws['A6'] = "  - Item Description (what was damaged)"
ws['A7'] = "  - Location/Room (where it was located)"
ws['A8'] = "  - Damage Level (Total Loss, Partial, Water Stained, etc.)"
ws['A9'] = "  - Purchase Date (or 'Unknown' if unsure)"
ws['A10'] = "  - Estimated Value (replacement cost in dollars)"
ws['A12'] = "IMPORTANT: You need to document at least 6 items from at least 3 different rooms."
ws['A13'] = "Add a SUM formula to calculate your total claim amount."
ws['A14'] = "Make sure headers and total are BOLD for professional appearance."

ws['A16'] = "START YOUR CLAIM INVENTORY BELOW (delete these instructions if needed):"
ws['A16'].font = Font(bold=True)

# Set column widths for better readability
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15

wb.save(sys.argv[1])
print(f"Claim spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_claim_sheet.py
python3 /tmp/create_claim_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Claim spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_claim_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_claim_task.log || true
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

echo "=== Water Damage Claim Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You experienced a burst pipe that flooded your basement and"
echo "   damaged the floor above. You need to create an insurance claim inventory."
echo ""
echo "📝 Required Tasks:"
echo "  1. Create column headers (Row 1):"
echo "     - Item Description"
echo "     - Location/Room"
echo "     - Damage Level"
echo "     - Purchase Date"
echo "     - Estimated Value"
echo "  2. Make header row BOLD"
echo "  3. Document at least 6 damaged items (furniture, electronics, etc.)"
echo "  4. Include items from at least 3 different rooms"
echo "  5. Use varied damage levels (Total Loss, Partial, Water Stained, etc.)"
echo "  6. Enter numeric values in Estimated Value column"
echo "  7. Create a SUM formula for total claim amount"
echo "  8. Make the total cell BOLD"
echo "  9. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Example items: furniture, rugs, electronics, flooring, books, clothing"
echo "💡 Example rooms: Basement, Living Room, Den, Bedroom, Office"