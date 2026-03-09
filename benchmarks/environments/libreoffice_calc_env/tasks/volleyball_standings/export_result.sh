#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Volleyball Standings Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Try to save as ODS format (preserves formulas better than CSV)
OUTPUT_FILE="/home/ga/Documents/volleyball_standings_final.ods"

echo "Attempting to save as ODS format..."
# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If format confirmation dialog appears, press Enter again
safe_xdotool ga :1 key Return
sleep 1

# Check if ODS file was created
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Standings saved as ODS: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Fallback: try regular save (Ctrl+S) which might keep CSV format
    echo "⚠️ ODS save may have failed, trying regular save..."
    safe_xdotool ga :1 key ctrl+s
    sleep 1
    
    # Check for CSV file
    if [ -f "/home/ga/Documents/volleyball_standings.csv" ]; then
        echo "✅ Standings saved as CSV: /home/ga/Documents/volleyball_standings.csv"
        ls -lh /home/ga/Documents/volleyball_standings.csv
    else
        echo "⚠️ Warning: Could not confirm file save"
    fi
fi

# Close LibreOffice Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 1

# Give time for graceful shutdown
sleep 1

echo "=== Export Complete ==="