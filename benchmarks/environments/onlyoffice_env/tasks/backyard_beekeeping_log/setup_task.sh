#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Backyard Beekeeping Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy input spreadsheet with raw inspection notes
INPUT_PATH="$WORKSPACE_DIR/bee_inspection_notes.xlsx"

cat > /tmp/create_bee_notes.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Raw_Notes"

# Add messy header
ws.append(["Date", "Hive", "Notes", "WeatherTemp"])

# Make header bold
for cell in ws[1]:
    cell.font = Font(bold=True)

# Add messy inspection data from 4 inspection dates, 2 hives each
# Data deliberately has inconsistencies that need to be cleaned
inspection_data = [
    ["April 15", "H1", "queen seen, 3 frames honey, calm bees, good brood pattern", "sunny 72F"],
    ["April 15", "Hive2", "didn't see queen but eggs present, 2 frames honey, some drone cells", "sunny 72F"],
    ["4/22/2025", "1", "queen seen, 5 frames honey, bees defensive when opened, spotty brood, varroa mites?", "cloudy 65"],
    ["4/22/2025", "H2", "queen seen, 4 frames honey, calm, good pattern", "cloudy 65"],
    ["May 3", "Hive1", "no queen seen, eggs present so OK, 6 frames, need to add super soon", "warm"],
    ["May 3", "Hive 2", "queen spotted, 7 frames honey capped, very calm, excellent brood", "78F sunny"],
    ["5/10/2025", "H1", "queen present, 8 frames honey, calm, ready to harvest, added second super", "hot 82"],
    ["5/10/2025", "2", "queen seen, 6 frames honey, low stores in brood chamber, may need feeding if weather bad", "hot 82"]
]

for row_data in inspection_data:
    ws.append(row_data)

# Adjust column widths for readability
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 70
ws.column_dimensions['D'].width = 15

# Add a note at the top
ws.insert_rows(1)
ws['A1'] = "Messy handwritten notes from beehive inspections - Need to clean and organize!"
ws['A1'].font = Font(italic=True, color="FF0000")
ws.merge_cells('A1:D1')

wb.save(sys.argv[1])
print(f"Messy bee inspection notes created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_bee_notes.py
python3 /tmp/create_bee_notes.py "$INPUT_PATH"
chown ga:ga "$INPUT_PATH"

echo "✅ Messy inspection notes created at: $INPUT_PATH"

# Launch ONLYOFFICE with the input spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$INPUT_PATH' > /tmp/onlyoffice_bee_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_bee_task.log || true
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

echo "=== Backyard Beekeeping Log Task Setup Complete ==="
echo "📝 Task Instructions:"
echo ""
echo "You have messy beekeeping inspection notes that need to be cleaned and structured."
echo ""
echo "REQUIRED ACTIONS:"
echo "  1. Create a NEW file: /home/ga/Documents/Spreadsheets/beekeeping_log_2025.xlsx"
echo "  2. Create a worksheet named 'Inspection_Log'"
echo "  3. Add these columns: Date, Hive_ID, Queen_Seen, Frames_Of_Honey, Brood_Pattern, Pest_Alert, Temperament, Action_Needed"
echo "  4. Clean and transfer the 8 inspection records:"
echo "     - Standardize dates (use consistent format)"
echo "     - Standardize Hive_ID (e.g., 'Hive1' or 'Hive2' consistently)"
echo "     - Extract queen status: 'Yes', 'No', or 'Eggs present'"
echo "     - Extract numeric honey frame counts from notes"
echo "     - Categorize brood pattern: 'Good', 'Spotty', 'Excellent', etc."
echo "     - Flag pest alerts: 'Yes' if mites/beetles mentioned, 'No' otherwise"
echo "     - Extract temperament: 'Calm', 'Defensive', 'Aggressive'"
echo "     - Note any actions needed: 'Add super', 'Monitor mites', etc."
echo "  5. Add summary calculations (formulas):"
echo "     - Latest inspection date (use MAX function)"
echo "     - Days since last inspection"
echo "     - Average honey frames for Hive1"
echo "     - Average honey frames for Hive2"
echo "  6. Save the NEW file (Ctrl+S or File > Save As)"
echo ""
echo "EXAMPLE DATA TRANSFORMATION:"
echo "  From: ['April 15', 'H1', 'queen seen, 3 frames honey, calm bees, good brood pattern']"
echo "  To:   ['04/15/2025', 'Hive1', 'Yes', 3, 'Good', 'No', 'Calm', 'None']"
echo ""
echo "TIP: You may want to copy the messy data to a new file first, then clean it column by column."