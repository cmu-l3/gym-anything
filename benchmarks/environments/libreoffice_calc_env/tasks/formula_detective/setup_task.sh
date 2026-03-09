#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Formula Detective Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
echo "Ensuring odfpy is installed..."
pip3 install --quiet odfpy 2>/dev/null || apt-get update && apt-get install -y python3-odf

# Create the corrupted spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol
import sys

try:
    # Create new spreadsheet
    doc = OpenDocumentSpreadsheet()

    # Define styles for corrupted cells (red background)
    corrupted_style = Style(name="CorruptedCell", family="table-cell")
    corrupted_props = TableCellProperties(backgroundcolor="#ffcccc")
    corrupted_style.addElement(corrupted_props)
    doc.automaticstyles.addElement(corrupted_style)

    # Define currency style
    currency_style = NumberStyle(name="Currency1")
    currency_style.addElement(NumberText(text="$"))
    currency_style.addElement(Number(decimalplaces="2", minintegerdigits="1", grouping="true"))
    doc.styles.addElement(currency_style)

    # Add a sheet named "Commissions"
    table = Table(name="Commissions")
    doc.spreadsheet.addElement(table)

    # Header row
    header_row = TableRow()
    headers = ["Sales Rep", "Sales Amount", "Commission", "Status", "Total Payout"]
    for header_text in headers:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=header_text))
        header_row.addElement(cell)
    table.addElement(header_row)

    # Data rows with mix of intact formulas and corrupted values
    # Format: (name, sales, commission_formula_or_value, status, payout_formula_or_value, is_corrupted)
    data_rows = [
        ("Alice Johnson", 8500, "=IF(C2<=10000,C2*0.05,IF(C2<=25000,C2*0.07,C2*0.1))", "Standard", "=D2+IF(AND(E2=\"Premium\",D2>1000),500,0)", False),
        ("Bob Smith", 12000, 840, "Standard", 840, True),  # CORRUPTED: should be 7% = 840
        ("Carol White", 18000, "=IF(C4<=10000,C4*0.05,IF(C4<=25000,C4*0.07,C4*0.1))", "Premium", "=D4+IF(AND(E4=\"Premium\",D4>1000),500,0)", False),
        ("David Lee", 22000, 1540, "Premium", 2040, True),  # CORRUPTED: 7% = 1540, +500 bonus = 2040
        ("Emma Davis", 28000, "=IF(C6<=10000,C6*0.05,IF(C6<=25000,C6*0.07,C6*0.1))", "Standard", "=D6+IF(AND(E6=\"Premium\",D6>1000),500,0)", False),
        ("Frank Wilson", 15000, 1050, "Premium", 1550, True),  # CORRUPTED: 7% = 1050, +500 bonus = 1550
        ("Grace Brown", 5000, "=IF(C8<=10000,C8*0.05,IF(C8<=25000,C8*0.07,C8*0.1))", "Standard", "=D8+IF(AND(E8=\"Premium\",D8>1000),500,0)", False),
    ]

    for idx, (name, sales, commission, status, payout, is_corrupted) in enumerate(data_rows, start=2):
        row = TableRow()
        
        # Name cell
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=name))
        row.addElement(cell)
        
        # Sales Amount cell
        cell = TableCell(valuetype="float", value=str(sales))
        cell.addElement(P(text=f"${sales:,}"))
        row.addElement(cell)
        
        # Commission cell (formula or corrupted value)
        if isinstance(commission, str) and commission.startswith('='):
            # Intact formula
            cell = TableCell(valuetype="float", formula=commission)
            cell.addElement(P(text=""))  # Formula will calculate
        else:
            # Corrupted - static value with red background
            cell = TableCell(valuetype="float", value=str(commission), stylename="CorruptedCell")
            cell.addElement(P(text=f"${commission:,}"))
        row.addElement(cell)
        
        # Status cell
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=status))
        row.addElement(cell)
        
        # Total Payout cell (formula or corrupted value)
        if isinstance(payout, str) and payout.startswith('='):
            # Intact formula
            cell = TableCell(valuetype="float", formula=payout)
            cell.addElement(P(text=""))  # Formula will calculate
        else:
            # Corrupted - static value with red background
            cell = TableCell(valuetype="float", value=str(payout), stylename="CorruptedCell")
            cell.addElement(P(text=f"${payout:,}"))
        row.addElement(cell)
        
        table.addElement(row)

    # Add a few empty rows
    for _ in range(5):
        row = TableRow()
        for _ in range(5):
            cell = TableCell()
            row.addElement(cell)
        table.addElement(row)

    # Save the file
    output_path = "/home/ga/Documents/sales_commissions.ods"
    doc.save(output_path)
    print(f"✅ Created corrupted spreadsheet: {output_path}")
    sys.exit(0)

except Exception as e:
    print(f"❌ Error creating spreadsheet: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create spreadsheet"
    exit 1
fi

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/sales_commissions.ods
sudo chmod 666 /home/ga/Documents/sales_commissions.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/sales_commissions.ods > /tmp/calc_formula_detective.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_formula_detective.log || true
    # Don't exit - let task continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - let task continue
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
        
        # Position cursor at cell A1
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

echo "=== Formula Detective Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  🔍 ANALYZE the intact formulas to understand the commission structure"
echo "  🔴 Red-highlighted cells are CORRUPTED (formulas converted to values)"
echo "  🛠️  RECONSTRUCT the missing formulas in corrupted cells"
echo ""
echo "💡 Commission Structure (to deduce from examples):"
echo "   - Tier 1: Sales ≤ \$10,000 → 5% commission"
echo "   - Tier 2: Sales \$10,001-\$25,000 → 7% commission"
echo "   - Tier 3: Sales > \$25,000 → 10% commission"
echo ""
echo "💡 Bonus Logic (to deduce from examples):"
echo "   - Premium status + Commission > \$1,000 → +\$500 bonus"
echo ""
echo "🎯 Goal: Fix cells D3, D5, D7 (Commission) and F3, F5, F7 (Total Payout)"