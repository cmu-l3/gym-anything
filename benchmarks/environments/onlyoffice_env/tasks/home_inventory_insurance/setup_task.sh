#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Inventory Insurance Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with headers
SHEET_PATH="$WORKSPACE_DIR/Home_Inventory.xlsx"

cat > /tmp/create_inventory_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font
import sys

wb = Workbook()
ws = wb.active
ws.title = "Home Inventory"

# Add column headers in row 1
headers = [
    "Room/Category",
    "Item Description", 
    "Purchase Date",
    "Original Cost",
    "Current Value",
    "Serial Number",
    "Has Receipt/Photo",
    "Notes"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)

# Set column widths for better readability
ws.column_dimensions['A'].width = 18
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 13
ws.column_dimensions['E'].width = 13
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 25

wb.save(sys.argv[1])
print(f"Home inventory spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_inventory_sheet.py
python3 /tmp/create_inventory_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_inventory_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_inventory_task.log || true
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

echo "=== Home Inventory Insurance Task Setup Complete ==="
echo "📝 Instructions:"
echo ""
echo "PART 1: Enter 7 items (rows 2-8) with the following details:"
echo "  Row 2: Living Room | 65\" Samsung TV | 03/2020 | \$1,800 | \$900 | SN: SAM789XYZ | Yes | Mounted on wall"
echo "  Row 3: Living Room | Bose Sound System | 11/2019 | \$1,200 | \$600 | SN: BOSE456 | Yes | 5.1 surround"
echo "  Row 4: Master Bedroom | Diamond Engagement Ring | 06/2015 | \$4,500 | \$5,200 | N/A | Yes | Appraised 2023"
echo "  Row 5: Home Office | MacBook Pro 16\" | 09/2022 | \$2,800 | \$2,100 | SN: MBP2022X | Yes | AppleCare until 2025"
echo "  Row 6: Garage | Mountain Bike (Trek) | 04/2021 | \$1,600 | \$1,000 | SN: TRK2021M | No | Need to photograph"
echo "  Row 7: Basement | Gibson Guitar | Unknown | Unknown | \$2,500 | SN: GIBS1987 | No | Vintage, est. value only"
echo "  Row 8: Kitchen | KitchenAid Mixer | 12/2018 | \$450 | \$350 | N/A | Yes | Wedding gift"
echo ""
echo "PART 2: Add totals row (row 9):"
echo "  A9: TOTAL COVERAGE NEEDED"
echo "  D9: =SUM(D2:D8)  [sum of Original Cost]"
echo "  E9: =SUM(E2:E8)  [sum of Current Value]"
echo ""
echo "PART 3: Create HIGH-VALUE ITEMS section (starting row 11):"
echo "  A11: HIGH-VALUE ITEMS (>$2,000 current value)"
echo "  A12: Item | B12: Current Value | C12: Needs Appraisal?"
echo "  Row 13: Diamond Engagement Ring | \$5,200 | No - recent appraisal"
echo "  Row 14: MacBook Pro 16\" | \$2,100 | No"
echo "  Row 15: Gibson Guitar | \$2,500 | Yes - vintage item"
echo ""
echo "PART 4: Create DOCUMENTATION PRIORITY section (starting row 17):"
echo "  A17: ITEMS NEEDING PHOTOS/RECEIPTS"
echo "  A18: Mountain Bike (Trek)"
echo "  A19: Gibson Guitar"
echo ""
echo "PART 5: Apply formatting:"
echo "  - Make row 1 (headers) bold"
echo "  - Make row 9 (totals) bold"
echo "  - Make cells A11, A17 bold (section headers)"
echo ""
echo "PART 6: Save the file (Ctrl+S)"