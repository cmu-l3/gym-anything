#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Plant Watering Scheduler Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a blank ODS file with initial structure
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Add empty rows (agent will fill these)
for _ in range(25):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/plant_watering_schedule.ods")
print("✅ Created blank plant_watering_schedule.ods")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/plant_watering_schedule.ods
sudo chmod 666 /home/ga/Documents/plant_watering_schedule.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/plant_watering_schedule.ods > /tmp/calc_plant_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_plant_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Plant Watering Scheduler Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Create a plant watering tracker with the following:"
echo ""
echo "1️⃣  Create column headers (A1-E1):"
echo "   • A1: Plant Name"
echo "   • B1: Watering Frequency (Days)"
echo "   • C1: Last Watered"
echo "   • D1: Next Watering Date"
echo "   • E1: Days Until Next Watering"
echo ""
echo "2️⃣  Enter at least 5 plants (rows 2-7) with:"
echo "   • Plant name, frequency (days), and last watered date"
echo "   • Include some old dates to create overdue plants"
echo ""
echo "3️⃣  Create formulas:"
echo "   • D2: =C2+B2 (Next Watering = Last Watered + Frequency)"
echo "   • E2: =D2-TODAY() (Days Until = Next Watering - Today)"
echo "   • Copy formulas down to all plant rows"
echo ""
echo "4️⃣  Apply conditional formatting:"
echo "   • Select E2:E7 (Days Until column)"
echo "   • Format → Conditional Formatting → Condition"
echo "   • Condition: Cell value < 0"
echo "   • Format: Red background or red text"
echo ""
echo "5️⃣  Sort by priority:"
echo "   • Select A1:E7 (all data including headers)"
echo "   • Data → Sort"
echo "   • Sort by: Days Until Next Watering (column E)"
echo "   • Order: Ascending (most urgent first)"
echo ""
echo "💡 TIP: Overdue plants should appear at top in RED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"