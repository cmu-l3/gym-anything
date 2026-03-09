#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Clothing Swap Credits Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Ensure odfpy is installed
apt-get update && apt-get install -y python3-odf python3-pip > /dev/null 2>&1 || true

# Create pre-populated ODS file with participant data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Swap Event"
table = Table(name="Swap Event")
doc.spreadsheet.addElement(table)

# Participant names (18 total)
participants = [
    "Sarah Martinez",
    "James Chen", 
    "Priya Patel",
    "Michael Anderson",
    "Emily Rodriguez",
    "David Kim",
    "Jessica Taylor",
    "Robert Garcia",
    "Amanda Lee",
    "Christopher Brown",
    "Laura Martinez",
    "Daniel Wilson",
    "Michelle Thompson",
    "Kevin Johnson",
    "Rachel White",
    "Brandon Miller",
    "Nicole Davis",
    "Justin Moore"
]

# Helper to create text cell
def create_text_cell(text):
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(text)))
    return cell

# Helper to create number cell
def create_number_cell(value):
    cell = TableCell(valuetype="float", value=str(value))
    cell.addElement(P(text=str(value)))
    return cell

# Helper to create empty cell
def create_empty_cell():
    cell = TableCell()
    return cell

# Header row
header_row = TableRow()
header_row.addElement(create_text_cell("Participant Name"))
header_row.addElement(create_text_cell("Registered Items"))
header_row.addElement(create_text_cell("Actual Items Brought"))
header_row.addElement(create_text_cell("Items Taken"))
header_row.addElement(create_text_cell("Remaining Credits"))
table.addElement(header_row)

# Data rows
# First 3 participants (Sarah, James, Priya) have NOT checked in yet
# Next 15 have checked in with varying data
for i, name in enumerate(participants):
    row = TableRow()
    
    # Name
    row.addElement(create_text_cell(name))
    
    # Registered items (random 3-10)
    registered = random.randint(3, 10)
    row.addElement(create_number_cell(registered))
    
    # Actual items brought (empty for first 3, filled for others)
    if i < 3:  # Sarah, James, Priya not checked in
        row.addElement(create_empty_cell())
        items_taken = 0  # Haven't taken anything yet
    else:
        # Checked in participants
        actual = random.randint(max(1, registered - 3), registered + 3)
        row.addElement(create_number_cell(actual))
        
        # Items taken (some have taken items, some haven't)
        if random.random() < 0.7:  # 70% have taken items
            # Occasionally make someone take more than they brought (violation)
            if random.random() < 0.15 and actual > 2:  # 15% chance of violation
                items_taken = actual + random.randint(1, 3)
            else:
                items_taken = random.randint(0, actual)
        else:
            items_taken = 0
    
    row.addElement(create_number_cell(items_taken))
    
    # Remaining credits (empty - agent needs to fill with formula)
    row.addElement(create_empty_cell())
    
    table.addElement(row)

# Add a few empty rows for spacing
for _ in range(3):
    row = TableRow()
    for _ in range(5):
        row.addElement(create_empty_cell())
    table.addElement(row)

# Add rows for summary statistics (labels only, agent fills formulas)
summary_labels = [
    "Total Items in Circulation",
    "Total Items Taken",
    "Items Still Available",
    "Participants Over Limit"
]

for label in summary_labels:
    row = TableRow()
    row.addElement(create_text_cell(label))
    row.addElement(create_empty_cell())  # Agent fills formula here
    for _ in range(3):
        row.addElement(create_empty_cell())
    table.addElement(row)

# Add more empty rows to make proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        row.addElement(create_empty_cell())
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/clothing_swap_credits.ods")
print("✅ Created clothing swap spreadsheet with 18 participants")
print("   - First 3 participants (Sarah, James, Priya) not checked in")
print("   - Remaining 15 participants have checked in")
print("   - Some participants have already taken items")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/clothing_swap_credits.ods
sudo chmod 666 /home/ga/Documents/clothing_swap_credits.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/clothing_swap_credits.ods > /tmp/calc_swap_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_swap_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Clothing Swap Credits Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Update check-ins: Sarah Martinez (6), James Chen (3), Priya Patel (8) in Column C"
echo "  2. Create formula in Column E: =IF(ISBLANK(C2),\"Not Checked In\",C2-D2)"
echo "  3. Apply conditional formatting to Column E (negative values → red)"
echo "  4. Sort data by Column E (Remaining Credits) in ascending order"
echo "  5. Add summary statistics with SUM and COUNTIF formulas"