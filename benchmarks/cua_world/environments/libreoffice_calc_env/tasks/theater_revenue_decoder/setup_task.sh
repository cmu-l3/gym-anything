#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Theater Revenue Decoder Task ==="

# Ensure Python ODF library is available
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || true

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the cryptic spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.number import NumberStyle, CurrencyStyle, Number, Text as NumText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "GalaRevenue"
table = Table(name="GalaRevenue")
doc.spreadsheet.addElement(table)

def create_cell(value=None, formula=None, value_type=None):
    """Helper to create cells with values or formulas"""
    cell = TableCell()
    if formula:
        cell.setAttribute('formula', formula)
        cell.setAttribute('valuetype', 'float')
    elif value is not None:
        if isinstance(value, (int, float)):
            cell.setAttribute('valuetype', 'float')
            cell.setAttribute('value', str(value))
        else:
            cell.setAttribute('valuetype', 'string')
        p = P()
        p.addText(str(value))
        cell.addElement(p)
    return cell

def create_row(cells_data):
    """Create a row with multiple cells"""
    row = TableRow()
    for cell_data in cells_data:
        if isinstance(cell_data, dict):
            cell = create_cell(**cell_data)
        else:
            cell = create_cell(value=cell_data)
        row.addElement(cell)
    return row

# Row 1: Cryptic headers
row1 = create_row([
    {'value': 'SR'}, 
    {'value': 'GEN'}, 
    {'value': 'STD'}, 
    {'value': 'COMP'}, 
    {'value': 'Total'}
])
table.addElement(row1)

# Row 2: Base prices (no labels)
row2 = create_row([
    {'value': 45},
    {'value': 65},
    {'value': 35},
    {'value': 0},
    {'value': ''}
])
table.addElement(row2)

# Row 3: Discount rates (no labels, cryptic)
row3 = create_row([
    {'value': 0.85},
    {'value': 1.00},
    {'value': 0.65},
    {'value': 0},
    {'value': ''}
])
table.addElement(row3)

# Row 4: Projected sales (no labels)
row4 = create_row([
    {'value': 40},
    {'value': 120},
    {'value': 30},
    {'value': 15},
    {'formula': 'of:=SUM([.A4:.D4])', 'value': 205}
])
table.addElement(row4)

# Row 5: Revenue per type (complex formulas, no explanation)
row5 = create_row([
    {'formula': 'of:=[.A2]*[.A3]*[.A4]'},
    {'formula': 'of:=[.B2]*[.B3]*[.B4]'},
    {'formula': 'of:=[.C2]*[.C3]*[.C4]'},
    {'formula': 'of:=[.D2]*[.D3]*[.D4]'},
    {'formula': 'of:=SUM([.A5:.D5])'}
])
table.addElement(row5)

# Row 6: Gross revenue with intentional #REF! error
row6 = create_row([
    {'value': 'GP'},
    {'formula': 'of:=[.E5]+[.F1]'},  # F1 doesn't exist, will cause #REF!-like issue
    {'value': ''},
    {'value': ''},
    {'value': ''}
])
table.addElement(row6)

# Row 7: Overhead (hardcoded 8% with no explanation)
row7 = create_row([
    {'value': 'OH'},
    {'formula': 'of:=[.E5]*0.08'},  # Hardcoded 8% - no label explaining what this is
    {'value': ''},
    {'value': ''},
    {'value': ''}
])
table.addElement(row7)

# Row 8: Net revenue
row8 = create_row([
    {'value': 'NP'},
    {'formula': 'of:=[.E5]-[.B7]-2500'},  # Hardcoded 2500 venue fee
    {'value': ''},
    {'value': ''},
    {'value': ''}
])
table.addElement(row8)

# Row 9: Empty
row9 = create_row([{'value': ''}, {'value': ''}, {'value': ''}, {'value': ''}, {'value': ''}])
table.addElement(row9)

# Row 10: Another cryptic calculation
row10 = create_row([
    {'value': 'BEP'},
    {'formula': 'of:=2500/[.B2]'},  # Break-even, no explanation
    {'value': ''},
    {'value': ''},
    {'value': ''}
])
table.addElement(row10)

# Add several more empty rows to make it look like a real spreadsheet
for _ in range(15):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/GalaTicketRevenue.ods")
print("✅ Created cryptic spreadsheet: GalaTicketRevenue.ods")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/GalaTicketRevenue.ods
sudo chmod 666 /home/ga/Documents/GalaTicketRevenue.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc with cryptic spreadsheet..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/GalaTicketRevenue.ods > /tmp/calc_theater_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_theater_task.log || true
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

echo "=== Theater Revenue Decoder Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   You've inherited this cryptic theater ticket revenue calculator from"
echo "   a departed treasurer. The gala is in 6 weeks and nobody understands"
echo "   how this spreadsheet works!"
echo ""
echo "🎯 YOUR MISSION:"
echo "   1. Decode the abbreviations (SR, GEN, STD, COMP, GP, OH, NP, BEP)"
echo "   2. Add descriptive labels next to cryptic headers"
echo "   3. Inspect formulas and add cell comments explaining them"
echo "   4. Fix or document the #REF! error in row 6"
echo "   5. Create a 'Documentation' sheet with:"
echo "      - Purpose of this spreadsheet"
echo "      - Input cells users should modify"
echo "      - Plain-language formula explanations"
echo "      - Hardcoded assumptions (like the 8% and 2500)"
echo "      - Usage instructions"
echo "   6. Add at least 6 cell comments (Right-click → Insert Comment)"
echo "   7. Save when done"
echo ""
echo "💡 HINTS:"
echo "   - Click cells to see formulas in formula bar"
echo "   - SR=Senior, GEN=General, STD=Student, COMP=Complimentary"
echo "   - GP=Gross Proceeds, OH=Overhead, NP=Net Proceeds, BEP=Break-Even Point"
echo "   - Look for hardcoded numbers: 0.08 (8% fee?), 2500 (venue rental?)"
echo "   - Right-click cells → Insert Comment to document formulas"
echo "   - Right-click sheet tab → Insert Sheet to create Documentation"