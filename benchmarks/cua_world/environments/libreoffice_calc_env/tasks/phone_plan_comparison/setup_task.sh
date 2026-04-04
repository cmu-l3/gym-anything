#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Phone Plan Comparison Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create the spreadsheet with pre-populated data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, ParagraphProperties, TableColumnProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for formatting
# Bold style
bold_style = Style(name="Bold", family="paragraph")
bold_style.addElement(TextProperties(fontweight="bold", fontsize="12pt"))
doc.styles.addElement(bold_style)

# Title style
title_style = Style(name="Title", family="paragraph")
title_style.addElement(TextProperties(fontweight="bold", fontsize="14pt"))
doc.styles.addElement(title_style)

# Create the main sheet
table = Table(name="Sheet1")

def create_text_cell(text, style_name=None):
    """Helper to create a cell with text"""
    cell = TableCell()
    p = P(stylename=style_name, text=str(text))
    cell.addElement(p)
    return cell

def create_empty_cell():
    """Helper to create an empty cell"""
    cell = TableCell()
    return cell

# Row 1: Title
row1 = TableRow()
row1.addElement(create_text_cell("Family Phone Plan Cost Comparison", "Title"))
for _ in range(9):
    row1.addElement(create_empty_cell())
table.addElement(row1)

# Row 2: Blank
row2 = TableRow()
for _ in range(10):
    row2.addElement(create_empty_cell())
table.addElement(row2)

# Row 3: Section header
row3 = TableRow()
row3.addElement(create_text_cell("Family Usage Summary", "Bold"))
for _ in range(9):
    row3.addElement(create_empty_cell())
table.addElement(row3)

# Row 4: Number of lines
row4 = TableRow()
row4.addElement(create_text_cell("Number of lines:"))
row4.addElement(create_text_cell("4"))
for _ in range(8):
    row4.addElement(create_empty_cell())
table.addElement(row4)

# Row 5: Data usage
row5 = TableRow()
row5.addElement(create_text_cell("Total data usage (GB):"))
row5.addElement(create_text_cell("22"))
for _ in range(8):
    row5.addElement(create_empty_cell())
table.addElement(row5)

# Row 6: Current plan cost
row6 = TableRow()
row6.addElement(create_text_cell("Current plan cost (after promo expires):"))
row6.addElement(create_text_cell("$240/month"))
for _ in range(8):
    row6.addElement(create_empty_cell())
table.addElement(row6)

# Row 7: Blank
row7 = TableRow()
for _ in range(10):
    row7.addElement(create_empty_cell())
table.addElement(row7)

# Row 8: Carrier pricing header
row8 = TableRow()
row8.addElement(create_text_cell("Carrier Pricing Options", "Bold"))
for _ in range(9):
    row8.addElement(create_empty_cell())
table.addElement(row8)

# Row 9: Carrier A
row9 = TableRow()
row9.addElement(create_text_cell("Carrier A (MegaTel):"))
row9.addElement(create_text_cell("$85 base + $20/line + $30 for 25GB data"))
for _ in range(8):
    row9.addElement(create_empty_cell())
table.addElement(row9)

# Row 10: Carrier B
row10 = TableRow()
row10.addElement(create_text_cell("Carrier B (ConnectPlus):"))
row10.addElement(create_text_cell("$60 base + $25/line + $15/GB over 20GB"))
for _ in range(8):
    row10.addElement(create_empty_cell())
table.addElement(row10)

# Row 11: Carrier C
row11 = TableRow()
row11.addElement(create_text_cell("Carrier C (FamilyLink):"))
row11.addElement(create_text_cell("$100 base + $15/line + unlimited data"))
for _ in range(8):
    row11.addElement(create_empty_cell())
table.addElement(row11)

# Row 12: Blank
row12 = TableRow()
for _ in range(10):
    row12.addElement(create_empty_cell())
table.addElement(row12)

# Row 13: Calculations header
row13 = TableRow()
row13.addElement(create_text_cell("Cost Calculations", "Bold"))
for _ in range(9):
    row13.addElement(create_empty_cell())
table.addElement(row13)

# Row 14: Carrier A Total (formula cell B14)
row14 = TableRow()
row14.addElement(create_text_cell("Carrier A Total:"))
row14.addElement(create_empty_cell())  # B14 - agent fills this
for _ in range(8):
    row14.addElement(create_empty_cell())
table.addElement(row14)

# Row 15: Carrier B Total (formula cell B15)
row15 = TableRow()
row15.addElement(create_text_cell("Carrier B Total:"))
row15.addElement(create_empty_cell())  # B15 - agent fills this
for _ in range(8):
    row15.addElement(create_empty_cell())
table.addElement(row15)

# Row 16: Carrier C Total (formula cell B16)
row16 = TableRow()
row16.addElement(create_text_cell("Carrier C Total:"))
row16.addElement(create_empty_cell())  # B16 - agent fills this
for _ in range(8):
    row16.addElement(create_empty_cell())
table.addElement(row16)

# Row 17: Blank
row17 = TableRow()
for _ in range(10):
    row17.addElement(create_empty_cell())
table.addElement(row17)

# Row 18: Best Plan (formula cell B18)
row18 = TableRow()
row18.addElement(create_text_cell("Best Plan Cost:", "Bold"))
row18.addElement(create_empty_cell())  # B18 - agent fills this
for _ in range(8):
    row18.addElement(create_empty_cell())
table.addElement(row18)

# Row 19: Monthly Savings (formula cell B19)
row19 = TableRow()
row19.addElement(create_text_cell("Monthly Savings:", "Bold"))
row19.addElement(create_empty_cell())  # B19 - agent fills this
for _ in range(8):
    row19.addElement(create_empty_cell())
table.addElement(row19)

# Add some extra empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        row.addElement(create_empty_cell())
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/phone_plan_comparison.ods")
print("✅ Created phone_plan_comparison.ods successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/phone_plan_comparison.ods
sudo chmod 666 /home/ga/Documents/phone_plan_comparison.ods

echo "✅ Spreadsheet created: /home/ga/Documents/phone_plan_comparison.ods"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/phone_plan_comparison.ods > /tmp/calc_phone_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_phone_task.log
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

# Position cursor at cell B14 (first formula cell)
echo "Positioning cursor at B14..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Navigate to B14: Right once (to B1), then Down 13 times (to B14)
safe_xdotool ga :1 key Right
sleep 0.2
for i in {1..13}; do
    safe_xdotool ga :1 key Down
    sleep 0.1
done

echo "=== Phone Plan Comparison Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Calculate Carrier A cost in B14: =85 + (20 * 4) + 30"
echo "  2. Calculate Carrier B cost in B15: =60 + (25 * 4) + IF(22 > 20, (22 - 20) * 15, 0)"
echo "  3. Calculate Carrier C cost in B16: =100 + (15 * 4) + 0"
echo "  4. Find best plan in B18: =MIN(B14:B16)"
echo "  5. Calculate savings in B19: =240 - B18"
echo ""
echo "Expected results: A=$195, B=$190, C=$160, Best=$160, Savings=$80"