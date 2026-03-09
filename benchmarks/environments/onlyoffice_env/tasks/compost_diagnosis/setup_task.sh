#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compost Diagnosis Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with rough notes
SHEET_PATH="$WORKSPACE_DIR/compost_notes.xlsx"

cat > /tmp/create_compost_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Compost Notes"

# Add title
ws['A1'] = "ROUGH COMPOSTING NOTES - NEEDS ORGANIZATION"
ws['A1'].font = Font(bold=True, size=14)
ws['A1'].alignment = Alignment(wrap_text=True)

# Add messy, unstructured notes simulating handwritten records
rough_notes = [
    "",
    "Started composting early June - excited to reduce waste!",
    "",
    "Week 1 (June 1-7):",
    "June 1: Added kitchen scraps from dinner prep (about 3 cups), coffee grounds (1 cup)",
    "June 3: More veggie peels and fruit scraps (2 cups)",
    "June 5: Grass clippings from mowing - big bag, maybe 4-5 gallons",
    "June 7: Coffee grounds again (1 cup), banana peels",
    "",
    "Week 2 (June 8-14):",
    "June 9: Kitchen waste - lots of salad scraps (3 cups)",
    "June 10: Pulled weeds from garden, threw in compost (2 bags full)",
    "June 12: More grass clippings (another 3 gallons or so)",
    "June 13: Apple cores, orange peels, cucumber ends (2 cups)",
    "June 14: Coffee grounds (2 cups) + tea bags",
    "",
    "Week 3 (June 15-21):",
    "June 15: Started noticing AMMONIA SMELL - not good!",
    "June 16: Added kitchen scraps anyway (2 cups veggie waste)",
    "June 17: More fruit scraps (2 cups)",
    "June 18: Tried adding some cardboard - ripped up 2 small boxes",
    "June 20: Smell is WORSE, also seeing fruit flies :( Material looks soggy",
    "June 22: Added more grass clippings + pulled weeds (thought it would help??)",
    "",
    "Week 4 (June 22-30):",
    "June 24: Found some dry leaves in garage - added about 1 bag",
    "June 25: Shredded newspaper - added maybe 2 cups worth",
    "June 27: Kitchen scraps (1 cup)",
    "June 29: More coffee grounds (1 cup)",
    "",
    "July - tried to fix it:",
    "July 2: Added more cardboard (3 boxes torn up)",
    "July 5: Dry leaves (2 bags)",
    "July 8: Shredded paper from office (1 bag)",
    "July 10: Still smelly but SLIGHTLY better",
    "",
    "PROBLEM: What went wrong? Need to figure out the ratio...",
    "I think I added too many grass clippings and kitchen waste early on?",
    "Read that green vs brown ratio matters - need to track this properly!",
]

for idx, note in enumerate(rough_notes, start=2):
    ws[f'A{idx}'] = note
    ws[f'A{idx}'].alignment = Alignment(wrap_text=True)

# Set column width
ws.column_dimensions['A'].width = 80

# Add instruction at the bottom
instruction_row = len(rough_notes) + 4
ws[f'A{instruction_row}'] = "TASK: Organize the above notes into a proper tracking spreadsheet"
ws[f'A{instruction_row}'].font = Font(bold=True, color="FF0000")
ws[f'A{instruction_row}'].alignment = Alignment(wrap_text=True)

ws[f'A{instruction_row + 1}'] = "Create columns: Date | Material | Category (Green/Brown) | Volume | Notes"
ws[f'A{instruction_row + 1}'].alignment = Alignment(wrap_text=True)

ws[f'A{instruction_row + 2}'] = "GREEN = nitrogen-rich (kitchen scraps, coffee, grass, weeds, fruit)"
ws[f'A{instruction_row + 2}'].alignment = Alignment(wrap_text=True)

ws[f'A{instruction_row + 3}'] = "BROWN = carbon-rich (dry leaves, paper, cardboard, wood chips)"
ws[f'A{instruction_row + 3}'].alignment = Alignment(wrap_text=True)

wb.save(sys.argv[1])
print(f"Compost notes spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_compost_sheet.py
python3 /tmp/create_compost_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Compost notes spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_compost_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_compost_task.log || true
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

echo "=== Compost Diagnosis Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the rough notes in column A"
echo "  2. Create a structured table with columns: Date, Material, Category, Volume, Notes"
echo "  3. Extract and organize data from the rough notes"
echo "  4. Categorize each material as GREEN (nitrogen) or BROWN (carbon)"
echo "  5. Create a formula to calculate green-to-brown ratio"
echo "  6. Identify the problem: too many greens added early, causing smell issues"
echo "  7. Save the spreadsheet (Ctrl+S)"