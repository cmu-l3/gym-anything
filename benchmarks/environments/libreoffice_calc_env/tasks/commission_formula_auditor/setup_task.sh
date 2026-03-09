#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Commission Formula Auditor Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the commission spreadsheet with intentional formula error using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create table
table = Table(name="Sheet1")

# Row 1: Headers
row1 = TableRow()
headers = ["Salesperson", "Monthly Sales", "Commission Earned", "", "Commission Policy:"]
for i, header_text in enumerate(headers):
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    row1.addElement(cell)
table.addElement(row1)

# Row 2: Alice (with WRONG formula - this is the bug to find)
row2 = TableRow()
# A2: Alice
cell_a2 = TableCell(valuetype="string")
cell_a2.addElement(P(text="Alice"))
row2.addElement(cell_a2)
# B2: 15000
cell_b2 = TableCell(valuetype="float", value="15000")
cell_b2.addElement(P(text="15000"))
row2.addElement(cell_b2)
# C2: WRONG FORMULA - missing base commission
cell_c2 = TableCell(valuetype="float", formula="of:=IF(B2<=10000,B2*0.05,(B2-10000)*0.07)")
cell_c2.addElement(P(text="350"))  # Wrong result
row2.addElement(cell_c2)
# D2: Empty
row2.addElement(TableCell())
# E2: Policy line 1
cell_e2 = TableCell(valuetype="string")
cell_e2.addElement(P(text="- 5% on first $10,000 of monthly sales"))
row2.addElement(cell_e2)
table.addElement(row2)

# Row 3: Bob
row3 = TableRow()
cell_a3 = TableCell(valuetype="string")
cell_a3.addElement(P(text="Bob"))
row3.addElement(cell_a3)
cell_b3 = TableCell(valuetype="float", value="8000")
cell_b3.addElement(P(text="8000"))
row3.addElement(cell_b3)
# Same wrong formula pattern
cell_c3 = TableCell(valuetype="float", formula="of:=IF(B3<=10000,B3*0.05,(B3-10000)*0.07)")
cell_c3.addElement(P(text="400"))  # Correct because under threshold
row3.addElement(cell_c3)
row3.addElement(TableCell())
cell_e3 = TableCell(valuetype="string")
cell_e3.addElement(P(text="- 7% on amounts exceeding $10,000"))
row3.addElement(cell_e3)
table.addElement(row3)

# Row 4: Carol
row4 = TableRow()
cell_a4 = TableCell(valuetype="string")
cell_a4.addElement(P(text="Carol"))
row4.addElement(cell_a4)
cell_b4 = TableCell(valuetype="float", value="22000")
cell_b4.addElement(P(text="22000"))
row4.addElement(cell_b4)
cell_c4 = TableCell(valuetype="float", formula="of:=IF(B4<=10000,B4*0.05,(B4-10000)*0.07)")
cell_c4.addElement(P(text="840"))  # Wrong result
row4.addElement(cell_c4)
row4.addElement(TableCell())
cell_e4 = TableCell(valuetype="string")
cell_e4.addElement(P(text=""))
row4.addElement(cell_e4)
table.addElement(row4)

# Row 5: David
row5 = TableRow()
cell_a5 = TableCell(valuetype="string")
cell_a5.addElement(P(text="David"))
row5.addElement(cell_a5)
cell_b5 = TableCell(valuetype="float", value="5500")
cell_b5.addElement(P(text="5500"))
row5.addElement(cell_b5)
cell_c5 = TableCell(valuetype="float", formula="of:=IF(B5<=10000,B5*0.05,(B5-10000)*0.07)")
cell_c5.addElement(P(text="275"))  # Correct because under threshold
row5.addElement(cell_c5)
row5.addElement(TableCell())
cell_e5 = TableCell(valuetype="string")
cell_e5.addElement(P(text="Example: $15,000 sales ="))
row5.addElement(cell_e5)
table.addElement(row5)

# Row 6: Empty row with policy example
row6 = TableRow()
for _ in range(4):
    row6.addElement(TableCell())
cell_e6 = TableCell(valuetype="string")
cell_e6.addElement(P(text="($10,000×5%) + ($5,000×7%) = $850"))
row6.addElement(cell_e6)
table.addElement(row6)

# Add column F header separately (Audit Status)
# Go back and add F1
table_rows = list(table.getElementsByType(TableRow))
if len(table_rows) > 0:
    first_row = table_rows[0]
    cell_f1 = TableCell(valuetype="string")
    cell_f1.addElement(P(text="Audit Status - Enter Findings Here"))
    first_row.addElement(cell_f1)

# Add empty rows to make it a proper spreadsheet
for _ in range(15):
    row = TableRow()
    for _ in range(10):
        row.addElement(TableCell())
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/commission_data.ods")
print("✅ Created commission_data.ods with intentional formula error")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/commission_data.ods
sudo chmod 666 /home/ga/Documents/commission_data.ods

# Verify file was created
if [ -f "/home/ga/Documents/commission_data.ods" ]; then
    echo "✅ Commission spreadsheet created successfully"
    ls -lh /home/ga/Documents/commission_data.ods
else
    echo "❌ ERROR: Failed to create commission_data.ods"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc with commission data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/commission_data.ods > /tmp/calc_audit_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_audit_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "WARNING: LibreOffice Calc window did not appear in expected time"
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
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at A1 to start
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Commission Formula Auditor Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: Alice (row 2) claims her commission is wrong for \$15,000 sales"
echo "📝 TASK: Audit the commission formulas and identify the error"
echo ""
echo "🔍 Instructions:"
echo "  1. Read the Commission Policy in column E (cells E1-E6)"
echo "  2. Notice Alice's commission: \$350 for \$15,000 sales (seems low?)"
echo "  3. Click on cell C2 to inspect the formula in the formula bar"
echo "  4. Compare the formula logic against the written policy"
echo "  5. Identify what's wrong with the formula"
echo "  6. Document findings in cell F1 OR add comment to C2"
echo "  7. (Bonus) Correct the formula if you can identify the fix"
echo ""
echo "💡 Hint: Policy uses TIERED rates (like tax brackets)"
echo "    Expected for \$15,000: (\$10,000 × 5%) + (\$5,000 × 7%) = \$850"