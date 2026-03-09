#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Soccer Carpool Coordinator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (for ODS file creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing python3-odf..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create the carpool spreadsheet with Martinez entries using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TableCellProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol
from datetime import datetime, timedelta

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Helper function to create a cell with text
def text_cell(value):
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(value)))
    return cell

# Helper function to create a cell with number
def number_cell(value):
    cell = TableCell(valuetype="float", value=str(value))
    cell.addElement(P(text=str(value)))
    return cell

# Helper function to create empty cell
def empty_cell():
    return TableCell()

# Create header row
header_row = TableRow()
headers = ["Practice Date", "Driver Family", "Vehicle Type", "Capacity", "Kids Assigned", "Miles (RT)"]
for h in headers:
    header_row.addElement(text_cell(h))
# Add empty cell
header_row.addElement(empty_cell())
# Family info table headers
header_row.addElement(text_cell("Family Name"))
header_row.addElement(text_cell("Vehicle Type"))
header_row.addElement(text_cell("Kids"))
header_row.addElement(text_cell("Miles to Field"))
table.addElement(header_row)

# Generate 12 practice dates (Tuesdays and Thursdays)
base_date = datetime(2025, 4, 1)  # April 1, 2025 (Tuesday)
practice_dates = []
date_obj = base_date
count = 0
while count < 12:
    weekday = date_obj.weekday()
    if weekday == 1 or weekday == 3:  # Tuesday or Thursday
        practice_dates.append(date_obj.strftime("%m/%d/%Y (%a)"))
        count += 1
    date_obj += timedelta(days=1)

# Family data
families = [
    {"name": "Johnson", "vehicle": "SUV", "capacity": 6, "kids": 2, "miles": 16},
    {"name": "Thompson", "vehicle": "Sedan", "capacity": 4, "kids": 1, "miles": 12},
    {"name": "Chen", "vehicle": "Minivan", "capacity": 7, "kids": 2, "miles": 20},
    {"name": "Patel", "vehicle": "Sedan", "capacity": 4, "kids": 1, "miles": 10},
    {"name": "Williams", "vehicle": "SUV", "capacity": 6, "kids": 2, "miles": 18},
    {"name": "Davis", "vehicle": "Minivan", "capacity": 7, "kids": 1, "miles": 14},
    {"name": "Rodriguez", "vehicle": "SUV", "capacity": 6, "kids": 1, "miles": 22},
    {"name": "Kim", "vehicle": "Sedan", "capacity": 4, "kids": 2, "miles": 16}
]

# Pre-assigned schedule (6 Martinez, 6 others) with passenger counts
# Passenger count includes all kids riding (including driver's kids)
assignments = [
    {"driver": "Martinez", "passengers": 5},  # Tue - needs replacement
    {"driver": "Johnson", "passengers": 6},    # Thu
    {"driver": "Martinez", "passengers": 4},  # Tue - needs replacement
    {"driver": "Williams", "passengers": 5},  # Thu
    {"driver": "Martinez", "passengers": 6},  # Tue - needs replacement
    {"driver": "Chen", "passengers": 7},      # Thu
    {"driver": "Martinez", "passengers": 4},  # Tue - needs replacement
    {"driver": "Rodriguez", "passengers": 4}, # Thu
    {"driver": "Martinez", "passengers": 5},  # Tue - needs replacement
    {"driver": "Davis", "passengers": 6},     # Thu
    {"driver": "Martinez", "passengers": 4},  # Tue - needs replacement
    {"driver": "Kim", "passengers": 4}        # Thu
]

