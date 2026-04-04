#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Road Trip Planner Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create template ODS file with headers and reference values
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, ParagraphProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")

# Create header row
header_row = TableRow()
headers = [
    "Day",
    "From → To", 
    "Distance (mi)",
    "Cumulative Distance (mi)",
    "Fuel Needed (gal)",
    "Fuel Cost ($)",
    "Driving Time (hrs)",
    "",  # Empty column H
    "",  # Empty column I
    "Reference Values"
]

for header_text in headers:
    cell = TableCell(valuetype="string")
    p = P(text=header_text)
    cell.addElement(p)
    header_row.addElement(cell)

table.addElement(header_row)

# Add empty data rows (rows 2-6 for days 1-5)
for i in range(5):
    row = TableRow()
    for j in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Add totals row (row 7)
totals_row = TableRow()
# A7: "TOTALS" label
cell = TableCell(valuetype="string")
p = P(text="TOTALS")
cell.addElement(p)
totals_row.addElement(cell)
# Empty cells for rest
for j in range(9):
    cell = TableCell()
    totals_row.addElement(cell)
table.addElement(totals_row)

# Add reference data rows (starting at row 2, column J)
# Row 2: Gas Price
ref_row_2 = TableRow()
for j in range(9):
    cell = TableCell()
    ref_row_2.addElement(cell)
# J2: Gas Price label and value
cell = TableCell(valuetype="string")
p = P(text="Gas Price: $3.45/gal")
cell.addElement(p)
ref_row_2.addElement(cell)
table.addElement(ref_row_2)

# Row 3: Vehicle MPG
ref_row_3 = TableRow()
for j in range(9):
    cell = TableCell()
    ref_row_3.addElement(cell)
# J3: MPG label and value
cell = TableCell(valuetype="string")
p = P(text="Vehicle MPG: 28")
cell.addElement(p)
ref_row_3.addElement(cell)
table.addElement(ref_row_3)

# Row 4: Avg Speed
ref_row_4 = TableRow()
for j in range(9):
    cell = TableCell()
    ref_row_4.addElement(cell)
# J4: Speed label and value
cell = TableCell(valuetype="string")
p = P(text="Avg Speed: 60 mph")
cell.addElement(p)
ref_row_4.addElement(cell)
table.addElement(ref_row_4)

# Add more empty rows to make it a proper spreadsheet
for _ in range(15):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/road_trip_template.ods")
print("✅ Created road_trip_template.ods with headers and reference values")
PYEOF

# Also create cells J2, J3, J4 with actual numeric values for formulas
# We need to modify the template to include actual values, not just text
python3 << 'PYEOF'
from odf import opendocument
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Load the created template
doc = opendocument.load("/home/ga/Documents/road_trip_template.ods")

# Get the first table
tables = doc.spreadsheet.getElementsByType(Table)
if tables:
    table = tables[0]
    rows = table.getElementsByType(TableRow)
    
    # Row index 8 = J2 (gas price) - but we need to set actual value
    # We'll add the values separately in another column for reference
    # Actually, let's recreate with proper numeric values
    pass

# For now, the template is fine with text labels
# Agent will use the reference values shown
doc.save("/home/ga/Documents/road_trip_template.ods")
print("✅ Template ready")
PYEOF

# Actually, let's create a better template with actual reference value cells
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()
table = Table(name="Sheet1")

# Row 1: Headers
header_row = TableRow()
headers = ["Day", "From → To", "Distance (mi)", "Cumulative Distance (mi)", 
           "Fuel Needed (gal)", "Fuel Cost ($)", "Driving Time (hrs)", "", "", ""]
for header_text in headers:
    cell = TableCell(valuetype="string")
    if header_text:
        p = P(text=header_text)
        cell.addElement(p)
    header_row.addElement(cell)
table.addElement(header_row)

# Rows 2-6: Empty data rows for days 1-5
for i in range(5):
    row = TableRow()
    for j in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Row 7: Totals row with label
