#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Vintage Computer Collection Organizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with vintage computer collection data
cat > /home/ga/Documents/vintage_computers.csv << 'EOF'
Model,Manufacturer,Year,Acquisition_Date,Condition,Rarity,Parts_Availability
Apple II Plus,Apple,1979,2022-03-15,Good,8,Moderate
Commodore 64,Commodore,1982,2021-11-20,Excellent,6,Easy
IBM PCjr,IBM,1984,2023-01-10,Fair,7,Hard
TRS-80 Model III,Radio Shack,1980,2020-07-22,Poor,5,Moderate
Atari 800XL,Atari,1983,2022-09-05,Good,6,Easy
Sinclair ZX Spectrum,Sinclair,,2023-02-14,Unknown,9,Hard
Amiga 500,Commodore,1987,2021-12-01,Excellent,7,Moderate
Kaypro II,Kaypro,1982,2022-06-18,Fair,6,Moderate
Apple IIe,Apple,1983,2023-04-20,Good,7,Easy
TI-99/4A,Texas Instruments,1981,2021-09-12,Poor,5,Hard
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/vintage_computers.csv
sudo chmod 666 /home/ga/Documents/vintage_computers.csv

echo "✅ Created vintage_computers.csv with 10 systems"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc with CSV file..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/vintage_computers.csv > /tmp/calc_vintage_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_vintage_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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
        
        # Ensure cursor is at a neutral position (e.g., cell A1)
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

echo "=== Vintage Computer Collection Organizer Task Setup Complete ==="
echo ""
echo "📋 Current Collection Status:"
echo "   • 10 vintage computers cataloged"
echo "   • Columns: Model, Manufacturer, Year, Acquisition_Date, Condition, Rarity, Parts_Availability"
echo ""
echo "🎯 Your Tasks:"
echo "   1. Add 3-5 new systems from estate sale (some with Unknown condition or missing Year)"
echo "   2. Create Priority_Score formula in column H:"
echo "      Formula: (Rarity × 2) + Condition_Points + Parts_Points - Age_Penalty"
echo "      • Condition: Excellent=5, Good=3, Fair=2, Poor=1, Unknown=0"
echo "      • Parts: Easy=3, Moderate=2, Hard=1, Impossible=0"
echo "      • Age_Penalty: (2024 - Year) / 10, rounded down (use 1985 for missing years)"
echo "   3. Apply conditional formatting to Priority_Score:"
echo "      • Green (≥15): High priority"
echo "      • Yellow (10-14): Medium priority"
echo "      • Red (<10): Low priority"
echo "   4. Sort entire dataset by Priority_Score descending"
echo "   5. Save as ODS file"
echo ""
echo "💡 Tip: Use nested IF statements for condition mapping"