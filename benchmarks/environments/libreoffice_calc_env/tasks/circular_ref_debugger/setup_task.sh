#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Circular Reference Debugger Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a budget spreadsheet with circular reference using Python
echo "Creating broken budget spreadsheet..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, ParagraphProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create currency style
currency_style = CurrencyStyle(name="Currency1")
currency_symbol = CurrencySymbol(language="en", country="US")
currency_symbol.addText("$")
currency_style.addElement(currency_symbol)
number_elem = Number(decimalplaces="2", minintegerdigits="1", grouping="true")
currency_style.addElement(number_elem)
doc.styles.addElement(currency_style)

# Create cell style for currency
currency_cell_style = Style(name="CurrencyCell", family="table-cell")
currency_cell_style.addAttribute("datastylename", "Currency1")
doc.styles.addElement(currency_cell_style)

# Add a sheet
table = Table(name="Budget")
doc.spreadsheet.addElement(table)

def create_text_cell(text_content):
    """Create a cell with text content"""
    cell = TableCell(valuetype="string")
    p = P()
    p.addText(text_content)
    cell.addElement(p)
    return cell

def create_value_cell(value):
    """Create a cell with numeric value"""
    cell = TableCell(valuetype="float", value=str(value))
    p = P()
    p.addText(str(value))
    cell.addElement(p)
    return cell

def create_currency_cell(value):
    """Create a cell with currency value"""
    cell = TableCell(valuetype="currency", currency="USD", value=str(value))
    cell.setAttribute("stylename", "CurrencyCell")
    p = P()
    p.addText(f"${value:,.2f}")
    cell.addElement(p)
    return cell

def create_formula_cell(formula):
    """Create a cell with formula"""
    cell = TableCell(valuetype="float", formula=formula)
    # Don't set value - let Calc calculate it
    return cell

def create_empty_cell():
    """Create an empty cell"""
    return TableCell()

# Row 1: Title
row1 = TableRow()
row1.addElement(create_text_cell("Q4 Department Budget"))
row1.addElement(create_empty_cell())
table.addElement(row1)

# Row 2: Empty
row2 = TableRow()
row2.addElement(create_empty_cell())
row2.addElement(create_empty_cell())
table.addElement(row2)

# Row 3: Revenue
row3 = TableRow()
row3.addElement(create_text_cell("Revenue"))
row3.addElement(create_currency_cell(75000.00))
table.addElement(row3)

# Row 4: Empty
row4 = TableRow()
row4.addElement(create_empty_cell())
row4.addElement(create_empty_cell())
table.addElement(row4)

# Row 5: Section header
row5 = TableRow()
row5.addElement(create_text_cell("Direct Expenses"))
row5.addElement(create_empty_cell())
table.addElement(row5)

# Row 6: Salaries
row6 = TableRow()
row6.addElement(create_text_cell("Salaries"))
row6.addElement(create_currency_cell(25000.00))
table.addElement(row6)

# Row 7: Supplies
row7 = TableRow()
row7.addElement(create_text_cell("Supplies"))
row7.addElement(create_currency_cell(5000.00))
table.addElement(row7)

# Row 8: Overhead (CIRCULAR REFERENCE - depends on B14)
row8 = TableRow()
row8.addElement(create_text_cell("Overhead (15% of Net)"))
row8.addElement(create_formula_cell("of:=[.B14]*0.15"))  # CIRCULAR!
table.addElement(row8)

# Row 9: Empty
row9 = TableRow()
row9.addElement(create_empty_cell())
row9.addElement(create_empty_cell())
table.addElement(row9)

# Row 10: Subtotal Expenses
row10 = TableRow()
row10.addElement(create_text_cell("Subtotal Expenses"))
row10.addElement(create_formula_cell("of:=SUM([.B6:.B8])"))
table.addElement(row10)

# Row 11: Empty
row11 = TableRow()
row11.addElement(create_empty_cell())
row11.addElement(create_empty_cell())
table.addElement(row11)

# Row 12: Total Expenses
row12 = TableRow()
row12.addElement(create_text_cell("Total Expenses"))
row12.addElement(create_formula_cell("of:=[.B10]"))
table.addElement(row12)

# Row 13: Empty
row13 = TableRow()
row13.addElement(create_empty_cell())
row13.addElement(create_empty_cell())
table.addElement(row13)

# Row 14: Net Income (CIRCULAR - depends on B12, which depends on B8, which depends on B14)
row14 = TableRow()
row14.addElement(create_text_cell("Net Income"))
row14.addElement(create_formula_cell("of:=[.B3]-[.B12]"))  # CIRCULAR!
table.addElement(row14)

# Row 15: Grand Total
row15 = TableRow()
row15.addElement(create_text_cell("Grand Total"))
row15.addElement(create_formula_cell("of:=[.B14]"))
table.addElement(row15)

# Add some more empty rows
for _ in range(5):
    row = TableRow()
    for _ in range(10):
        row.addElement(create_empty_cell())
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/budget_circular.ods"
doc.save(output_path)
print(f"✅ Created broken budget spreadsheet: {output_path}")
print("   Circular reference: B8 → B14 → B12 → B10 → B8")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/budget_circular.ods
sudo chmod 666 /home/ga/Documents/budget_circular.ods

# Verify file was created
if [ ! -f "/home/ga/Documents/budget_circular.ods" ]; then
    echo "ERROR: Failed to create budget spreadsheet"
    exit 1
fi

echo "✅ Budget spreadsheet created successfully"
ls -lh /home/ga/Documents/budget_circular.ods

# Launch LibreOffice Calc with the broken spreadsheet
echo "Launching LibreOffice Calc with broken budget..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/budget_circular.ods > /tmp/calc_circular_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_circular_task.log || true
    # Don't exit - continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "WARNING: LibreOffice Calc window did not appear in time"
    # Don't exit - continue anyway
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
        
        # If circular reference dialog appears, dismiss it
        # Press Escape to close any warning dialogs
        safe_xdotool ga :1 key Escape
        sleep 0.3
    fi
fi

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Circular Reference Debugger Task Setup Complete ==="
echo ""
echo "⚠️  CIRCULAR REFERENCE DETECTED!"
echo ""
echo "📋 Problem:"
echo "   - Cell B8 (Overhead) = B14 * 0.15"
echo "   - Cell B14 (Net Income) = B3 - B12"
echo "   - Cell B12 depends on B10, which includes B8"
echo "   - This creates a loop: B8 → B14 → B12 → B10 → B8"
echo ""
echo "🎯 Your Task:"
echo "   1. Identify the circular reference"
echo "   2. Fix the formulas to break the circular dependency"
echo "   3. Preserve the calculation logic"
echo "   4. Ensure Grand Total (B15) calculates correctly"
echo ""
echo "💡 Hint: Calculate Overhead based on direct expenses only (B6+B7)"
echo "   Expected Grand Total after fix: $40,500.00"