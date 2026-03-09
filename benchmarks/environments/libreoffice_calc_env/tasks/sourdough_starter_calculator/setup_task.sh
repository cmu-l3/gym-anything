#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Sourdough Starter Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with feeding log data
cat > /home/ga/Documents/feeding_log.csv << 'CSVEOF'
Date,Time,Starter_Weight_g,Flour_Added_g,Water_Added_g,Room_Temp_C,Hours_Since_Feed
2024-01-15,08:00,50,50,50,22,12
2024-01-15,20:00,50,50,50,21,12
2024-01-16,08:00,50,50,50,23,12
2024-01-16,20:00,50,50,50,22,12
2024-01-17,09:00,50,50,50,24,13
2024-01-17,21:00,50,50,50,23,12
2024-01-18,08:00,60,60,60,22,11
2024-01-18,20:00,60,60,60,21,12
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/feeding_log.csv
sudo chmod 644 /home/ga/Documents/feeding_log.csv

echo "✅ Created feeding_log.csv with 8 feeding entries"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with feeding log..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/feeding_log.csv > /tmp/calc_sourdough_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_sourdough_task.log || true
    # Don't exit, allow task to continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, allow task to continue
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
        # Maximize window for better visibility
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at cell H1 (where new columns should start)
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column H (right of existing data)
for i in {1..7}; do
    safe_xdotool ga :1 key Right
    sleep 0.1
done

echo "=== Sourdough Starter Calculator Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Add column H: 'Total_Weight_After_Feed' = Starter + Flour + Water"
echo "  2. Add column I: 'Hydration_Percent' = (Water/Flour)*100"
echo "  3. Add column J: 'Hours_to_Peak' based on temperature (optional)"
echo "  4. Add column K: 'Ready_to_Bake' = IF(AND(hours 3-8, weight>=150), YES, NO)"
echo "  5. Below data: Add 'Total Flour Used' with SUM formula"
echo "  6. Below data: Add 'Average Hydration' with AVERAGE formula"
echo ""
echo "💡 Hints:"
echo "  - Use formulas with cell references (e.g., =C2+D2+E2)"
echo "  - Copy formulas down to all data rows"
echo "  - Hydration should be 70-150% range"
echo "  - Ready flag: hours between 3-8 AND weight >= 150g"