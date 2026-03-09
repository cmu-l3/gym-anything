#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Declutter Inventory Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with headers and example items
SHEET_PATH="$WORKSPACE_DIR/kitchen_declutter.xlsx"

cat > /tmp/create_declutter_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Kitchen Inventory"

# Add headers (not formatted yet - agent will format)
headers = ['Item Name', 'Last Used', 'Condition', 'Category', 'Decision', 'Estimated Sell Value', 'Reason']
for col_num, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_num)
    cell.value = header

# Add 2 example items to show the expected format
example_items = [
    {
        'name': 'Bread Maker',
        'last_used': '2+ years ago',
        'condition': 'Good',
        'category': 'Appliance',
        'decision': 'SELL',
        'sell_value': 25.00,
        'reason': 'Never use it, prefer store-bought bread'
    },
    {
        'name': 'Wooden Spoon Set',
        'last_used': '2024-01',
        'condition': 'Excellent',
        'category': 'Cooking',
        'decision': 'KEEP',
        'sell_value': None,
        'reason': 'Use daily for cooking'
    }
]

for row_num, item in enumerate(example_items, start=2):
    ws.cell(row=row_num, column=1, value=item['name'])
    ws.cell(row=row_num, column=2, value=item['last_used'])
    ws.cell(row=row_num, column=3, value=item['condition'])
    ws.cell(row=row_num, column=4, value=item['category'])
    ws.cell(row=row_num, column=5, value=item['decision'])
    if item['sell_value']:
        ws.cell(row=row_num, column=6, value=item['sell_value'])
    ws.cell(row=row_num, column=7, value=item['reason'])

# Add instruction rows below
ws.cell(row=4, column=1, value="[Add at least 13 more items below - see instructions]")
ws.cell(row=5, column=1, value="")

# Add calculation placeholders at the bottom (rows 20-23)
ws.cell(row=20, column=1, value="Summary Calculations:")
ws.cell(row=21, column=1, value="Total Potential Revenue:")
ws.cell(row=21, column=2, value="[Add SUM formula for all sell values]")
ws.cell(row=22, column=1, value="Items to Remove:")
ws.cell(row=22, column=2, value="[Add COUNTIF formulas for DONATE + SELL]")
ws.cell(row=23, column=1, value="Retention Rate:")
ws.cell(row=23, column=2, value="[Add formula for % of items kept]")

# Set column widths for better visibility
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 35

wb.save(sys.argv[1])
print(f"Declutter inventory spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_declutter_sheet.py
python3 /tmp/create_declutter_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_declutter_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_declutter_task.log || true
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

echo "=== Declutter Inventory Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  Elena is downsizing from a 2-bedroom to 1-bedroom apartment."
echo "  She needs to declutter her kitchen systematically to reduce decision fatigue."
echo "  Help her create an inventory to track what to KEEP, DONATE, or SELL."
echo ""
echo "📝 INSTRUCTIONS:"
echo "  1. Two example items are provided as reference"
echo "  2. Add at least 13 MORE kitchen items (15+ total) with complete data"
echo "  3. Required distributions:"
echo "     - At least 4 items marked KEEP"
echo "     - At least 6 items marked DONATE"
echo "     - At least 3 items marked SELL (with sell values)"
echo "     - At least 2 items from EACH category:"
echo "       * Cooking, Baking, Serving, Storage, Appliance"
echo "  4. Add formulas (around row 21-23):"
echo "     - Total Potential Revenue: =SUM(F2:F20) or similar"
echo "     - Items to Remove: =COUNTIF(E2:E20,\"DONATE\")+COUNTIF(E2:E20,\"SELL\")"
echo "     - Retention Rate: =COUNTIF(E2:E20,\"KEEP\")/COUNTA(E2:E20)"
echo "  5. Format the spreadsheet:"
echo "     - Header row (row 1): BOLD + background color"
echo "     - Decision column (E): Color-code text:"
echo "       * KEEP = Green"
echo "       * DONATE = Blue"
echo "       * SELL = Orange or Red"
echo "     - Sell Value column (F): Currency format (\$0.00)"
echo "     - Retention Rate result: Percentage format (0.0%)"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: Use realistic kitchen items like: blender, spatula, cake pan,"
echo "   serving platter, tupperware set, rice cooker, etc."