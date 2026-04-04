#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Pet Vaccination Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with partial vaccination data (Next Due Date and Status columns empty)
cat > /home/ga/Documents/pet_vaccines.csv << 'EOF'
Pet Name,Vaccine Type,Last Vaccination,Interval (years),Next Due Date,Status
Max,Rabies,2021-03-15,3,,
Max,DHPP,2023-03-15,3,,
Max,Bordetella,2024-01-10,1,,
Bella,Rabies,2021-06-20,3,,
Bella,DHPP,2023-06-20,3,,
Bella,Bordetella,2023-08-15,1,,
Whiskers,Rabies,2021-09-10,3,,
Whiskers,FVRCP,2022-09-10,3,,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/pet_vaccines.csv
sudo chmod 666 /home/ga/Documents/pet_vaccines.csv

echo "✅ Created pet_vaccines.csv with vaccination data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with vaccination tracker..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/pet_vaccines.csv > /tmp/calc_vaccine_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_vaccine_task.log || true
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

# Position cursor at E2 (first Next Due Date cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Pet Vaccination Tracker Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. In column E (Next Due Date), add formulas to calculate due dates"
echo "     - Formula example: =C2+(D2*365) or =DATE(YEAR(C2)+D2,MONTH(C2),DAY(C2))"
echo "  2. Copy the formula down to all rows (E2:E9)"
echo "  3. In column F (Status), add IF formulas to check if overdue"
echo "     - Formula example: =IF(E2<TODAY(),\"OVERDUE\",\"Current\")"
echo "  4. Copy the status formula down to all rows (F2:F9)"
echo "  5. Apply conditional formatting to Status column (F2:F9)"
echo "     - Format → Conditional Formatting → Condition"
echo "     - Condition: Cell value equals \"OVERDUE\""
echo "     - Format: Red background color"
echo ""
echo "💡 Context: Alex needs to identify which pet vaccines are overdue before boarding"