#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Canning Inventory Freshness Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
DOCS_DIR="/home/ga/Documents"
SHEETS_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$DOCS_DIR"
sudo -u ga mkdir -p "$SHEETS_DIR"

# Create the canning notes text file (messy data source)
NOTES_PATH="$DOCS_DIR/canning_notes.txt"

cat > "$NOTES_PATH" << 'TXTEOF'
CANNING NOTES - 2024 SEASON

Tomato Sauce - Aug 15 - 6 quarts - basement shelf
Dill Pickles batch 1 - Aug 22 - 8 pints - pantry
Strawberry Jam - June 10 - 4 half-pints - pantry (gave away 2)
Bread & Butter Pickles - Sep 3 - 6 pints - basement
Pickled Jalapeños - Sep 10 - 3 half-pints - pantry
Peach Jam - July 28 - 5 half-pints - pantry (gave 1 to mom)
Tomato Salsa - Aug 20 - 4 pints - basement shelf
Green Beans - Aug 8 - 7 quarts - root cellar
Apple Butter - Oct 5 - 4 pints - pantry
Pickled Beets - Sep 15 - 5 pints - basement
Grape Jelly - Sep 25 - 6 half-pints - pantry
Pumpkin Butter - Oct 20 - 3 pints - pantry (gave 1 already)
Corn Relish - Aug 30 - 4 pints - basement
Cherry Preserves - July 15 - 4 half-pints - root cellar
Marinara Sauce - Aug 25 - 5 quarts - basement shelf
Zucchini Relish - Sep 8 - 4 pints - pantry
Hot Pepper Jelly - Oct 1 - 5 half-pints - pantry
Applesauce - Oct 12 - 6 quarts - root cellar

Notes: Today is Dec 8, 2024. Need to use anything over 10 months old soon!
Most canned goods best within 12 months.
TXTEOF

chown ga:ga "$NOTES_PATH"
chmod 644 "$NOTES_PATH"

echo "✅ Canning notes created at: $NOTES_PATH"

# Create the initial spreadsheet template with column headers
SHEET_PATH="$SHEETS_DIR/canning_inventory.xlsx"

cat > /tmp/create_canning_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Canning Inventory"

# Add column headers with formatting
headers = [
    "Item Name",
    "Date Processed",
    "Quantity Remaining",
    "Size",
    "Location",
    "Use By Date",
    "Days Until Expiry",
    "Priority"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center', vertical='center')

# Set column widths for readability
ws.column_dimensions['A'].width = 22  # Item Name
ws.column_dimensions['B'].width = 15  # Date Processed
ws.column_dimensions['C'].width = 18  # Quantity Remaining
ws.column_dimensions['D'].width = 12  # Size
ws.column_dimensions['E'].width = 15  # Location
ws.column_dimensions['F'].width = 15  # Use By Date
ws.column_dimensions['G'].width = 18  # Days Until Expiry
ws.column_dimensions['H'].width = 12  # Priority

# Add a helpful note in row 2
ws['A2'] = "Read data from /home/ga/Documents/canning_notes.txt"
ws['A2'].font = Font(italic=True, color="666666")

wb.save(sys.argv[1])
print(f"Spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_canning_sheet.py
python3 /tmp/create_canning_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_canning_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_canning_task.log || true
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

echo "=== Canning Inventory Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Open the canning notes at /home/ga/Documents/canning_notes.txt"
echo "  2. Create inventory from the notes in canning_inventory.xlsx"
echo "  3. Columns needed: Item Name, Date Processed, Quantity Remaining, Size, Location"
echo "  4. Add formula columns:"
echo "     - Use By Date: Date Processed + 12 months"
echo "     - Days Until Expiry: Use By Date - TODAY() (Dec 8, 2024)"
echo "     - Priority: IF(Days Until Expiry < 60, \"URGENT\", \"OK\")"
echo "  5. Account for items given away (noted in parentheses)"
echo "  6. Apply conditional formatting: highlight URGENT rows"
echo "  7. Sort by Days Until Expiry (ascending - oldest first)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - All 18 items entered"
echo "  - Strawberry Jam: 2 (gave away 2)"
echo "  - Peach Jam: 4 (gave 1 away)"
echo "  - Pumpkin Butter: 2 (gave 1 away)"
echo "  - June/July items should be flagged URGENT"