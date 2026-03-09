#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Baby Feeding Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (for ODS creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create ODS template with partial data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, TimeStyle, Hours, Minutes, AmPm

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a time style for time-of-day format (e.g., "2:30 AM")
time_style = TimeStyle(name="TimeFormat1")
time_style.addElement(Hours(style="long"))
time_style.addElement(NumberText(text=":"))
time_style.addElement(Minutes(style="long"))
time_style.addElement(NumberText(text=" "))
time_style.addElement(AmPm())
doc.automaticstyles.addElement(time_style)

# Create a time style for duration format (e.g., "2:30" for 2.5 hours)
duration_style = TimeStyle(name="DurationFormat1")
duration_style.addElement(Hours(style="long"))
duration_style.addElement(NumberText(text=":"))
duration_style.addElement(Minutes(style="long"))
doc.automaticstyles.addElement(duration_style)

# Add a sheet named "Feeding Tracker"
table = Table(name="Feeding Tracker")
doc.spreadsheet.addElement(table)

# Helper function to create text cell
def create_text_cell(value):
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(value)))
    return cell

# Helper function to create time cell
def create_time_cell(time_str):
    """Create cell with time value in format HH:MM AM/PM"""
    cell = TableCell(valuetype="time", timevalue=time_str)
    cell.addElement(P(text=time_str))
    return cell

# Helper function to create empty cell
def create_empty_cell():
    return TableCell()

# Header row
header_row = TableRow()
headers = ["Date", "Start Time", "End Time", "Event Type", "Duration", "Interval Since Last Feed"]
for header in headers:
    header_row.addElement(create_text_cell(header))
table.addElement(header_row)

# Sample data rows (10 entries over 2 days)
data_entries = [
    ("2024-01-15", "2:30 AM", "2:50 AM", "Feed"),
    ("2024-01-15", "3:00 AM", "5:30 AM", "Sleep"),
    ("2024-01-15", "5:45 AM", "6:05 AM", "Feed"),
    ("2024-01-15", "6:15 AM", "8:00 AM", "Sleep"),
    ("2024-01-15", "8:15 AM", "8:35 AM", "Feed"),
    ("2024-01-15", "8:45 AM", "10:30 AM", "Sleep"),
    ("2024-01-15", "10:45 AM", "11:00 AM", "Feed"),
    ("2024-01-15", "2:15 PM", "2:35 PM", "Feed"),
    ("2024-01-15", "2:45 PM", "4:15 PM", "Sleep"),
    ("2024-01-15", "4:30 PM", "4:50 PM", "Feed"),
    ("2024-01-15", "5:00 PM", "6:45 PM", "Sleep"),
    ("2024-01-15", "7:00 PM", "7:20 PM", "Feed"),
]

for date, start, end, event_type in data_entries:
    row = TableRow()
    row.addElement(create_text_cell(date))
    row.addElement(create_text_cell(start))
    row.addElement(create_text_cell(end))
    row.addElement(create_text_cell(event_type))
    row.addElement(create_empty_cell())  # Duration - to be filled
    row.addElement(create_empty_cell())  # Interval - to be filled
    table.addElement(row)

# Empty row
empty_row = TableRow()
for _ in range(6):
    empty_row.addElement(create_empty_cell())
table.addElement(empty_row)

# Summary section headers
summary_labels = [
    "Shortest Interval Between Feeds:",
    "Longest Sleep Stretch:",
    "Average Time Between Feeds:",
    "",
    "Notes for Doctor:"
]

for label in summary_labels:
    row = TableRow()
    row.addElement(create_text_cell(label))
    for _ in range(5):
        row.addElement(create_empty_cell())
    table.addElement(row)

# Add more empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(6):
        row.addElement(create_empty_cell())
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/baby_feeding_tracker.ods"
doc.save(output_path)
print(f"Created template ODS file: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/baby_feeding_tracker.ods
sudo chmod 666 /home/ga/Documents/baby_feeding_tracker.ods

echo "✅ Created baby feeding tracker template"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/baby_feeding_tracker.ods > /tmp/calc_feeding_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_feeding_task.log || true
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

# Position cursor at cell E2 (Duration column, first data row)
echo "Positioning cursor at Duration column..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.3
safe_xdotool ga :1 key Down
sleep 0.3

echo "=== Baby Feeding Tracker Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You're helping new parents prepare for tomorrow's pediatrician appointment."
echo "             They've tracked feeding/sleep data on paper - it needs to be organized!"
echo ""
echo "📝 Instructions:"
echo "  1. Calculate Duration (Column E): Add formula =D2-C2 (End Time - Start Time)"
echo "  2. Copy duration formula down for all 12 data rows"
echo "  3. Calculate Interval Since Last Feed (Column F): Time between feeds"
echo "     - For Feed events: =C3-D2 (current feed start - previous event end)"
echo "  4. Create Summary Statistics (around row 15-17):"
echo "     - Shortest Interval: =MIN(F:F)"
echo "     - Longest Sleep: =MAXIFS(E:E, D:D, \"Sleep\")"
echo "     - Average Interval: =AVERAGE(F:F)"
echo "  5. Apply Conditional Formatting to Interval column (F):"
echo "     - Format → Conditional Formatting → Condition"
echo "     - Rule: Cell value < 1:30 (flag short intervals)"
echo "     - Format: Red background or text"
echo ""
echo "💡 Why this matters: Pediatricians need to know longest sleep stretch,"
echo "   average feeding interval, and any concerning patterns (too frequent feeds)"