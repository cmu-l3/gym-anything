#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Genealogy Age Validator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (needed for creating ODS files)
if ! python3 -c "from odf import opendocument" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create genealogy data spreadsheet with pre-populated data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, ParagraphProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a table (sheet)
table = Table(name="Genealogy Records")

# Header row
header_data = ["Person Name", "Known Birth Year", "Record Date", "Recorded Age", "Implied Birth Year", "Flag Inconsistency"]
header_row = TableRow()
for header in header_data:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Genealogy data with realistic records
# Format: (Name, Known Birth Year, Record Date, Recorded Age)
# Intentionally includes inconsistencies for testing
genealogy_data = [
    ("Sarah Johnson", 1850, 1895, 40),      # 1855 implied - 5 year gap -> INVESTIGATE
    ("William Davis", 1845, 1880, 35),      # 1845 implied - 0 year gap -> OK
    ("Mary Wilson", 1862, 1900, 38),        # 1862 implied - 0 year gap -> OK
    ("James Miller", 1855, 1890, 32),       # 1858 implied - 3 year gap -> INVESTIGATE
    ("Elizabeth Brown", 1848, 1885, 36),    # 1849 implied - 1 year gap -> OK
    ("Robert Taylor", 1840, 1875, 42),      # 1833 implied - 7 year gap -> INVESTIGATE
    ("Margaret Anderson", 1858, 1895, 37),  # 1858 implied - 0 year gap -> OK
    ("Thomas Moore", 1852, 1892, 41),       # 1851 implied - 1 year gap -> OK
    ("Catherine White", 1860, 1905, 40),    # 1865 implied - 5 year gap -> INVESTIGATE
    ("Charles Jackson", 1843, 1878, 35),    # 1843 implied - 0 year gap -> OK
    ("Emma Thompson", 1856, 1898, 43),      # 1855 implied - 1 year gap -> OK
    ("Henry Martin", 1849, 1889, 35),       # 1854 implied - 5 year gap -> INVESTIGATE
    ("Hannah Lee", 1864, 1902, 38),         # 1864 implied - 0 year gap -> OK
    ("George Harris", 1851, 1886, 38),      # 1848 implied - 3 year gap -> INVESTIGATE
    ("Annie Clark", 1867, 1910, 42),        # 1868 implied - 1 year gap -> OK
    ("Albert Lewis", 1854, 1894, 39),       # 1855 implied - 1 year gap -> OK
    ("Clara Walker", 1861, 1901, 35),       # 1866 implied - 5 year gap -> INVESTIGATE
]

# Add data rows
for name, birth_year, record_date, recorded_age in genealogy_data:
    row = TableRow()
    
    # Name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=name))
    row.addElement(cell)
    
    # Known Birth Year (number)
    cell = TableCell(valuetype="float", value=str(birth_year))
    cell.addElement(P(text=str(birth_year)))
    row.addElement(cell)
    
    # Record Date (number)
    cell = TableCell(valuetype="float", value=str(record_date))
    cell.addElement(P(text=str(record_date)))
    row.addElement(cell)
    
    # Recorded Age (number)
    cell = TableCell(valuetype="float", value=str(recorded_age))
    cell.addElement(P(text=str(recorded_age)))
    row.addElement(cell)
    
    # Implied Birth Year (empty - agent fills this)
    cell = TableCell()
    row.addElement(cell)
    
    # Flag Inconsistency (empty - agent fills this)
    cell = TableCell()
    row.addElement(cell)
    
    table.addElement(row)

# Add empty rows for proper spreadsheet format
for _ in range(5):
    row = TableRow()
    for _ in range(len(header_data)):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
output_path = "/home/ga/Documents/genealogy_analysis.ods"
doc.save(output_path)
print(f"Created genealogy data spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/genealogy_analysis.ods
sudo chmod 666 /home/ga/Documents/genealogy_analysis.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/genealogy_analysis.ods > /tmp/calc_genealogy_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_genealogy_task.log
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Move cursor to cell E2 (first data cell in Implied Birth Year column)
echo "Positioning cursor at cell E2..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Genealogy Age Validator Task Setup Complete ==="
echo "📋 Task Overview:"
echo "  - 17 genealogy records with known birth years and census data"
echo "  - Column E (Implied Birth Year): Enter formula =C2-D2, then copy down"
echo "  - Column F (Flag Inconsistency): Enter formula =IF(ABS(B2-E2)>2,\"INVESTIGATE\",\"OK\"), then copy down"
echo ""
echo "💡 Expected Results:"
echo "  - Some records will show 'INVESTIGATE' (discrepancy >2 years)"
echo "  - Some records will show 'OK' (discrepancy ≤2 years)"
echo ""
echo "🎯 Current Position: Cell E2 (ready for first formula)"