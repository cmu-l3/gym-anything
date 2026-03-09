#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Theater Prop Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy props spreadsheet
SHEET_PATH="$WORKSPACE_DIR/props_messy.xlsx"

cat > /tmp/create_messy_props.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Props List"

# Create messy column headers
ws['A1'] = "Item"
ws['B1'] = "Status"
ws['C1'] = "Who?"
ws['D1'] = "Cost"
ws['E1'] = "Note1"
ws['F1'] = "Note2"

# Messy prop data - intentionally disorganized
props_data = [
    ["Whiskey bottle", "got it", "", "0", "period accurate - 1940s", ""],
    ["bourbon bottle", "", "Sarah", "15", "", "needs to look used"],
    ["Playing cards", "done", "Tom", "", "vintage style", ""],
    ["poker chips", "acquired", "", "12.50", "", "red and white"],
    ["Suitcase (large)", "", "", "25", "brown leather preferred", "must open/close smoothly"],
    ["trunk", "have", "Mike", "", "", "large enough for costume"],
    ["Table lamp", "in progress", "Jenny", "$18", "art deco style", "working light"],
    ["Floor lamp", "", "", "35", "", ""],
    ["Telephone", "acquired", "Sarah", "$45.00", "rotary dial - must work", "period accurate - 1940s"],
    ["Radio", "", "Tom", "60", "1940s tabletop style", "doesn't need to work"],
    ["Liquor glasses", "done", "", "8", "set of 4", "sturdy - will be handled"],
    ["Armchair", "", "Mike", "0", "borrowed from Jane's attic", "floral pattern"],
    ["Kitchen chair", "in progress", "", "", "", "wooden - sturdy"],
    ["kitchen chair (wooden)", "", "Props team", "0", "donated by cast member", ""],
    ["Newspaper", "got it", "Props team", "0", "1947 New Orleans", "photocopy OK"],
    ["Paper lantern", "", "Sarah", "12", "Chinese style", "white/colored"],
    ["Mirror", "acquired", "", "$22", "handheld - ornate", ""],
    ["Hairbrush", "", "Actor", "0", "", "actress will provide"],
    ["Cosmetics", "done", "Actor", "0", "period appropriate", "actress will provide"],
    ["Streetcar poster", "", "Tom", "15", "vintage New Orleans", "print from library"],
    ["Cigarettes", "in progress", "Props team", "8", "herbal/prop cigarettes", "no real tobacco"],
    ["Cigarette case", "", "Sarah", "18", "silver or chrome", "working clasp"],
    ["Matches", "acquired", "", "3", "period matchbooks", ""],
    ["Liquor bottle (brandy)", "", "Mike", "12", "empty bottle OK", "label visible"],
    ["brandy bottle", "in progress", "", "$12.00", "", "period style"],
    ["Ice bucket", "in progress", "", "20", "chrome/silver", "art deco style"],
    ["Door bell", "", "Tom", "25", "functional", "mount on door frame"],
    ["Sofa", "", "Jenny", "0", "borrowed", "fits stage - blue/grey"],
    ["Picture frames", "have", "", "8", "set of 3", "wall mounted"],
    ["Ashtrays", "done", "Props team", "$5", "glass - art deco", ""]
]

# Write data starting from row 2
for i, prop in enumerate(props_data, start=2):
    ws[f'A{i}'] = prop[0]
    ws[f'B{i}'] = prop[1]
    ws[f'C{i}'] = prop[2]
    ws[f'D{i}'] = prop[3]
    ws[f'E{i}'] = prop[4]
    ws[f'F{i}'] = prop[5]

# Make headers bold
for col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1']:
    ws[col].font = Font(bold=True)

# Adjust column widths
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 30
ws.column_dimensions['F'].width = 30

wb.save(sys.argv[1])
print(f"Messy props spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_messy_props.py
python3 /tmp/create_messy_props.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Messy props spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_props_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_props_task.log || true
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

echo "=== Theater Prop Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK: Transform messy props spreadsheet into organized tracking system"
echo ""
echo "REQUIREMENTS:"
echo "  1. Standardize columns to:"
echo "     - Prop Name, Category, Status, Method, Responsible Person, Priority, Est. Cost, Notes"
echo ""
echo "  2. Clean the data:"
echo "     - Consolidate duplicates (whiskey/bourbon bottle, kitchen chairs, brandy bottles)"
echo "     - Standardize status: 'got it'/'done'/'have' → 'Acquired'"
echo "     - Combine Note1 and Note2 into single Notes column"
echo "     - Remove $ symbols from costs (numbers only)"
echo "     - Assign Category (Furniture, Hand Prop, Set Dressing, Practical, Costume Accessory)"
echo "     - Assign Priority (Critical, Important, Optional)"
echo "     - Assign Method (Buy, Borrow, Build, Actor Provides)"
echo ""
echo "  3. Add summary section at TOP (rows 1-6):"
echo "     - Row 1: Title (e.g., 'PROP TRACKING - A Streetcar Named Desire')"
echo "     - Row 2: Total Props: [FORMULA]"
echo "     - Row 3: Acquired: [FORMULA]"
echo "     - Row 4: Still Needed: [FORMULA]"
echo "     - Row 5: Total Budget: \$[FORMULA]"
echo "     - Row 6: Spent So Far: \$[FORMULA]"
echo "     - Row 7: (blank)"
echo "     - Row 8: Column headers"
echo ""
echo "  4. Save as: /home/ga/Documents/Spreadsheets/props_organized.xlsx"
echo ""
echo "Current file: $SHEET_PATH"
echo "Target file: /home/ga/Documents/Spreadsheets/props_organized.xlsx"