#!/bin/bash
# set -euo pipefail

echo "=== Exporting Aquarium Water Chemistry Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format (Ctrl+Shift+S for Save As)
echo "Saving analyzed spreadsheet..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/aquarium_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If file exists warning appears, confirm overwrite
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
OUTPUT_FILE="/home/ga/Documents/aquarium_analysis.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Analysis saved to: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: Output file not found, trying alternative save..."
    # Try simple save in case file was already named
    safe_xdotool ga :1 key ctrl+s
    sleep 1
    
    # Check for CSV file as fallback
    if [ -f "/home/ga/Documents/water_chemistry_log.csv" ]; then
        echo "⚠️ CSV file exists (may have been modified)"
    fi
fi

# Close LibreOffice Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="