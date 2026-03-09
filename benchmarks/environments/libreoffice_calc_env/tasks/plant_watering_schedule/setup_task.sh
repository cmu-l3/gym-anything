#!/bin/bash
# set -euo pipefail

echo "=== Setting up Plant Watering Schedule Task ==="

source /workspace/scripts/task_utils.sh

# Create Documents directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic plant data
# Dates are strategically chosen to create mix of priorities
# Using dates relative to a baseline (mid-January 2024)
cat > /home/ga/Documents/plants_data.csv << 'CSVEOF'
Plant Name,Location,Last Watered,Frequency (days)
Monstera Deliciosa,Living Room,2024-01-15,7
Snake Plant,Bedroom,2024-01-10,14
Pothos,Kitchen,2024-01-18,5
Fiddle Leaf Fig,Office,2024-01-12,7
Spider Plant,Bathroom,2024-01-16,4
Peace Lily,Dining Room,2024-01-14,6
ZZ Plant,Hallway,2024-01-08,21
Rubber Plant,Living Room,2024-01-17,7
Philodendron,Kitchen,2024-01-13,5
Aloe Vera,Windowsill,2024-01-05,10
Jade Plant,Desk,2024-01-01,14
Boston Fern,Bathroom,2024-01-19,3
CSVEOF

chown ga:ga /home/ga/Documents/plants_data.csv
chmod 644 /home/ga/Documents/plants_data.csv
echo "✅ Created plants_data.csv with 12 plants"

# Launch LibreOffice Calc with blank spreadsheet first
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore > /tmp/calc_plant_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_plant_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
fi

sleep 2

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        echo "Window focused successfully"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

echo "=== Plant Watering Schedule Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You're a plant enthusiast who recently forgot to water your fiddle leaf fig."
echo "   It dropped leaves. You need a systematic schedule that updates automatically each day."
echo ""
echo "📝 YOUR TASK:"
echo "  1. Open File → Open and load: /home/ga/Documents/plants_data.csv"
echo "  2. Add column E 'Next Watering Due': formula =C2+D2 (Last Watered + Frequency)"
echo "  3. Add column F 'Days Until': formula =E2-TODAY() (days until watering)"
echo "  4. Add column G 'Priority': use IF formula to categorize:"
echo "     - 'OVERDUE' if Days Until < 0"
echo "     - 'TODAY' if Days Until = 0"
echo "     - 'SOON' if Days Until <= 2"
echo "     - 'OK' otherwise"
echo "  5. Apply conditional formatting to Priority column:"
echo "     - Red background for OVERDUE"
echo "     - Yellow/Orange for TODAY or SOON"
echo "     - Green/White for OK"
echo "  6. Sort entire data by 'Next Watering Due' column (earliest first)"
echo "  7. Save as /home/ga/Documents/plant_schedule.ods"
echo ""
echo "💡 HINTS:"
echo "  - Date arithmetic: adding a number to a date adds that many days"
echo "  - TODAY() function returns current date"
echo "  - Nested IF: =IF(F2<0,\"OVERDUE\",IF(F2=0,\"TODAY\",IF(F2<=2,\"SOON\",\"OK\")))"
echo "  - Format → Conditional Formatting → Condition for color rules"
echo "  - Select all data before sorting: Data → Sort"