totals_row = TableRow()
cell_a7 = TableCell(valuetype="string")
p = P(text="TOTALS")
cell_a7.addElement(p)
totals_row.addElement(cell_a7)
for j in range(9):
    cell = TableCell()
    totals_row.addElement(cell)
table.addElement(totals_row)

# Row 8: Empty
empty_row = TableRow()
for j in range(10):
    cell = TableCell()
    empty_row.addElement(cell)
table.addElement(empty_row)

# Now add reference value cells in a separate area
# Let's put them in column J (index 9), starting at row 2
# We need to go back and add them to the right rows

# Actually, let's rebuild more carefully
# Start over with proper structure
doc = OpenDocumentSpreadsheet()
table = Table(name="Sheet1")

# Row 1: Headers
row1 = TableRow()
for col_idx in range(15):  # More columns for safety
    if col_idx == 0:
        cell = TableCell(valuetype="string")
        p = P(text="Day")
        cell.addElement(p)
    elif col_idx == 1:
        cell = TableCell(valuetype="string")
        p = P(text="From → To")
        cell.addElement(p)
    elif col_idx == 2:
        cell = TableCell(valuetype="string")
        p = P(text="Distance (mi)")
        cell.addElement(p)
    elif col_idx == 3:
        cell = TableCell(valuetype="string")
        p = P(text="Cumulative Distance (mi)")
        cell.addElement(p)
    elif col_idx == 4:
        cell = TableCell(valuetype="string")
        p = P(text="Fuel Needed (gal)")
        cell.addElement(p)
    elif col_idx == 5:
        cell = TableCell(valuetype="string")
        p = P(text="Fuel Cost ($)")
        cell.addElement(p)
    elif col_idx == 6:
        cell = TableCell(valuetype="string")
        p = P(text="Driving Time (hrs)")
        cell.addElement(p)
    else:
        cell = TableCell()
    row1.addElement(cell)
table.addElement(row1)

# Row 2-6: Data rows (with reference values in column J)
for row_idx in range(2, 7):  # Rows 2-6
    row = TableRow()
    for col_idx in range(15):
        if col_idx == 9 and row_idx == 2:  # J2: Gas price
            cell = TableCell(valuetype="float", value=3.45)
            p = P(text="3.45")
            cell.addElement(p)
        elif col_idx == 9 and row_idx == 3:  # J3: MPG
            cell = TableCell(valuetype="float", value=28)
            p = P(text="28")
            cell.addElement(p)
        elif col_idx == 9 and row_idx == 4:  # J4: Speed
            cell = TableCell(valuetype="float", value=60)
            p = P(text="60")
            cell.addElement(p)
        else:
            cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Row 7: Totals
row7 = TableRow()
for col_idx in range(15):
    if col_idx == 0:
        cell = TableCell(valuetype="string")
        p = P(text="TOTALS")
        cell.addElement(p)
    else:
        cell = TableCell()
    row7.addElement(cell)
table.addElement(row7)

# Add more empty rows
for _ in range(20):
    row = TableRow()
    for _ in range(15):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)
doc.save("/home/ga/Documents/road_trip_template.ods")
print("✅ Created road_trip_template.ods successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/road_trip_template.ods
sudo chmod 666 /home/ga/Documents/road_trip_template.ods

# Launch LibreOffice Calc with the template
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/road_trip_template.ods > /tmp/calc_roadtrip.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_roadtrip.log || true
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

# Position cursor at cell A2 (first data entry cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Road Trip Planner Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Enter route data for 5 days in columns A-C (rows 2-6)"
echo "  2. Create cumulative distance formulas in column D"
echo "  3. Calculate fuel needed in column E (=C2/\$J\$3)"
echo "  4. Calculate fuel cost in column F (=E2*\$J\$2)"
echo "  5. Calculate driving time in column G (=C2/\$J\$4)"
echo "  6. Add totals in row 7"
echo "  7. Apply conditional formatting to G2:G6 (>8 hours = red)"
echo ""
echo "📊 Reference values available in column J:"
echo "  J2 = Gas Price: \$3.45/gal"
echo "  J3 = Vehicle MPG: 28"
echo "  J4 = Avg Speed: 60 mph"