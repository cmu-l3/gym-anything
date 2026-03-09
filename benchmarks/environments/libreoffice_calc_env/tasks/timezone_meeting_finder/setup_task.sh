#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Timezone Meeting Finder Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create ODS file with team availability data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, ParagraphProperties, TableColumnProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Schedule"
table = Table(name="Schedule")

# Create header row
header_row = TableRow()
headers = ["Name", "Location", "Timezone", "UTC Offset", "Local Start", "Local End", "UTC Start", "UTC End"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Team member data
team_data = [
    ["Alex", "New York", "EST", -5, "09:00", "17:00"],
    ["Priya", "London", "GMT", 0, "08:00", "16:00"],
    ["Kenji", "Tokyo", "JST", 9, "10:00", "18:00"],
    ["Sophie", "Sydney", "AEDT", 11, "09:00", "17:00"],
    ["Carlos", "Los Angeles", "PST", -8, "10:00", "18:00"]
]

# Add data rows
for person_data in team_data:
    row = TableRow()
    
    # Name, Location, Timezone (strings)
    for i in range(3):
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(person_data[i])))
        row.addElement(cell)
    
    # UTC Offset (number)
    cell = TableCell(valuetype="float", value=str(person_data[3]))
    cell.addElement(P(text=str(person_data[3])))
    row.addElement(cell)
    
    # Local Start, Local End (strings for simplicity)
    for i in range(4, 6):
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=person_data[i]))
        row.addElement(cell)
    
    # UTC Start and UTC End (empty cells for formulas)
    for _ in range(2):
        cell = TableCell()
        row.addElement(cell)
    
    table.addElement(row)

# Add some empty rows
for _ in range(3):
    row = TableRow()
    for _ in range(8):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Add instructions section
instr_row = TableRow()
cell = TableCell(valuetype="string")
cell.addElement(P(text="Instructions:"))
instr_row.addElement(cell)
for _ in range(7):
    instr_row.addElement(TableCell())
table.addElement(instr_row)

instructions = [
    "1. Create formulas in columns G (UTC Start) and H (UTC End) to convert local times to UTC",
    "2. Use the UTC Offset (column D) to calculate UTC times from local times",
    "3. Remember: UTC = Local Time - UTC Offset (e.g., NYC 9AM with offset -5 → 9-(-5) = 14:00 UTC)",
    "4. Below, create an overlap analysis to find 2-hour windows where all 5 people are available",
    "5. Document your recommended meeting time in UTC format"
]

for instr_text in instructions:
    row = TableRow()
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=instr_text))
    row.addElement(cell)
    for _ in range(7):
        row.addElement(TableCell())
    table.addElement(row)

# Add more empty rows for overlap analysis
for _ in range(10):
    row = TableRow()
    for _ in range(8):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
output_path = "/home/ga/Documents/meeting_schedule.ods"
doc.save(output_path)
print(f"Created spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/meeting_schedule.ods
sudo chmod 666 /home/ga/Documents/meeting_schedule.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/meeting_schedule.ods > /tmp/calc_timezone_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_timezone_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at cell G2 (first UTC Start cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Timezone Meeting Finder Task Setup Complete ==="
echo ""
echo "📋 Task: Find a 2-hour meeting window that works for all 5 team members"
echo ""
echo "👥 Team Availability (Local Times):"
echo "  • Alex (NYC, UTC-5): 9:00-17:00"
echo "  • Priya (London, UTC+0): 8:00-16:00"
echo "  • Kenji (Tokyo, UTC+9): 10:00-18:00"
echo "  • Sophie (Sydney, UTC+11): 9:00-17:00"
echo "  • Carlos (LA, UTC-8): 10:00-18:00"
echo ""
echo "💡 Steps:"
echo "  1. Fill in columns G & H with UTC conversion formulas"
echo "  2. Create overlap analysis below the data"
echo "  3. Identify a 2-hour window where everyone is available"
echo ""
echo "🎯 Goal: Coordinate a meeting time using timezone math!"