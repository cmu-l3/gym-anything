#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Theater Conflict Detector Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for ODS file creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || true
fi

# Generate theater schedule with known conflicts using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ============= Sheet 1: Rehearsal_Schedule =============
rehearsal_sheet = Table(name="Rehearsal_Schedule")

# Header row
header_row = TableRow()
headers = ["Rehearsal_ID", "Date", "Time", "Scene", "Assigned_Actor"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
rehearsal_sheet.addElement(header_row)

# Rehearsal data (10 rehearsals over 7 days in June 2024)
rehearsals = [
    ("R001", "2024-06-03", "19:00", "Act1_Scene1", "Alice"),
    ("R002", "2024-06-03", "20:30", "Act1_Scene2", "Bob"),
    ("R003", "2024-06-04", "19:00", "Act2_Scene1", "Alice"),  # CONFLICT: Alice unavailable
    ("R004", "2024-06-04", "20:30", "Act1_Scene3", "Charlie"),
    ("R005", "2024-06-05", "19:00", "Act2_Scene2", "Diana"),  # CONFLICT: Diana unavailable
    ("R006", "2024-06-05", "20:30", "Act1_Scene1", "Bob"),
    ("R007", "2024-06-06", "19:00", "Act3_Scene1", "Alice"),
    ("R008", "2024-06-07", "19:00", "Act2_Scene3", "Bob"),  # CONFLICT: Bob unavailable
    ("R009", "2024-06-07", "20:30", "Act3_Scene2", "Charlie"),  # CONFLICT: Charlie unavailable
    ("R010", "2024-06-08", "19:00", "Act1_Scene2", "Diana"),
]

for reh in rehearsals:
    row = TableRow()
    for value in reh:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    rehearsal_sheet.addElement(row)

doc.spreadsheet.addElement(rehearsal_sheet)

# ============= Sheet 2: Actor_Availability =============
availability_sheet = Table(name="Actor_Availability")

# Header row
header_row = TableRow()
headers = ["Actor_Name", "Unavailable_Date", "Reason"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
availability_sheet.addElement(header_row)

# Unavailability data (creates conflicts with R003, R005, R008, R009)
unavailability = [
    ("Alice", "2024-06-04", "Work conflict"),
    ("Diana", "2024-06-05", "Family emergency"),
    ("Bob", "2024-06-07", "Medical appointment"),
    ("Charlie", "2024-06-07", "Out of town"),
    ("Alice", "2024-06-09", "Vacation"),
]

for avail in unavailability:
    row = TableRow()
    for value in avail:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    availability_sheet.addElement(row)

doc.spreadsheet.addElement(availability_sheet)

# ============= Sheet 3: Scene_Requirements (Optional Reference) =============
scene_sheet = Table(name="Scene_Requirements")

# Header row
header_row = TableRow()
headers = ["Scene_Name", "Required_Actors", "Duration_Min"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
scene_sheet.addElement(header_row)

# Scene data
scenes = [
    ("Act1_Scene1", "Alice, Bob", "60"),
    ("Act1_Scene2", "Bob, Diana", "45"),
    ("Act1_Scene3", "Charlie, Bob", "50"),
    ("Act2_Scene1", "Alice, Charlie", "55"),
    ("Act2_Scene2", "Diana, Alice", "40"),
    ("Act2_Scene3", "Bob, Charlie", "50"),
    ("Act3_Scene1", "Alice, Diana", "60"),
    ("Act3_Scene2", "Charlie, Bob", "45"),
]

for scene in scenes:
    row = TableRow()
    for value in scene:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    scene_sheet.addElement(row)

doc.spreadsheet.addElement(scene_sheet)

# Save the file
output_path = "/home/ga/Documents/theater_schedule.ods"
doc.save(output_path)
print(f"Created theater schedule: {output_path}")
print("Ground truth conflicts: R003, R005, R008, R009")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/theater_schedule.ods
sudo chmod 666 /home/ga/Documents/theater_schedule.ods

# Save ground truth conflicts to a file for verifier
echo "R003,R005,R008,R009" > /home/ga/Documents/.theater_ground_truth.txt
sudo chown ga:ga /home/ga/Documents/.theater_ground_truth.txt

echo "✅ Theater schedule created with 4 known conflicts"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/theater_schedule.ods > /tmp/calc_theater_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_theater_task.log || true
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

# Ensure we're on the Rehearsal_Schedule sheet (first sheet)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Theater Conflict Detector Task Setup Complete ==="
echo "📋 Task: Detect scheduling conflicts in rehearsal schedule"
echo "📊 Sheets: Rehearsal_Schedule, Actor_Availability, Scene_Requirements"
echo "🎯 Goal: Add conflict detection column using formulas"
echo "💡 Hint: Use COUNTIFS to cross-reference Actor_Availability sheet"
echo ""
echo "Expected conflicts: 4 rehearsals have actors unavailable on scheduled dates"