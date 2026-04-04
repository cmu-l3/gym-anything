#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Water Leak Forensics Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Create results directory
sudo -u ga mkdir -p /home/ga/Documents/results

# Try to save the file
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if file was saved to results directory or Documents
RESULT_FILE_1="/home/ga/Documents/results/water_leak_analysis.ods"
RESULT_FILE_2="/home/ga/Documents/water_leak_analysis.ods"
RESULT_FILE_3="/home/ga/Documents/water_meter_readings.ods"

if [ -f "$RESULT_FILE_1" ]; then
    echo "✅ Analysis file found at: $RESULT_FILE_1"
    ls -lh "$RESULT_FILE_1"
elif [ -f "$RESULT_FILE_2" ]; then
    echo "✅ Analysis file found at: $RESULT_FILE_2"
    ls -lh "$RESULT_FILE_2"
elif [ -f "$RESULT_FILE_3" ]; then
    echo "✅ Modified file found at: $RESULT_FILE_3"
    ls -lh "$RESULT_FILE_3"
else
    echo "⚠️  Warning: Analysis file not found in expected locations"
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="