# Create data rows for schedule
for i, (date, assignment) in enumerate(zip(practice_dates, assignments)):
    row = TableRow()
    
    # Date
    row.addElement(text_cell(date))
    
    # Driver
    row.addElement(text_cell(assignment["driver"]))
    
    # Vehicle type, capacity, miles - only if not Martinez
    if assignment["driver"] != "Martinez":
        family_data = next(f for f in families if f["name"] == assignment["driver"])
        row.addElement(text_cell(family_data["vehicle"]))
        row.addElement(number_cell(family_data["capacity"]))
        row.addElement(number_cell(assignment["passengers"]))
        row.addElement(number_cell(family_data["miles"]))
    else:
        # Empty cells for Martinez (need to be filled)
        row.addElement(empty_cell())
        row.addElement(empty_cell())
        row.addElement(number_cell(assignment["passengers"]))
        row.addElement(empty_cell())
    
    # Empty cell separator
    row.addElement(empty_cell())
    
    # Family info table (only for first 8 rows)
    if i < len(families):
        family = families[i]
        row.addElement(text_cell(family["name"]))
        row.addElement(text_cell(family["vehicle"]))
        row.addElement(number_cell(family["kids"]))
        row.addElement(number_cell(family["miles"]))
    else:
        for _ in range(4):
            row.addElement(empty_cell())
    
    table.addElement(row)

# Add empty rows
for _ in range(3):
    row = TableRow()
    for _ in range(11):
        row.addElement(empty_cell())
    table.addElement(row)

# Add notes section header
notes_row = TableRow()
notes_row.addElement(text_cell("NOTES - Availability Constraints:"))
for _ in range(10):
    notes_row.addElement(empty_cell())
table.addElement(notes_row)

# Add constraint notes
constraints = [
    "• Johnson family: Already driving 5 times, prefer not to add more",
    "• Thompson: Cannot drive Tuesdays (work conflict)",
    "• Chen: Cannot drive Thursdays (care for elderly parent)",
    "• Patel: Only has sedan (capacity 4), be mindful of passenger count"
]

for constraint in constraints:
    row = TableRow()
    row.addElement(text_cell(constraint))
    for _ in range(10):
        row.addElement(empty_cell())
    table.addElement(row)

# Add empty rows
for _ in range(2):
    row = TableRow()
    for _ in range(11):
        row.addElement(empty_cell())
    table.addElement(row)

# Add gas reimbursement calculation section header
calc_header_row = TableRow()
calc_header_row.addElement(text_cell("Gas Reimbursement Calculation (Total Fund: $240)"))
for _ in range(10):
    calc_header_row.addElement(empty_cell())
table.addElement(calc_header_row)

# Add calculation table headers
calc_headers_row = TableRow()
calc_headers_row.addElement(text_cell("Family"))
calc_headers_row.addElement(text_cell("Trips"))
calc_headers_row.addElement(text_cell("Miles"))
calc_headers_row.addElement(text_cell("Reimbursement"))
for _ in range(7):
    calc_headers_row.addElement(empty_cell())
table.addElement(calc_headers_row)

# Add rows for each family (for formulas to be added)
for family in families:
    row = TableRow()
    row.addElement(text_cell(family["name"]))
    # Empty cells for formulas to be added by agent
    for _ in range(10):
        row.addElement(empty_cell())
    table.addElement(row)

# Add more empty rows to make spreadsheet navigable
for _ in range(10):
    row = TableRow()
    for _ in range(11):
        row.addElement(empty_cell())
    table.addElement(row)

# Save
doc.save("/home/ga/Documents/carpool_schedule.ods")
print("✅ Created carpool_schedule.ods with Martinez entries")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/carpool_schedule.ods
sudo chmod 666 /home/ga/Documents/carpool_schedule.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/carpool_schedule.ods > /tmp/calc_carpool_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_carpool_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Soccer Carpool Coordinator Task Setup Complete ==="
echo "📋 Crisis: Martinez family dropped out - 6 driving dates need new drivers!"
echo "📝 Instructions:"
echo "  1. Find dates with 'Martinez' as driver (Column B)"
echo "  2. Assign replacement drivers from available families"
echo "  3. Update vehicle info (columns C, D, F) when changing driver"
echo "  4. Apply conditional formatting to highlight capacity issues"
echo "  5. Create formulas in calculation section (rows ~23-31) for:"
echo "     - Count trips per family: =COUNTIF(\$B\$2:\$B\$13, \"FamilyName\")"
echo "     - Sum miles per family: =SUMIF(\$B\$2:\$B\$13, \"FamilyName\", \$F\$2:\$F\$13)"
echo "     - Calculate reimbursement: (family_miles / total_miles) * 240"
echo "  6. Check constraints in Notes section before assigning!"