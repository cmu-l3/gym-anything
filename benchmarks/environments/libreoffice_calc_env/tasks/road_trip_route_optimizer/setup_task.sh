#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Road Trip Route Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the road trip template ODS file using Python
sudo apt-get update && sudo apt-get install -y python3-odf > /dev/null 2>&1
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TableCellProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for formatting
# Bold style
bold_style = Style(name="Bold", family="table-cell")
bold_style.addElement(TextProperties(fontweight="bold"))
doc.styles.addElement(bold_style)

# Currency style
currency_style = CurrencyStyle(name="Currency")
currency_style.addElement(CurrencySymbol(language="en", country="US", text="$"))
currency_style.addElement(Number(decimalplaces="2", minintegerdigits="1", grouping="true"))
doc.styles.addElement(currency_style)

cell_currency_style = Style(name="CellCurrency", family="table-cell", datastylename="Currency")
doc.styles.addElement(cell_currency_style)

# Create the main sheet
table = Table(name="Road Trip Planner")

# Helper function to create a cell with value
def create_cell(value, formula=None, value_type='string', style_name=None):
    cell = TableCell(valuetype=value_type)
    if formula:
        cell.setAttribute('formula', formula)
    if value is not None:
        p = P()
        p.addText(str(value))
        cell.addElement(p)
    if value_type == 'float':
        cell.setAttribute('value', str(value))
    if style_name:
        cell.setAttribute('stylename', style_name)
    return cell

# Row 1: Title
row = TableRow()
row.addElement(create_cell("ROAD TRIP PLANNER - Seattle National Parks Loop", style_name="Bold"))
for _ in range(5):
    row.addElement(create_cell(None))
table.addElement(row)

# Row 2: Empty
row = TableRow()
for _ in range(6):
    row.addElement(create_cell(None))
table.addElement(row)

# Row 3: Headers
row = TableRow()
headers = ["Leg", "Destination", "Miles", "Fuel Cost", "Drive Time (hrs)", "Cumulative Miles"]
for header in headers:
    row.addElement(create_cell(header, style_name="Bold"))
table.addElement(row)

# Route data
routes = [
    (1, "Seattle to Portland", 173),
    (2, "Portland to Crater Lake", 285),
    (3, "Crater Lake to Bend", 90),
    (4, "Bend to Burns", 130),
    (5, "Burns to Boise", 185),
    (6, "Boise to Sun Valley", 155),
    (7, "Sun Valley to Spokane", 410),
    (8, "Spokane to Seattle", 280)
]

# Rows 4-11: Data rows (with empty formula columns)
for leg_num, destination, miles in routes:
    row = TableRow()
    row.addElement(create_cell(leg_num, value_type='float'))
    row.addElement(create_cell(destination))
    row.addElement(create_cell(miles, value_type='float'))
    row.addElement(create_cell(None))  # Fuel Cost - to be filled
    row.addElement(create_cell(None))  # Drive Time - to be filled
    row.addElement(create_cell(None))  # Cumulative Miles - to be filled
    table.addElement(row)

# Row 12: Empty
row = TableRow()
for _ in range(6):
    row.addElement(create_cell(None))
table.addElement(row)

# Row 13: Totals row
row = TableRow()
row.addElement(create_cell(None))
row.addElement(create_cell("TOTALS:", style_name="Bold"))
row.addElement(create_cell(1708, value_type='float'))  # Total miles
row.addElement(create_cell(None))  # Total Fuel Cost - to be filled
row.addElement(create_cell(None))  # Total Drive Time - to be filled
row.addElement(create_cell(None))
table.addElement(row)

# Row 14: Empty
row = TableRow()
for _ in range(6):
    row.addElement(create_cell(None))
table.addElement(row)

# Row 15-19: Constants section
constants_data = [
    ("CONSTANTS:", ""),
    ("Vehicle MPG:", 25),
    ("Gas Price ($/gal):", 3.80),
    ("Avg Speed (mph):", 60),
    ("Budget ($):", 400),
    ("Max Drive Time (hrs):", 24)
]

for label, value in constants_data:
    row = TableRow()
    row.addElement(create_cell(label, style_name="Bold"))
    if value:
        if isinstance(value, float):
            row.addElement(create_cell(value, value_type='float'))
        else:
            row.addElement(create_cell(value, value_type='float'))
    else:
        row.addElement(create_cell(None))
    for _ in range(4):
        row.addElement(create_cell(None))
    table.addElement(row)

# Add empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/road_trip_plan.ods")
print("✅ Created road trip template ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/road_trip_plan.ods
sudo chmod 666 /home/ga/Documents/road_trip_plan.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/road_trip_plan.ods > /tmp/calc_roadtrip_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_roadtrip_task.log || true
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

# Position cursor at cell D4 (first Fuel Cost cell)
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down Down Down
sleep 0.2
safe_xdotool ga :1 key Right Right Right
sleep 0.2

echo "=== Road Trip Route Optimizer Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Maya needs help finishing her road trip calculations!"
echo ""
echo "✏️  TODO:"
echo "  1. Column D (Fuel Cost): Add formula (Miles ÷ MPG × Gas Price)"
echo "     Example for D4: =(C4/\$B\$16)*\$B\$17"
echo "     Copy down for all 8 legs"
echo ""
echo "  2. Column E (Drive Time): Add formula (Miles ÷ Speed)"
echo "     Example for E4: =C4/\$B\$18"
echo "     Copy down for all 8 legs"
echo ""
echo "  3. Column F (Cumulative Miles): Running total"
echo "     F4: =C4"
echo "     F5: =F4+C5 (and copy down)"
echo ""
echo "  4. Row 13 Totals:"
echo "     D13: =SUM(D4:D11)"
echo "     E13: =SUM(E4:E11)"
echo ""
echo "  5. Format column D as Currency ($)"
echo ""
echo "📊 CONSTANTS (in cells B16-B19):"
echo "  • MPG: 25  |  Gas Price: \$3.80  |  Speed: 60 mph"
echo "  • Budget: \$400  |  Max Time: 24 hours"
echo ""
echo "🎯 GOAL: Will they fit under \$400 and 24 hours?"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"