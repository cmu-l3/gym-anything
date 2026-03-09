#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Garden Planting Schedule Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
SPREADSHEET_DIR="/home/ga/Documents/Spreadsheets"
GARDEN_DIR="/home/ga/Documents/Garden"
sudo -u ga mkdir -p "$SPREADSHEET_DIR"
sudo -u ga mkdir -p "$GARDEN_DIR"

# Create the unstructured source data file (planting notes)
NOTES_PATH="$GARDEN_DIR/planting_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
SPRING PLANTING NOTES - 2024
=============================

Last Frost Date for my area: April 15

VEGETABLE PLANTING INFORMATION:

TOMATOES - plant 2 weeks after last frost, needs 24-36 inch spacing
Good companions: basil, carrots, avoid: potatoes

LETTUCE - can plant 4 weeks before last frost, needs 6-8 inch spacing
Companions: carrots, radishes

BASIL - plant 1 week after last frost, needs 10-12 inch spacing
Companions: tomatoes, peppers  

CARROTS - plant 3 weeks before last frost, needs 3-4 inch spacing
Companions: lettuce, tomatoes

PEPPERS - plant 2-3 weeks after last frost, needs 18-24 inch spacing
Companions: basil, onions

RADISHES - plant 4 weeks before last frost, needs 2-3 inch spacing
Fast growing! Companions: lettuce, carrots

ZUCCHINI - plant 1 week after last frost, needs 36-48 inch spacing
Companions: beans, corn

BEANS - plant on last frost date (same day), needs 4-6 inch spacing
Companions: corn, zucchini

IMPORTANT NOTES:
- Tomatoes and peppers are nightshades - give them space from each other
- Start tomatoes indoors 6-8 weeks before transplant date
- Succession plant lettuce and radishes every 2 weeks for continuous harvest
- Check soil temperature before planting: tomatoes need 60°F+, peppers 65°F+
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Planting notes created at: $NOTES_PATH"

# Create the initial spreadsheet with frost date reference
SHEET_PATH="$SPREADSHEET_DIR/planting_schedule.xlsx"

cat > /tmp/create_garden_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys
from datetime import datetime

wb = Workbook()
ws = wb.active
ws.title = "Spring Planting"

# Add frost date reference at top
ws['A1'] = "Reference Information"
ws['A1'].font = Font(bold=True, size=12)

ws['B1'] = "Last Frost Date:"
ws['B1'].font = Font(bold=True)
ws['C1'] = datetime(2024, 4, 15)
ws['C1'].number_format = 'M/D/YYYY'

# Add instructions
ws['A2'] = "Instructions: Organize your planting notes below. Use formulas in column C to calculate dates from the frost date above."
ws['A2'].font = Font(italic=True, size=9)

# The user needs to create headers in row 3 and fill in data
# We leave it mostly blank for them to organize

wb.save(sys.argv[1])
print(f"Spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_garden_sheet.py
python3 /tmp/create_garden_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_garden_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_garden_task.log || true
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

echo "=== Garden Planting Schedule Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open and read the planting notes: ~/Documents/Garden/planting_notes.txt"
echo "  2. Create column headers in row 3:"
echo "     A: Crop"
echo "     B: Days from Frost (negative for before, positive for after)"
echo "     C: Planting Date (formula referencing C1)"
echo "     D: Spacing (inches)"
echo "     E: Companions"
echo "  3. Fill in data for at least 6 vegetables from your notes"
echo "  4. Use formulas like =C1+B4 to calculate planting dates"
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Example conversions:"
echo "  '4 weeks before' = -28 days"
echo "  '2 weeks after' = +14 days"
echo "  'same day' = 0 days"