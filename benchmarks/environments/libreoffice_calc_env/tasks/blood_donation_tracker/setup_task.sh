#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Blood Donation Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create pre-populated ODS file with donation log and reference table
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, DateStyle, Day, Month, Year
import datetime

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add date style for cells
date_style = DateStyle(name="date1")
date_style.addElement(Year(style="long"))
date_style.addElement(NumberText(text="-"))
date_style.addElement(Month(style="long"))
date_style.addElement(NumberText(text="-"))
date_style.addElement(Day(style="long"))
doc.styles.addElement(date_style)

# Create Donation Log sheet
donation_log = Table(name="Donation Log")

# Header row
header_row = TableRow()
headers = ["Donation Date", "Donation Type", "Next Eligible Date"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
donation_log.addElement(header_row)

# Sample donation data (past donations with various types)
donations = [
    ("2023-11-15", "Whole Blood"),
    ("2024-01-10", "Platelets"),
    ("2024-01-25", "Platelets"),
    ("2024-02-05", "Plasma"),
    ("2024-02-20", "Whole Blood"),
    ("2024-03-01", "Platelets"),
    ("2024-03-15", "Plasma"),
    ("2024-04-01", "Whole Blood"),
]

for date_str, donation_type in donations:
    row = TableRow()
    
    # Date cell
    date_cell = TableCell(valuetype="date", datevalue=date_str)
    date_cell.addElement(P(text=date_str))
    row.addElement(date_cell)
    
    # Donation type cell
    type_cell = TableCell(valuetype="string")
    type_cell.addElement(P(text=donation_type))
    row.addElement(type_cell)
    
    # Empty cell for formula (to be filled by user)
    formula_cell = TableCell(valuetype="string")
    formula_cell.addElement(P(text=""))
    row.addElement(formula_cell)
    
    donation_log.addElement(row)

# Add empty rows for spacing
for _ in range(2):
    row = TableRow()
    for _ in range(3):
        cell = TableCell()
        row.addElement(cell)
    donation_log.addElement(row)

# Add summary area
summary_label_row = TableRow()
label_cell = TableCell(valuetype="string")
label_cell.addElement(P(text="Next Available Donation Date:"))
summary_label_row.addElement(label_cell)
summary_value_cell = TableCell(valuetype="string")
summary_value_cell.addElement(P(text=""))
summary_label_row.addElement(summary_value_cell)
donation_log.addElement(summary_label_row)

# Add more empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    donation_log.addElement(row)

doc.spreadsheet.addElement(donation_log)

# Create Reference Table sheet
ref_table = Table(name="Reference Table")

# Header row
ref_header_row = TableRow()
ref_headers = ["Donation Type", "Waiting Period (Days)"]
for header_text in ref_headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    ref_header_row.addElement(cell)
ref_table.addElement(ref_header_row)

# Reference data
reference_data = [
    ("Whole Blood", 56),
    ("Platelets", 7),
    ("Plasma", 28),
    ("Double Red Cells", 112),
]

for donation_type, waiting_period in reference_data:
    row = TableRow()
    
    # Type cell
    type_cell = TableCell(valuetype="string")
    type_cell.addElement(P(text=donation_type))
    row.addElement(type_cell)
    
    # Waiting period cell
    period_cell = TableCell(valuetype="float", value=str(waiting_period))
    period_cell.addElement(P(text=str(waiting_period)))
    row.addElement(period_cell)
    
    ref_table.addElement(row)

# Add empty rows
for _ in range(15):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    ref_table.addElement(row)

doc.spreadsheet.addElement(ref_table)

# Save the file
doc.save("/home/ga/Documents/blood_donation_tracker.ods")
print("Created blood donation tracker ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/blood_donation_tracker.ods
sudo chmod 666 /home/ga/Documents/blood_donation_tracker.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/blood_donation_tracker.ods > /tmp/calc_blood_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_blood_task.log || true
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

# Navigate to cell C2 (first cell where formula should be entered)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Blood Donation Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. In cell C2, create a formula to calculate next eligible date"
echo "  2. Use VLOOKUP or INDEX-MATCH to get waiting period from 'Reference Table' sheet"
echo "  3. Add the waiting period to the donation date (A2 + waiting period)"
echo "  4. Copy formula down to all donation records"
echo "  5. In summary area (around row 12), calculate the next available donation date"
echo ""
echo "💡 Hint: =A2+VLOOKUP(B2,'Reference Table'.$A$2:$B$5,2,FALSE)"