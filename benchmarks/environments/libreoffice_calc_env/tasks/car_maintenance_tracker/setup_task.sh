#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Car Maintenance Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create maintenance log CSV with incomplete data
cat > /home/ga/Documents/car_maintenance_log.csv << 'CSVEOF'
Current Mileage:,47500,,,,
,,,,,,
Date,Service Type,Mileage at Service,Cost,Next Service Due At,Miles Until Next Service
2022-03-15,Oil Change,25000,45,,
2022-06-20,Tire Rotation,27500,30,,
2022-09-10,Oil Change,30000,45,,
2022-11-05,Brake Inspection,32000,120,,
2023-02-14,Oil Change,,45,,
2023-05-30,Tire Rotation,40000,35,,
2023-08-22,Oil Change,42500,50,,
2023-11-15,Air Filter,45000,25,,
2024-01-10,Oil Change,47000,50,,
2024-02-25,Tire Rotation,47500,35,,
,,,,,,
Total Cost:,,,,,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/car_maintenance_log.csv
sudo chmod 666 /home/ga/Documents/car_maintenance_log.csv

echo "✅ Created car_maintenance_log.csv with incomplete data"

# Convert CSV to ODS for better formula support
echo "Converting CSV to ODS..."
su - ga -c "DISPLAY=:1 libreoffice --headless --convert-to ods --outdir /home/ga/Documents /home/ga/Documents/car_maintenance_log.csv" || true
sleep 2

# Check if ODS was created
if [ -f "/home/ga/Documents/car_maintenance_log.ods" ]; then
    echo "✅ Converted to ODS format"
    sudo chown ga:ga /home/ga/Documents/car_maintenance_log.ods
    sudo chmod 666 /home/ga/Documents/car_maintenance_log.ods
    OPEN_FILE="/home/ga/Documents/car_maintenance_log.ods"
else
    echo "⚠️  ODS conversion failed, will open CSV"
    OPEN_FILE="/home/ga/Documents/car_maintenance_log.csv"
fi

# Launch LibreOffice Calc with the maintenance log
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore '$OPEN_FILE' > /tmp/calc_maintenance_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_maintenance_task.log || true
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

# Position cursor at the first data row
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Car Maintenance Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK CONTEXT:"
echo "   You just bought a used car with 47,500 miles. The previous owner's"
echo "   maintenance log is incomplete. You need to quickly assess which services"
echo "   are overdue to avoid vehicle damage and expensive repairs."
echo ""
echo "📝 YOUR TASKS:"
echo "   1. Fill missing mileage data (row 8: Oil Change around Feb 2023)"
echo "   2. Add formulas in Column E: Next Service Due = Mileage at Service + Interval"
echo "      - Oil Change: every 5,000 miles"
echo "      - Tire Rotation: every 7,500 miles"
echo "      - Brake Inspection: every 15,000 miles"
echo "      - Air Filter: every 20,000 miles"
echo "   3. Add formulas in Column F: Miles Until Next = Column E - Current Mileage (B1)"
echo "   4. Apply conditional formatting to Column F:"
echo "      - RED: Values < 0 (overdue)"
echo "      - YELLOW: Values 0-1000 (due soon)"
echo "      - GREEN: Values > 1000 (not due yet)"
echo "   5. Calculate total cost (cell D13 or similar)"
echo ""
echo "💡 HINTS:"
echo "   - Use IF formulas for different service intervals"
echo "   - Reference cell B1 (current mileage) with absolute reference \$B\$1"
echo "   - Format → Conditional Formatting → Condition..."
echo "   - Negative values in Column F mean the service is OVERDUE!"