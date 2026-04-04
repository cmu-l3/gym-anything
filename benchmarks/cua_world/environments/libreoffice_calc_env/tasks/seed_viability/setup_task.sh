#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Seed Library Viability Checker Task ==="

# Ensure Python ODF library is available
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy library..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf || pip3 install odfpy
fi

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the seed inventory ODS file with two sheets using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import DateStyle, Number, Day, Month, Year, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Sheet 1: Seed Inventory
inventory_table = Table(name="Seed_Inventory")

# Header row for inventory
header_data = ["Seed_ID", "Variety_Name", "Seed_Type", "Collection_Date", 
               "Quantity_Packets", "Donor_Name", "Age_Years", "Viability_Status"]
header_row = TableRow()
for header in header_data:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
inventory_table.addElement(header_row)

# Seed data - mix of dates from 2018-2024 to create variety
seed_data = [
    ["S001", "Cherokee Purple", "Tomato", "2020-03-15", "12", "Maria Garcia", "", ""],
    ["S002", "Buttercrunch", "Lettuce", "2023-08-20", "8", "John Smith", "", ""],
    ["S003", "Blue Lake Bush", "Bean", "2021-05-10", "15", "Sarah Johnson", "", ""],
    ["S004", "Black Beauty", "Zucchini", "2019-06-22", "10", "Tom Wilson", "", ""],
    ["S005", "Sweet Basil", "Herb", "2024-02-14", "20", "Linda Chen", "", ""],
    ["S006", "Brandywine", "Tomato", "2018-04-05", "6", "Robert Davis", "", ""],
    ["S007", "Red Leaf", "Lettuce", "2024-01-10", "14", "Emma Brown", "", ""],
    ["S008", "Kentucky Wonder", "Bean", "2020-07-18", "18", "Michael Lee", "", ""],
    ["S009", "Butternut", "Squash", "2019-05-30", "8", "Patricia Martinez", "", ""],
    ["S010", "Jalapeño", "Pepper", "2022-03-25", "12", "James Anderson", "", ""],
    ["S011", "Roma", "Tomato", "2021-08-12", "10", "Jennifer Taylor", "", ""],
    ["S012", "Cilantro", "Herb", "2023-11-05", "16", "David Thomas", "", ""],
    ["S013", "California Wonder", "Pepper", "2020-09-14", "9", "Susan Jackson", "", ""],
    ["S014", "Oakleaf", "Lettuce", "2022-06-08", "11", "Richard White", "", ""],
    ["S015", "Provider", "Bean", "2019-10-20", "13", "Lisa Harris", "", ""],
    ["S016", "Early Prolific", "Squash", "2023-04-17", "7", "Charles Martin", "", ""],
    ["S017", "Genovese Basil", "Herb", "2024-03-22", "19", "Nancy Thompson", "", ""],
    ["S018", "Serrano", "Pepper", "2018-12-11", "5", "Paul Garcia", "", ""],
    ["S019", "Yellow Pear", "Tomato", "2022-01-28", "14", "Karen Rodriguez", "", ""],
    ["S020", "Dragon Tongue", "Bean", "2021-11-03", "12", "Mark Wilson", "", ""],
]

for row_data in seed_data:
    data_row = TableRow()
    for i, value in enumerate(row_data):
        if i == 3:  # Collection_Date column
            cell = TableCell(valuetype="date", datevalue=value)
            cell.addElement(P(text=value))
        elif i == 4:  # Quantity (numeric)
            cell = TableCell(valuetype="float", value=value)
            cell.addElement(P(text=value))
        elif i in [6, 7]:  # Empty columns for Age_Years and Viability_Status
            cell = TableCell()
        else:  # String values
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=value))
        data_row.addElement(cell)
    inventory_table.addElement(data_row)

# Add some empty rows
for _ in range(10):
    empty_row = TableRow()
    for _ in range(len(header_data)):
        empty_row.addElement(TableCell())
    inventory_table.addElement(empty_row)

