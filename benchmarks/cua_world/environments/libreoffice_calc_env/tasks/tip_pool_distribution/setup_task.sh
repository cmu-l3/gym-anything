#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tip Pool Distribution Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
if ! python3 -c "from odf import opendocument" 2>/dev/null; then
    echo "Installing python3-odf..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create the incomplete tip pooling spreadsheet
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, ParagraphProperties, TableColumnProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add bold style
bold_style = Style(name="Bold", family="paragraph")
bold_style.addElement(TextProperties(fontweight="bold", fontsize="12pt"))
doc.styles.addElement(bold_style)

# Add title style
title_style = Style(name="Title", family="paragraph")
title_style.addElement(TextProperties(fontweight="bold", fontsize="14pt"))
doc.styles.addElement(title_style)

# Create currency style
currency_style = NumberStyle(name="Currency")
currency_style.addElement(NumberText(text="$"))
currency_style.addElement(Number(decimalplaces=2, minintegerdigits=1, grouping=True))
doc.styles.addElement(currency_style)

# Create sheet
table = Table(name="Tip Pool")

def make_row(values, style_name=None):
    """Helper to create a row with values"""
    row = TableRow()
    for val in values:
        cell = TableCell()
        if val is not None:
            p = P(stylename=style_name, text=str(val))
            cell.addElement(p)
        row.addElement(cell)
    return row

# Row 1: Title
table.addElement(make_row(["Golden Spoon Restaurant - Weekly Tip Pool Distribution", None, None, None], "Title"))

# Row 2: Date and total
table.addElement(make_row(["Week of: May 12-18, 2024", None, "Total Tips Collected:", "$2,850.00"], "Bold"))

# Row 3: Blank
table.addElement(make_row([None, None, None, None]))

# Rows 4-7: Policy
table.addElement(make_row(["TIP POOLING POLICY:", None, None, None], "Bold"))
table.addElement(make_row(["- Support Staff (bussers, food runners): 20% of total tips", None, None, None]))
table.addElement(make_row(["- Service Staff (servers, bartenders): 80% of total tips", None, None, None]))
table.addElement(make_row(["- Distribution: Proportional to hours worked within each role", None, None, None]))

# Row 8: Blank
table.addElement(make_row([None, None, None, None]))

# Row 9: Column headers
table.addElement(make_row(["Name", "Role", "Hours Worked", "Tip Amount"], "Bold"))

# Rows 10-17: Staff data (with some calculations missing)
staff_data = [
    ["Sarah Chen", "Server", "32", ""],
    ["David Martinez", "Bartender", "28", ""],
    ["Emma Rodriguez", "Server", "24", ""],
    ["Marcus Johnson", "Busser", "28", ""],
    ["Keisha Williams", "Food Runner", "18", ""],
    ["James Lee", "Busser", "15", ""],
    ["Maria Garcia", "Server + Busser", "12 + 8", ""],
]

for staff in staff_data:
    table.addElement(make_row(staff))

# Row 18: Blank
table.addElement(make_row([None, None, None, None]))

# Row 19: Blank
table.addElement(make_row([None, None, None, None]))

# Rows 20-22: Summary section (to be filled)
table.addElement(make_row(["SUPPORT STAFF POOL (20%):", None, None, ""], "Bold"))
table.addElement(make_row(["SERVICE STAFF POOL (80%):", None, None, ""], "Bold"))
table.addElement(make_row(["TOTAL DISTRIBUTED:", None, None, ""], "Bold"))

# Add more empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/tip_distribution.ods")
print("✅ Created incomplete tip pooling spreadsheet")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/tip_distribution.ods
sudo chmod 666 /home/ga/Documents/tip_distribution.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/tip_distribution.ods > /tmp/calc_tippool.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_tippool.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of screen to select desktop
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

# Navigate to first calculation cell (D10 - Sarah's tip amount)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key --repeat 9 Down
sleep 0.3
safe_xdotool ga :1 key --repeat 3 Right
sleep 0.3

echo "=== Tip Pool Distribution Task Setup Complete ==="
echo "📋 Task Summary:"
echo "  - Total tips: \$2,850.00"
echo "  - Support staff (20%): \$570.00"
echo "  - Service staff (80%): \$2,280.00"
echo "  - 7 staff members (1 worked both roles)"
echo ""
echo "📝 Instructions:"
echo "  1. Calculate total hours for support staff"
echo "  2. Calculate total hours for service staff"
echo "  3. Calculate hourly tip rate for each category"
echo "  4. Fill in individual tip amounts (hours × rate)"
echo "  5. Handle Maria's dual role (8h busser + 12h server)"
echo "  6. Verify total equals \$2,850.00"
echo ""
echo "💡 Hint: Use formulas like =SUM() and cell references"