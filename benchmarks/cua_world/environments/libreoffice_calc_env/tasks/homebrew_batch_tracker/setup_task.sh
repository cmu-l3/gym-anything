#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Homebrew Batch Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for creating ODS files)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
    apt-get update && apt-get install -y python3-odf
fi

# Create ODS file with homebrew batch data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Brewing Log"
table = Table(name="Brewing Log")

# Header row
header_data = [
    "Batch Name",
    "Brew Date", 
    "Original Gravity (OG)",
    "Final Gravity (FG)",
    "Target ABV",
    "ABV",
    "Quality Notes"
]

header_row = TableRow()
for header in header_data:
    cell = TableCell(valuetype="string")
    p = P(text=header)
    cell.addElement(p)
    header_row.addElement(cell)
table.addElement(header_row)

# Batch data
batches = [
    ["Pale Ale #1", "2024-01-15", 1.055, 1.012, "4.5-6.5%", "", "Slightly sweet finish"],
    ["Belgian Wit", "2024-02-03", 1.048, 1.010, "4.5-6.5%", "", "Excellent clarity"],
    ["IPA Experiment", "2024-02-28", 1.062, 1.014, "4.5-6.5%", "", "Good hop character"],
    ["Light Summer Ale", "2024-03-10", 1.045, 1.008, "4.5-6.5%", "", "Very dry, crisp"],
    ["Amber Ale", "2024-03-22", 1.058, 1.015, "4.5-6.5%", "", "Balanced malt profile"],
    ["Stout Attempt", "2024-04-05", 1.070, None, "4.5-6.5%", "", "Still fermenting"]
]

for batch in batches:
    row = TableRow()
    for i, value in enumerate(batch):
        if value is None:
            # Empty cell for missing FG
            cell = TableCell()
        elif isinstance(value, float):
            # Numeric cell for gravity readings
            cell = TableCell(valuetype="float", value=str(value))
            p = P(text=str(value))
            cell.addElement(p)
        elif isinstance(value, str) and value == "":
            # Empty cell for ABV (to be filled by agent)
            cell = TableCell()
        else:
            # String cell
            cell = TableCell(valuetype="string")
            p = P(text=str(value))
            cell.addElement(p)
        row.addElement(cell)
    table.addElement(row)

# Add a few more empty rows for good measure
for _ in range(5):
    row = TableRow()
    for _ in range(7):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/homebrew_tracker.ods")
print("Created homebrew_tracker.ods with batch data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/homebrew_tracker.ods
sudo chmod 666 /home/ga/Documents/homebrew_tracker.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/homebrew_tracker.ods > /tmp/calc_homebrew_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_homebrew_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Move cursor to ABV column (F2) to give visual hint
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Navigate to F2 (first ABV cell)
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Homebrew Batch Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Calculate ABV using formula: =(C2-D2)*131.25 in cell F2"
echo "  2. Copy the formula down to other batches (F3:F7)"
echo "  3. Apply conditional formatting to ABV column (F2:F7)"
echo "  4. Highlight cells where value is between 4.5 and 6.5"
echo "  5. Note: Batch 6 has missing FG data (will show error - this is expected)"
echo ""
echo "💡 ABV Formula: (Original Gravity - Final Gravity) × 131.25"
echo "🎯 Target range: 4.5% to 6.5%"