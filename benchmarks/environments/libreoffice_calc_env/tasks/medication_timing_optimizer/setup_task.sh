#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Medication Timing Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the medication schedule spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumText
import sys

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Sheet 1: Med_Rules
rules_table = Table(name="Med_Rules")
doc.spreadsheet.addElement(rules_table)

# Header row for Med_Rules
header_data = ["Medication", "Daily_Doses", "Food_Requirement", "Interacts_With", "Min_Hours_Between"]
header_row = TableRow()
for header_text in header_data:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
rules_table.addElement(header_row)

# Medication data
med_data = [
    ["Med_A", 1, "With food", "", ""],
    ["Med_B", 1, "Empty stomach", "", ""],
    ["Med_C", 2, "No requirement", "Med_D", 6],
    ["Med_D", 1, "With food", "Med_C", ""],
    ["Med_E", 2, "Empty stomach", "", 8],
    ["Med_F", 1, "No requirement", "", ""]
]

for med_row_data in med_data:
    row = TableRow()
    for i, value in enumerate(med_row_data):
        if value == "":
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=""))
        elif isinstance(value, int):
            cell = TableCell(valuetype="float", value=str(value))
            cell.addElement(P(text=str(value)))
        else:
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=str(value)))
        row.addElement(cell)
    rules_table.addElement(row)

# Add empty rows to complete the sheet
for _ in range(20):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    rules_table.addElement(row)

# Sheet 2: Current_Schedule
schedule_table = Table(name="Current_Schedule")
doc.spreadsheet.addElement(schedule_table)

# Header row for Current_Schedule
schedule_headers = ["Time", "Medication", "Meal_Window", "Empty_Stomach", "Food_OK", "Interaction_OK", "Interval_OK"]
header_row = TableRow()
for header_text in schedule_headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
schedule_table.addElement(header_row)

# Schedule data (with 3 planted conflicts)
schedule_data = [
    ["07:00:00", "Med_B"],      # OK - empty stomach medication at breakfast time edge
    ["08:00:00", "Med_E (1)"],  # OK - first dose of Med_E, empty stomach (1hr after breakfast)
    ["10:00:00", "Med_A"],      # CONFLICT 1: With-food requirement but empty stomach time
    ["12:00:00", "Med_C (1)"],  # CONFLICT 2a: First dose of Med_C, interacts with Med_D
    ["12:00:00", "Med_D"],      # CONFLICT 2b: Med_D at same time as Med_C (interaction)
    ["14:00:00", "Med_E (2)"],  # CONFLICT 3: Only 6 hours after first Med_E dose (needs 8)
    ["18:00:00", "Med_F"],      # OK - dinner time, no requirements
    ["21:00:00", "Med_C (2)"]   # OK - second dose of Med_C, 9 hours after first
]

for sched_row_data in schedule_data:
    row = TableRow()
    # Time cell
    time_cell = TableCell(valuetype="time", timevalue=f"PT{sched_row_data[0][:2]}H{sched_row_data[0][3:5]}M00S")
    time_cell.addElement(P(text=sched_row_data[0]))
    row.addElement(time_cell)
    
    # Medication cell
    med_cell = TableCell(valuetype="string")
    med_cell.addElement(P(text=sched_row_data[1]))
    row.addElement(med_cell)
    
    # Empty cells for formulas (5 columns)
    for _ in range(5):
        cell = TableCell()
        row.addElement(cell)
    
    schedule_table.addElement(row)

# Add explanation section
for _ in range(2):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    schedule_table.addElement(row)

# Add meal times reference
meal_info_row = TableRow()
info_cell = TableCell(valuetype="string")
info_cell.addElement(P(text="Meal Times:"))
meal_info_row.addElement(info_cell)
schedule_table.addElement(meal_info_row)

meals = [
    "Breakfast: 7:00 AM",
    "Lunch: 12:00 PM",
    "Dinner: 6:00 PM"
]

for meal_text in meals:
    meal_row = TableRow()
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=meal_text))
    meal_row.addElement(cell)
    schedule_table.addElement(meal_row)

# Add definitions
for _ in range(1):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    schedule_table.addElement(row)

definitions = [
    "Definitions:",
    "With food = within 30 minutes before or after meal",
    "Empty stomach = at least 1 hour before or 2 hours after any meal"
]

for def_text in definitions:
    def_row = TableRow()
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=def_text))
    def_row.addElement(cell)
    schedule_table.addElement(def_row)

# Add empty rows to complete the sheet
for _ in range(20):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    schedule_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/medication_schedule.ods")
print("Created medication schedule spreadsheet successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/medication_schedule.ods
sudo chmod 666 /home/ga/Documents/medication_schedule.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/medication_schedule.ods > /tmp/calc_med_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_med_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
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

# Navigate to Current_Schedule sheet
echo "Navigating to Current_Schedule sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.5

# Position cursor at cell C2 (first formula cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right
sleep 0.3

echo "=== Medication Timing Optimizer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Sheet 1: Med_Rules contains medication requirements"
echo "  Sheet 2: Current_Schedule needs validation formulas"
echo "  Task: Create formulas to detect 3 scheduling conflicts:"
echo "    1. Food requirement violation (Med_A at 10 AM)"
echo "    2. Drug interaction (Med_C + Med_D at 12 PM)"
echo "    3. Insufficient interval (Med_E doses 6 hours apart, needs 8)"
echo ""
echo "💡 Hint: Start with meal window detection in column C"
echo "    Use TIME function and logical comparisons"
echo "    Reference Med_Rules sheet for requirements"