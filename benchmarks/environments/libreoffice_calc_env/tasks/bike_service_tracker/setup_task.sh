#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Bike Service Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the spreadsheet with ride log, service intervals, and tracker structure
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Bike Maintenance"
table = Table(name="Bike Maintenance")
doc.spreadsheet.addElement(table)

def create_cell(value=None, value_type='string'):
    """Helper to create a cell with a value"""
    cell = TableCell()
    if value is not None:
        if value_type == 'float':
            cell.setAttrNS('urn:oasis:names:tc:opendocument:xmlns:office:1.0', 'value-type', 'float')
            cell.setAttrNS('urn:oasis:names:tc:opendocument:xmlns:office:1.0', 'value', str(value))
        p = P()
        p.addText(str(value))
        cell.addElement(p)
    return cell

# Row 1: Headers for Ride Log and Service Intervals
row1 = TableRow()
row1.addElement(create_cell("Ride Date"))
row1.addElement(create_cell("Distance (km)"))
row1.addElement(create_cell())  # Empty column C
row1.addElement(create_cell("Component"))
row1.addElement(create_cell("Service Interval (km)"))
row1.addElement(create_cell())  # Empty column F
row1.addElement(create_cell("SERVICE TRACKER"))
row1.addElement(create_cell())
row1.addElement(create_cell())
table.addElement(row1)

# Row 2: First ride + Service interval header + Total Mileage label
row2 = TableRow()
row2.addElement(create_cell("2024-01-05"))
row2.addElement(create_cell(45, 'float'))
row2.addElement(create_cell())
row2.addElement(create_cell())
row2.addElement(create_cell())
row2.addElement(create_cell())
row2.addElement(create_cell("Total Mileage:"))
row2.addElement(create_cell())  # H2 - Agent enters SUM formula here
row2.addElement(create_cell())
table.addElement(row2)

# Rows 3-11: Ride data (9 more rides)
rides = [
    ("2024-01-08", 32),
    ("2024-01-12", 50),
    ("2024-01-15", 28),
    ("2024-01-19", 35),
    ("2024-01-22", 48),
    ("2024-01-26", 30),
    ("2024-01-29", 42),
    ("2024-02-02", 38),
    ("2024-02-05", 37),
]

for i, (date, distance) in enumerate(rides):
    row = TableRow()
    row.addElement(create_cell(date))
    row.addElement(create_cell(distance, 'float'))
    
    # Add service interval data in rows 3-6 (indices 0-3 of rides list)
    if i == 0:  # Row 3 - empty spacer
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
    elif i == 1:  # Row 4 - Headers for Service Tracker
        row.addElement(create_cell())
        row.addElement(create_cell("Chain"))
        row.addElement(create_cell(500, 'float'))
        row.addElement(create_cell())
        row.addElement(create_cell("Component"))
        row.addElement(create_cell("Interval"))
        row.addElement(create_cell("Miles Remaining"))
    elif i == 2:  # Row 5
        row.addElement(create_cell())
        row.addElement(create_cell("Tires"))
        row.addElement(create_cell(3000, 'float'))
        row.addElement(create_cell())
        row.addElement(create_cell("Chain"))
        row.addElement(create_cell())  # H5 - Agent enters formula
        row.addElement(create_cell())  # I5 - Agent enters formula
    elif i == 3:  # Row 6
        row.addElement(create_cell())
        row.addElement(create_cell("Brake Pads"))
        row.addElement(create_cell(2000, 'float'))
        row.addElement(create_cell())
        row.addElement(create_cell("Tires"))
        row.addElement(create_cell())  # H6 - Agent enters formula
        row.addElement(create_cell())  # I6 - Agent enters formula
    elif i == 4:  # Row 7
        row.addElement(create_cell())
        row.addElement(create_cell("Full Tune-up"))
        row.addElement(create_cell(5000, 'float'))
        row.addElement(create_cell())
        row.addElement(create_cell("Brake Pads"))
        row.addElement(create_cell())  # H7 - Agent enters formula
        row.addElement(create_cell())  # I7 - Agent enters formula
    elif i == 5:  # Row 8
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell("Full Tune-up"))
        row.addElement(create_cell())  # H8 - Agent enters formula
        row.addElement(create_cell())  # I8 - Agent enters formula
    else:
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
        row.addElement(create_cell())
    
    table.addElement(row)

# Add some empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        row.addElement(create_cell())
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/bike_service_tracker.ods")
print("Created bike service tracker ODS file successfully")
print("Total expected mileage: 45+32+50+28+35+48+30+42+38+37 = 385 km")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/bike_service_tracker.ods
sudo chmod 666 /home/ga/Documents/bike_service_tracker.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/bike_service_tracker.ods > /tmp/calc_bike_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_bike_task.log || true
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

# Move cursor to starting position (H2 - where total mileage formula goes)
echo "Positioning cursor at H2..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.2
safe_xdotool ga :1 key --delay 100 Right Right Right Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.3

echo "=== Bike Service Tracker Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "   Alex missed a chain service interval and paid $300 for repairs"
echo "   instead of $25 for timely maintenance. Help create an automated"
echo "   tracking system!"
echo ""
echo "📝 YOUR TASK:"
echo "   1. Calculate total mileage in cell H2 using SUM function"
echo "   2. Reference service intervals in cells H5:H8 from column E"
echo "   3. Calculate miles remaining in cells I5:I8 (interval - total)"
echo ""
echo "💡 HINTS:"
echo "   - Total mileage: =SUM(B2:B11)"
echo "   - Service interval: =E5 (for Chain in H5)"
echo "   - Miles remaining: =H5-\$H\$2 (use absolute reference for total)"
echo "   - Copy the formula down for other components"
echo ""
echo "✅ EXPECTED RESULTS:"
echo "   - Total mileage: ~385 km"
echo "   - Chain remaining: ~115 km"
echo "   - Tires remaining: ~2615 km"