doc.spreadsheet.addElement(inventory_table)

# Sheet 2: Seed Lifespan Reference
reference_table = Table(name="Seed_Lifespan_Reference")

# Header row for reference
ref_header_data = ["Seed_Type", "Min_Viable_Years", "Max_Viable_Years"]
ref_header_row = TableRow()
for header in ref_header_data:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    ref_header_row.addElement(cell)
reference_table.addElement(ref_header_row)

# Reference data
reference_data = [
    ["Tomato", "4", "6"],
    ["Lettuce", "1", "3"],
    ["Bean", "3", "4"],
    ["Squash", "4", "6"],
    ["Pepper", "2", "4"],
    ["Herb", "1", "2"],
]

for row_data in reference_data:
    data_row = TableRow()
    for i, value in enumerate(row_data):
        if i == 0:  # Seed_Type (string)
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=value))
        else:  # Years (numeric)
            cell = TableCell(valuetype="float", value=value)
            cell.addElement(P(text=value))
        data_row.addElement(cell)
    reference_table.addElement(data_row)

# Add empty rows
for _ in range(10):
    empty_row = TableRow()
    for _ in range(len(ref_header_data)):
        empty_row.addElement(TableCell())
    reference_table.addElement(empty_row)

doc.spreadsheet.addElement(reference_table)

# Save the file
doc.save("/home/ga/Documents/seed_inventory.ods")
print("✅ Created seed inventory ODS file with 20 seed entries")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/seed_inventory.ods
sudo chmod 666 /home/ga/Documents/seed_inventory.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/seed_inventory.ods > /tmp/calc_seed_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_seed_task.log || true
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

# Position cursor at Age_Years column (G2)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key ctrl+g  # Go to cell dialog
sleep 0.5
safe_xdotool ga :1 type "G2"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.3

echo "=== Seed Library Viability Checker Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You are helping a community seed library coordinator assess seed viability."
echo ""
echo "SHEETS:"
echo "  • Seed_Inventory: Contains 20 donated seeds with empty Age_Years and Viability_Status columns"
echo "  • Seed_Lifespan_Reference: Contains expected lifespan data for each seed type"
echo ""
echo "YOUR TASKS:"
echo "  1. Calculate Age_Years (column G):"
echo "     • Use date formula: =DATEDIF(D2,TODAY(),\"Y\") or equivalent"
echo "     • Copy formula down to all seed rows (G2:G21)"
echo ""
echo "  2. Determine Viability_Status (column H):"
echo "     • Use VLOOKUP to get Min and Max viable years from reference sheet"
echo "     • Use nested IF: =IF(age<min,\"Good\",IF(age<max,\"Test\",\"Discard\"))"
echo "     • Copy formula down to all seed rows (H2:H21)"
echo ""
echo "  3. Apply Conditional Formatting to column H:"
echo "     • Select H2:H21"
echo "     • Format → Conditional Formatting → Condition"
echo "     • \"Good\" = Green background"
echo "     • \"Test\" = Yellow background"
echo "     • \"Discard\" = Red background"
echo ""
echo "REFERENCE DATA (Sheet 2):"
echo "  Tomato:  4-6 years  |  Lettuce: 1-3 years  |  Bean: 3-4 years"
echo "  Squash:  4-6 years  |  Pepper:  2-4 years  |  Herb: 1-2 years"
echo ""
echo "💡 HINTS:"
echo "  • TODAY() returns current date"
echo "  • DATEDIF(start_date, end_date, \"Y\") calculates years"
echo "  • VLOOKUP syntax: =VLOOKUP(C2,Seed_Lifespan_Reference.$A$2:$C$7,2,FALSE)"
echo "  • Use absolute references ($) for lookup ranges"
echo ""
echo "Cursor positioned at G2 (Age_Years column). Good luck! 🌱"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"