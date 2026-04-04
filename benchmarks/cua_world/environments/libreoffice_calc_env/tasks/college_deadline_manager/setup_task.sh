#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up College Deadline Manager Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy college application spreadsheet with inconsistent date formats
# We'll create this as an ODS file with proper structure
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties
from odf.number import DateStyle, Day, Month, Year, Text as NumText

import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Applications")
doc.spreadsheet.addElement(table)

# Create header row
header_row = TableRow()
headers = ["School Name", "Application Type", "Deadline", "Essay Required"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Add data rows with INTENTIONALLY MESSY date formats (stored as text strings)
# This simulates real-world inconsistent data entry
data_rows = [
    ["State University", "Regular Decision", "02/01/2025", "Yes"],
    ["Tech Institute", "Early Action", "November 1", "Yes"],
    ["Liberal Arts College", "Regular Decision", "1-15-2025", "No"],
    ["Community College", "Rolling", "12/15/24", "No"],
    ["Private University", "Early Decision", "11/15/2024", "Yes"],
    ["Regional University", "Regular Decision", "2025-01-01", "Yes"],
]

for data in data_rows:
    row = TableRow()
    for value in data:
        cell = TableCell(valuetype="string")  # Store everything as STRING initially
        cell.addElement(P(text=value))
        row.addElement(cell)
    table.addElement(row)

# Add some empty rows
for _ in range(15):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/college_deadlines.ods"
doc.save(output_path)
print(f"✅ Created messy deadline spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/college_deadlines.ods
sudo chmod 666 /home/ga/Documents/college_deadlines.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/college_deadlines.ods > /tmp/calc_deadline_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_deadline_task.log || true
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

# Position cursor at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== College Deadline Manager Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You're helping your high school senior organize college applications."
echo "   The deadline data was entered inconsistently over several months."
echo ""
echo "📝 YOUR TASKS:"
echo "   1. Standardize all dates in column C to proper date format"
echo "   2. Insert a new column 'Days Until Deadline' (after column C)"
echo "   3. Add formulas to calculate days remaining: =Deadline-TODAY()"
echo "   4. Sort entire dataset by urgency (earliest deadline first)"
echo "   5. Apply conditional formatting to highlight deadlines ≤14 days"
echo ""
echo "⚠️  IMPORTANT: These are real college deadlines - missing them has consequences!"
echo ""