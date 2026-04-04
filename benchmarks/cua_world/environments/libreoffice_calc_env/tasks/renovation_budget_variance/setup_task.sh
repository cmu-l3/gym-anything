#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Renovation Budget Variance Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create the initial budget spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Budget"
table = Table(name="Budget")
doc.spreadsheet.addElement(table)

# Define headers
headers = ["Category", "Budget", "Actual", "Variance ($)", "% Over Budget"]

# Define data rows (Category, Budget, Actual)
# Some Actual values are empty (Labor - project in progress)
data_rows = [
    ["Plumbing", 3500, 4200],
    ["Electrical", 2800, 2650],
    ["Flooring", 4500, 5800],
    ["Cabinets", 8000, 8000],
    ["Paint", 1200, 980],
    ["Fixtures", 2400, 2890],
    ["Labor", 6000, None],  # In-progress, no actual yet
    ["Permits", 800, 750]
]

# Helper function to create cell with value
def create_cell(value=None, value_type=None, formula=None):
    cell = TableCell()
    if formula:
        cell.setAttribute('formula', formula)
    if value is not None:
        if value_type == 'float':
            cell.setAttribute('valuetype', 'float')
            cell.setAttribute('value', str(value))
        elif value_type == 'string':
            cell.setAttribute('valuetype', 'string')
        p = P(text=str(value))
        cell.addElement(p)
    return cell

# Add header row
header_row = TableRow()
for header in headers:
    cell = create_cell(header, 'string')
    header_row.addElement(cell)
table.addElement(header_row)

# Add data rows
for row_data in data_rows:
    row = TableRow()
    
    # Category (string)
    cell = create_cell(row_data[0], 'string')
    row.addElement(cell)
    
    # Budget (number)
    cell = create_cell(row_data[1], 'float')
    row.addElement(cell)
    
    # Actual (number or empty)
    if row_data[2] is not None:
        cell = create_cell(row_data[2], 'float')
    else:
        cell = create_cell()  # Empty cell
    row.addElement(cell)
    
    # Variance (empty - agent will add formula)
    cell = create_cell()
    row.addElement(cell)
    
    # % Over Budget (empty - agent will add formula)
    cell = create_cell()
    row.addElement(cell)
    
    table.addElement(row)

# Add Total row
total_row = TableRow()
# "Total" label
cell = create_cell("Total", 'string')
total_row.addElement(cell)
# Empty cells for totals (agent will add formulas)
for _ in range(4):  # Budget Total, Actual Total, Variance Total, empty
    cell = create_cell()
    total_row.addElement(cell)
table.addElement(total_row)

# Add some extra empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/renovation_budget.ods")
print("Created renovation budget spreadsheet successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/renovation_budget.ods
sudo chmod 666 /home/ga/Documents/renovation_budget.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/renovation_budget.ods > /tmp/calc_renovation.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_renovation.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Ensure cursor is at cell D2 (start of variance column)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to D2 (right 3 times, down 1)
safe_xdotool ga :1 key Right Right Right Down
sleep 0.3

echo "=== Renovation Budget Variance Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add variance formulas in column D: =C2-B2, etc."
echo "  2. Add percentage formulas in column E: =D2/B2*100 or =D2/B2"
echo "  3. Add SUM formulas in row 10 for totals"
echo "  4. Apply conditional formatting to column D (highlight positive values)"
echo "  5. Format columns B, C, D as currency"
echo "  6. Format column E as percentage"
echo ""
echo "💡 Real-world context: You're analyzing which renovation categories"
echo "   are over budget and by how much percentage."