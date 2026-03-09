#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mileage Deduction Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for ODS file creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create mileage log ODS file with trip data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Mileage Log")

# Header row
header_row = TableRow()
headers = ["Date", "From", "To", "Purpose", "Miles", "Rate", "Deduction"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Trip data (6 trips)
trips = [
    ["2024-01-05", "Home Office", "Client Site A", "Client Meeting", 45, 0.655],
    ["2024-01-12", "Home Office", "Downtown Office", "Project Review", 28, 0.655],
    ["2024-01-18", "Home Office", "Conference Center", "Industry Conference", 67, 0.655],
    ["2024-01-25", "Home Office", "Client Site B", "Consultation", 52, 0.655],
    ["2024-02-02", "Home Office", "Training Facility", "Professional Development", 38, 0.655],
    ["2024-02-09", "Home Office", "Client Site A", "Follow-up Meeting", 45, 0.655],
]

# Add trip rows
for trip in trips:
    row = TableRow()
    
    # Date (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=trip[0]))
    row.addElement(cell)
    
    # From (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=trip[1]))
    row.addElement(cell)
    
    # To (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=trip[2]))
    row.addElement(cell)
    
    # Purpose (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=trip[3]))
    row.addElement(cell)
    
    # Miles (float)
    cell = TableCell(valuetype="float", value=str(trip[4]))
    cell.addElement(P(text=str(trip[4])))
    row.addElement(cell)
    
    # Rate (float)
    cell = TableCell(valuetype="float", value=str(trip[5]))
    cell.addElement(P(text=str(trip[5])))
    row.addElement(cell)
    
    # Deduction (empty - agent must add formula)
    cell = TableCell()
    row.addElement(cell)
    
    table.addElement(row)

# Add TOTAL row
total_row = TableRow()

# Label
cell = TableCell(valuetype="string")
cell.addElement(P(text="TOTAL"))
total_row.addElement(cell)

# Empty cells for From, To, Purpose
for _ in range(3):
    cell = TableCell()
    total_row.addElement(cell)

# Total Miles (empty - agent must add SUM formula)
cell = TableCell()
total_row.addElement(cell)

# Empty Rate cell
cell = TableCell()
total_row.addElement(cell)

# Total Deduction (empty - agent must add SUM formula)
cell = TableCell()
total_row.addElement(cell)

table.addElement(total_row)

# Add some empty rows for better visibility
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/mileage_log.ods")
print("Created mileage log ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/mileage_log.ods
sudo chmod 666 /home/ga/Documents/mileage_log.ods

# Verify file was created
if [ -f "/home/ga/Documents/mileage_log.ods" ]; then
    echo "✅ Mileage log file created: $(ls -lh /home/ga/Documents/mileage_log.ods)"
else
    echo "❌ ERROR: Failed to create mileage log file"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/mileage_log.ods > /tmp/calc_mileage_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_mileage_task.log || true
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

# Position cursor at G2 (first Deduction cell)
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column G (Deduction)
safe_xdotool ga :1 key Right Right Right Right Right Right
sleep 0.2
# Move to row 2 (first data row)
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Mileage Deduction Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add formulas in column G (Deduction) to calculate: Miles × Rate"
echo "     Example: In G2, enter =E2*F2"
echo "  2. Copy formula down to all trip rows (G2:G7)"
echo "  3. In TOTAL row (row 8), add SUM formula for Miles (column E)"
echo "     Example: In E8, enter =SUM(E2:E7)"
echo "  4. In TOTAL row (row 8), add SUM formula for Deduction (column G)"
echo "     Example: In G8, enter =SUM(G2:G7)"
echo "  5. Verify all calculations are correct"
echo ""
echo "💡 Tip: Use Ctrl+C and Ctrl+V to copy formulas efficiently"