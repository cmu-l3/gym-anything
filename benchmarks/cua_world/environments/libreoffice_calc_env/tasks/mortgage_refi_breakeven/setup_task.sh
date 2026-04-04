#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mortgage Refinance Decision Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create mortgage refinance template ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, ParagraphProperties, TableColumnProperties
from odf.number import NumberStyle, CurrencyStyle, Number, Text as NumberText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for formatting
# Bold style
bold_style = Style(name="Bold", family="paragraph")
bold_style.addElement(TextProperties(fontweight="bold"))
doc.styles.addElement(bold_style)

# Title style (bold, larger)
title_style = Style(name="Title", family="paragraph")
title_style.addElement(TextProperties(fontweight="bold", fontsize="14pt"))
doc.styles.addElement(title_style)

# Currency style
currency_style = CurrencyStyle(name="Currency1")
currency_style.addElement(NumberText(text="$"))
currency_style.addElement(Number(decimalplaces=0, minintegerdigits=1, grouping=True))
doc.styles.addElement(currency_style)

# Percentage style
percent_style = NumberStyle(name="Percent1")
percent_style.addElement(Number(decimalplaces=2, minintegerdigits=1))
percent_style.addElement(NumberText(text="%"))
doc.styles.addElement(percent_style)

# Add a sheet named "Refinance Analysis"
table = Table(name="Refinance Analysis")
doc.spreadsheet.addElement(table)

def add_row(values, value_types=None):
    """Add a row to the table with specified values and types"""
    row = TableRow()
    for i, value in enumerate(values):
        cell = TableCell()
        if value is not None:
            p = P(text=str(value))
            cell.addElement(p)
            
            # Set value type if specified
            if value_types and i < len(value_types):
                vtype = value_types[i]
                if vtype == 'float':
                    cell.setAttribute('valuetype', 'float')
                    cell.setAttribute('value', str(value))
                elif vtype == 'percentage':
                    cell.setAttribute('valuetype', 'percentage')
                    cell.setAttribute('value', str(float(value)/100))
                elif vtype == 'string':
                    cell.setAttribute('valuetype', 'string')
        row.addElement(cell)
    table.addElement(row)
    return row

# Row 1: Title
add_row(["MORTGAGE REFINANCE DECISION CALCULATOR", None, None, None, None])

# Row 2: Empty
add_row([None, None, None, None, None])

# Row 3: Section header
add_row(["CURRENT MORTGAGE", None, None, None, None])

# Row 4-8: Current mortgage details
add_row(["Original Loan:", "$285,000", None, None, None])
add_row(["Current Rate:", "6.50%", None, None, None])
add_row(["Years Remaining:", "23", None, None, None])
add_row(["Monthly Payment (P&I):", "$1,806", None, None, None])
add_row(["Estimated Balance:", "$238,000", None, None, None], ['string', 'float'])

# Row 9: Empty
add_row([None, None, None, None, None])

# Row 10: Refinance offers header
add_row(["REFINANCE OFFERS", None, "Offer 1", "Offer 2", "Offer 3"])

# Row 11-13: Offer details
add_row(["Interest Rate (APR)", None, "4.75%", "4.25%", "5.125%"])
add_row(["Loan Term (years)", None, "30", "20", "30"])
add_row(["Closing Costs", None, "$4,200", "$6,800", "$0"])

# Row 14: Empty
add_row([None, None, None, None, None])

# Row 15: Analysis section header
add_row(["ANALYSIS", None, "Offer 1", "Offer 2", "Offer 3"])

# Row 16-19: Calculation rows (TO BE FILLED BY AGENT)
add_row(["New Monthly Payment", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])
add_row(["Monthly Savings", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])
add_row(["Break-Even (months)", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])
add_row(["Break-Even (years)", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])

# Row 20: Empty
add_row([None, None, None, None, None])

# Row 21: Long-term savings header
add_row(["LONG-TERM SAVINGS", None, "Offer 1", "Offer 2", "Offer 3"])

# Row 22-23: Savings projections (TO BE FILLED BY AGENT)
add_row(["5-Year Net Savings", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])
add_row(["7-Year Net Savings", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])

# Row 24: Empty
add_row([None, None, None, None, None])

# Row 25: Recommendation row (TO BE FILLED BY AGENT)
add_row(["RECOMMENDATION", None, "[FORMULA]", "[FORMULA]", "[FORMULA]"])

# Add extra empty rows
for _ in range(10):
    add_row([None, None, None, None, None])

# Save the file
doc.save("/home/ga/Documents/mortgage_refi.ods")
print("✅ Created mortgage refinance template ODS file")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/mortgage_refi.ods
sudo chmod 666 /home/ga/Documents/mortgage_refi.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/mortgage_refi.ods > /tmp/calc_refi_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_refi_task.log || true
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

# Navigate to cell C16 (first formula cell) to help agent start
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Click on cell C16 (New Monthly Payment for Offer 1)
# Navigate down to row 16, right to column C
for i in {1..15}; do
    safe_xdotool ga :1 key Down
    sleep 0.05
done
for i in {1..2}; do
    safe_xdotool ga :1 key Right
    sleep 0.05
done

echo "=== Mortgage Refinance Task Setup Complete ==="
echo "📊 Scenario: Sarah needs to evaluate 3 refinance offers"
echo "📝 Your mission:"
echo "  1. Calculate new monthly payments using PMT function (Row 16)"
echo "     Formula: =PMT(rate/12, years*12, -238000)"
echo "  2. Calculate monthly savings: Current payment - New payment (Row 17)"
echo "  3. Calculate break-even timeline: Closing costs / Monthly savings (Rows 18-19)"
echo "  4. Calculate 5-year and 7-year net savings (Rows 22-23)"
echo "  5. Add decision logic: IF statements for recommendations (Row 25)"
echo "  6. Format currency columns appropriately"
echo ""
echo "💡 Key Info:"
echo "  - Current payment: $1,806/month"
echo "  - Loan balance: $238,000"
echo "  - Expected break-even: Offer 1 (~0.6 yrs), Offer 2 (~1.7 yrs), Offer 3 (~0 yrs)"
echo ""
echo "✅ Cursor positioned at C16 (first calculation cell)"