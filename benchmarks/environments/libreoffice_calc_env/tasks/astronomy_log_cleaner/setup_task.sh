#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Astronomy Observation Log Cleaner Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not already installed
apt-get update > /dev/null 2>&1 && apt-get install -y python3-odf > /dev/null 2>&1 || true

# Create the observation log ODS file with messy data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== Sheet 1: Observations (with messy data) =====
observations_table = Table(name="Observations")

# Header row
header_row = TableRow()
headers = ["Object Name", "Messier #", "Observation Time", "Observer 1", "Observer 2", "Observer 3", "Avg Quality", "Best for Beginners?"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
observations_table.addElement(header_row)

# Data rows (with intentional messiness)
# Format: [Object, Messier#, Time (mixed formats), Obs1, Obs2, Obs3, AvgQuality(empty), Beginner(empty)]
observation_data = [
    ["Andromeda Galaxy", "M31", "9:45 PM", "5", "5", "4", "", ""],
    ["Orion Nebula", "", "21:30", "5", "5", "5", "", ""],
    ["Pleiades", "M45", "10:15 PM", "4", "3", "4", "", ""],
    ["Ring Nebula", "", "22:45", "3", "4", "", "", ""],
    ["Triangulum Galaxy", "M33", "8:30 PM", "2", "3", "2", "", ""],
    ["Hercules Cluster", "", "23:15", "4", "5", "4", "", ""],
    ["Dumbbell Nebula", "M27", "9:00 PM", "3", "3", "", "", ""],
    ["Lagoon Nebula", "", "10:45 PM", "5", "4", "5", "", ""],
]

for data_row in observation_data:
    row = TableRow()
    for i, value in enumerate(data_row):
        cell = TableCell()
        # Columns D, E, F (indices 3, 4, 5) are numeric ratings
        if i in [3, 4, 5] and value:
            cell.setAttribute('valuetype', 'float')
            cell.setAttribute('value', value)
            cell.addElement(P(text=value))
        elif value:
            cell.setAttribute('valuetype', 'string')
            cell.addElement(P(text=value))
        # Empty cells remain empty
        row.addElement(cell)
    observations_table.addElement(row)

# Add empty rows for spacing
for _ in range(2):
    empty_row = TableRow()
    for _ in range(8):
        empty_row.addElement(TableCell())
    observations_table.addElement(empty_row)

# Row for summary statistic (row 12, which is index 11 after header)
summary_row = TableRow()
summary_label_cell = TableCell(valuetype="string")
summary_label_cell.addElement(P(text="Total Messier Objects Observed:"))
summary_row.addElement(summary_label_cell)

# Cell B for the count formula (to be filled by user)
summary_value_cell = TableCell()
summary_row.addElement(summary_value_cell)

for _ in range(6):  # Fill remaining columns
    summary_row.addElement(TableCell())
observations_table.addElement(summary_row)

doc.spreadsheet.addElement(observations_table)

# ===== Sheet 2: Messier_Reference =====
reference_table = Table(name="Messier_Reference")

# Header row
ref_header_row = TableRow()
ref_headers = ["Object Name", "Messier Number"]
for header_text in ref_headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    ref_header_row.addElement(cell)
reference_table.addElement(ref_header_row)

# Reference data
reference_data = [
    ["Andromeda Galaxy", "M31"],
    ["Orion Nebula", "M42"],
    ["Pleiades", "M45"],
    ["Ring Nebula", "M57"],
    ["Triangulum Galaxy", "M33"],
    ["Hercules Cluster", "M13"],
    ["Dumbbell Nebula", "M27"],
    ["Lagoon Nebula", "M8"],
]

for ref_row_data in reference_data:
    row = TableRow()
    for value in ref_row_data:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=value))
        row.addElement(cell)
    reference_table.addElement(row)

doc.spreadsheet.addElement(reference_table)

# Save the file
doc.save("/home/ga/Documents/star_party_observations.ods")
print("✅ Created star_party_observations.ods with messy data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/star_party_observations.ods
sudo chmod 666 /home/ga/Documents/star_party_observations.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/star_party_observations.ods > /tmp/calc_astronomy_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_astronomy_task.log || true
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

# Ensure we're on the Observations sheet (should be active by default)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Astronomy Observation Log Cleaner Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Standardize time formats in Column C (24-hour format)"
echo "  2. Fill missing Messier numbers in Column B using VLOOKUP from 'Messier_Reference' sheet"
echo "  3. Calculate average quality in Column G using AVERAGE(D:F)"
echo "  4. Mark beginner-friendly objects in Column H (IF formula, quality >= 4.0)"
echo "  5. Sort data by Column G (Average Quality) in descending order"
echo "  6. In cell B12, add COUNTIF formula to count total Messier objects"