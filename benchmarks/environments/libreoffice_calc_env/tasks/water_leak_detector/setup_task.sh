#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Water Leak Detection Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with 30 days of water usage data
# Data includes normal usage (80-120 gal/day), anomalies (160-220 gal), and meter outages (0)
cat > /home/ga/Documents/water_usage_data.csv << 'CSVEOF'
Date,Gallons
2024-01-01,95
2024-01-02,103
2024-01-03,88
2024-01-04,112
2024-01-05,97
2024-01-06,105
2024-01-07,94
2024-01-08,189
2024-01-09,102
2024-01-10,91
2024-01-11,0
2024-01-12,108
2024-01-13,115
2024-01-14,172
2024-01-15,99
2024-01-16,106
2024-01-17,93
2024-01-18,197
2024-01-19,110
2024-01-20,87
2024-01-21,104
2024-01-22,165
2024-01-23,98
2024-01-24,101
2024-01-25,183
2024-01-26,95
2024-01-27,109
2024-01-28,92
2024-01-29,207
2024-01-30,103
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/water_usage_data.csv
sudo chmod 644 /home/ga/Documents/water_usage_data.csv

echo "✅ Created water_usage_data.csv with 30 days of data"
ls -lh /home/ga/Documents/water_usage_data.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with water usage data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/water_usage_data.csv > /tmp/calc_water_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_water_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "WARNING: LibreOffice Calc window did not appear within timeout"
    # Don't exit, continue anyway
fi

sleep 2

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
        
        # Position cursor at cell A1
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
else
    echo "⚠️ Could not find Calc window ID"
fi

echo ""
echo "=== Water Leak Detection Task Setup Complete ==="
echo ""
echo "📊 Task Overview:"
echo "  Analyze 30 days of household water usage to detect potential leaks"
echo ""
echo "📝 Required Actions:"
echo "  1. Review the imported water usage data (Date in A, Gallons in B)"
echo "  2. Insert column C: '7-Day Avg Baseline' with rolling average formula"
echo "     → In C8: =AVERAGE(B2:B8), then copy down to C31"
echo "  3. Insert column D: 'Threshold' (baseline × 1.5)"
echo "     → In D8: =C8*1.5, then copy down to D31"
echo "  4. Insert column E: 'Leak Alert?' to flag anomalies"
echo "     → In E8: =IF(B8>D8,\"POTENTIAL LEAK\",\"\"), then copy down to E31"
echo "  5. Insert column F: 'Excess Gallons' to quantify waste"
echo "     → In F8: =IF(B8>D8,B8-C8,0), then copy down to F31"
echo "  6. Save the file as 'water_analysis.ods'"
echo ""
echo "✅ Expected outcome: 5-8 days flagged as potential leaks"
echo "💡 Tip: Days with 0 gallons are meter outages; calculations will handle them"
echo ""