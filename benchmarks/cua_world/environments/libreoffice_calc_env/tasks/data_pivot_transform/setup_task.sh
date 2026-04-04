#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Data Restructuring Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (for ODS file creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create ODS file with source data (wide format)
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a bold text style for headers
bold_style = Style(name="BoldHeader", family="table-cell")
bold_style.addElement(TextProperties(fontweight="bold"))
doc.styles.addElement(bold_style)

# Add a sheet named "Quarterly Sales"
table = Table(name="Quarterly Sales")
doc.spreadsheet.addElement(table)

# Define the source data (wide format)
headers = ["Category", "Q1", "Q2", "Q3", "Q4"]
data_rows = [
    ["Electronics", 45000, 52000, 48000, 61000],
    ["Home & Garden", 23000, 28000, 31000, 26000],
    ["Clothing", 18000, 15000, 22000, 29000],
    ["Sports Equipment", 12000, 14000, 19000, 16000],
    ["Books", 8000, 7500, 8200, 11000]
]

# Create header row
header_row = TableRow()
for header_text in headers:
    cell = TableCell(valuetype="string", stylename="BoldHeader")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Create data rows
for row_data in data_rows:
    row = TableRow()
    for i, value in enumerate(row_data):
        if i == 0:  # Category column (string)
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=str(value)))
        else:  # Sales columns (numbers)
            cell = TableCell(valuetype="float", value=float(value))
            cell.addElement(P(text=str(value)))
        row.addElement(cell)
    table.addElement(row)

# Add empty rows to make space for transformation
for _ in range(30):
    row = TableRow()
    for _ in range(15):  # Enough columns for both source and destination
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/quarterly_sales.ods"
doc.save(output_path)
print(f"✅ Created source data file: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/quarterly_sales.ods
sudo chmod 666 /home/ga/Documents/quarterly_sales.ods

# Verify file was created
if [ -f "/home/ga/Documents/quarterly_sales.ods" ]; then
    echo "✅ Source file verified: $(ls -lh /home/ga/Documents/quarterly_sales.ods)"
else
    echo "❌ ERROR: Failed to create source file"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/quarterly_sales.ods > /tmp/calc_restructure_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_restructure_task.log || true
    # Don't exit, continue to allow manual intervention
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue
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
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
else
    echo "⚠️  Warning: Could not find Calc window ID"
fi

# Position cursor at A1 (top of source data)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo ""
echo "=== Data Restructuring Task Setup Complete ==="
echo ""
echo "📊 SOURCE DATA (Wide Format):"
echo "   Location: Columns A-E (Category, Q1, Q2, Q3, Q4)"
echo "   Data: 5 product categories × 4 quarters"
echo ""
echo "🎯 YOUR TASK:"
echo "   Transform to Long Format with 3 columns:"
echo "   • Category | Quarter | Sales"
echo "   • Create 20 data rows (5 categories × 4 quarters)"
echo "   • Suggested location: Columns G-I"
echo ""
echo "💡 APPROACH:"
echo "   1. Create headers in G1:I1 (Category, Quarter, Sales)"
echo "   2. For each category, create 4 rows (one per quarter)"
echo "   3. Use cell references to avoid retyping"
echo "   4. Verify: 20 data rows total"
echo ""
echo "✅ When complete, save with Ctrl+S"
echo ""