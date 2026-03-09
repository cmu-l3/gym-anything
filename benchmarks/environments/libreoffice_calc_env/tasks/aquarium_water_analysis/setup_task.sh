#!/bin/bash
# set -euo pipefail

echo "=== Setting up Aquarium Water Chemistry Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Create Documents directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with 14 days of realistic water chemistry data
# Ammonia is the PRIMARY problem (most frequent violations)
# Data simulates tank with insufficient biological filtration
cat > /home/ga/Documents/water_chemistry_log.csv << 'CSVEOF'
Date,pH,Ammonia(ppm),Nitrite(ppm),Nitrate(ppm)
2024-01-01,7.2,0.15,0.25,35
2024-01-02,7.1,0.30,0.45,38
2024-01-03,7.3,0.40,0.60,42
2024-01-04,7.0,0.35,0.55,45
2024-01-05,7.2,0.50,0.70,48
2024-01-06,7.4,0.28,0.40,44
2024-01-07,7.1,0.45,0.65,50
2024-01-08,7.3,0.38,0.52,46
2024-01-09,7.2,0.42,0.48,43
2024-01-10,6.9,0.35,0.58,52
2024-01-11,7.0,0.48,0.62,55
2024-01-12,7.2,0.32,0.45,49
2024-01-13,7.1,0.40,0.68,53
2024-01-14,7.0,0.52,0.75,58
CSVEOF

chown ga:ga /home/ga/Documents/water_chemistry_log.csv
echo "✅ Created water chemistry log CSV with 14 days of data"

# Display data summary for debugging
echo "📊 Data Summary:"
echo "   - 14 days of readings"
echo "   - Expected Ammonia violations (>0.25): 11 days"
echo "   - Expected Nitrite violations (>0.5): 7 days"
echo "   - Expected Nitrate violations (>40): 13 days"
echo "   - pH mostly in safe range (6.5-7.5)"
echo "   - PRIMARY PROBLEM: Ammonia (most consistent toxicity)"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/water_chemistry_log.csv > /tmp/calc_aquarium_task.log 2>&1 &"

# Wait for LibreOffice process to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_aquarium_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of screen to select desktop (important for focus)
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

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Aquarium Water Chemistry Analysis Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Calculate averages for pH, Ammonia, Nitrite, Nitrate (use AVERAGE function)"
echo "  2. Apply conditional formatting to highlight dangerous readings:"
echo "     - Ammonia >0.25 ppm (red/orange)"
echo "     - Nitrite >0.5 ppm (red/orange)"
echo "     - Nitrate >40 ppm (yellow)"
echo "     - pH outside 6.5-7.5 range (light red)"
echo "  3. Count violations using COUNTIF formulas"
echo "  4. Identify and document PRIMARY PROBLEM"
echo ""
echo "💡 Hints:"
echo "  - Create summary section below or beside data"
echo "  - Format → Conditional Formatting → Condition"
echo "  - Example: =AVERAGE(B2:B15), =COUNTIF(C2:C15,\">0.25\")"