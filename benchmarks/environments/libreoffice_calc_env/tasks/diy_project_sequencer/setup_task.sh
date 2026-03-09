#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up DIY Project Sequencer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || true

# Create the bathroom renovation ODS file with task data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create main sheet
table = Table(name="Renovation Tasks")

# Header row
header_row = TableRow()
headers = ["Task Name", "Duration (days)", "Prerequisites", "Proposed Sequence", "Needs Plumber?"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Task data (with intentional sequencing error: Task 8 before Task 7)
tasks = [
    ["Remove old tile", 1.0, "", 1, "No"],
    ["Install cement board", 1.0, "Remove old tile", 2, "No"],
    ["Rough plumbing", 1.0, "Remove old tile", 3, "Yes"],
    ["Waterproof shower walls", 0.5, "Install cement board", 4, "No"],
    ["Install tile", 2.0, "Waterproof shower walls", 5, "No"],
    ["Grout tile", 1.0, "Install tile", 6, "No"],
    ["Install ventilation fan", 0.5, "Rough plumbing", 8, "Yes"],  # Sequence 8
    ["Paint walls", 1.0, "Install ventilation fan", 7, "No"],  # Sequence 7 - VIOLATION!
    ["Install fixtures", 1.0, "Paint walls;Grout tile", 9, "Yes"],
    ["Install vanity", 0.5, "Install fixtures", 10, "No"],
    ["Install toilet", 0.5, "Install fixtures", 11, "Yes"],
    ["Final caulking", 0.5, "Install vanity;Install toilet", 12, "No"],
]

# Add data rows
for task_data in tasks:
    row = TableRow()
    
    # Task name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(task_data[0])))
    row.addElement(cell)
    
    # Duration (float)
    cell = TableCell(valuetype="float", value=str(task_data[1]))
    cell.addElement(P(text=str(task_data[1])))
    row.addElement(cell)
    
    # Prerequisites (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(task_data[2])))
    row.addElement(cell)
    
    # Sequence (integer)
    cell = TableCell(valuetype="float", value=str(task_data[3]))
    cell.addElement(P(text=str(task_data[3])))
    row.addElement(cell)
    
    # Needs Plumber (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(task_data[4])))
    row.addElement(cell)
    
    table.addElement(row)

# Add empty rows for summary section
for _ in range(3):
    row = TableRow()
    for _ in range(8):  # Extend to H column
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save file
doc.save("/home/ga/Documents/bathroom_renovation.ods")
print("✅ Created bathroom_renovation.ods with task data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/bathroom_renovation.ods
sudo chmod 666 /home/ga/Documents/bathroom_renovation.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/bathroom_renovation.ods > /tmp/calc_sequencer.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_sequencer.log || true
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

# Position cursor at F1 (where agent should start adding columns)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column F
safe_xdotool ga :1 key --repeat 5 Right
sleep 0.3

echo "=== DIY Project Sequencer Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  - 12 renovation tasks with dependencies"
echo "  - Task 8 (Paint) is INCORRECTLY scheduled before Task 7 (Ventilation fan)"
echo ""
echo "🎯 Agent must add:"
echo "  1. Column F: Dependency Check (formulas to validate prerequisites)"
echo "  2. Column G: Earliest Start (Day) (calculate based on prerequisite chains)"
echo "  3. Column H: Critical Path? (identify zero-slack tasks)"
echo "  4. Cell A15: Total Project Duration"
echo ""
echo "💡 Hints:"
echo "  - Use IF/AND/OR for dependency checking"
echo "  - Use VLOOKUP to find prerequisite info"
echo "  - Handle semicolon-separated prerequisites"
echo "  - Earliest Start = MAX(prerequisite completion times)"