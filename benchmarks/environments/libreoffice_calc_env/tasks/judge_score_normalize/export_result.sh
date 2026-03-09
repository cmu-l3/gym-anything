#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Judge Score Normalization Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+Shift+S for Save As)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Type filename
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/normalized_scores.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle potential overwrite dialog
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
OUTPUT_FILE="/home/ga/Documents/normalized_scores.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Try alternate location (might still be CSV)
    if [ -f "/home/ga/Documents/pie_competition.ods" ]; then
        echo "✅ File saved as: /home/ga/Documents/pie_competition.ods"
        ls -lh /home/ga/Documents/pie_competition.ods
    elif [ -f "/home/ga/Documents/pie_competition.csv" ]; then
        echo "⚠️ File still in CSV format: /home/ga/Documents/pie_competition.csv"
        ls -lh /home/ga/Documents/pie_competition.csv
    else
        echo "⚠️ Warning: Could not verify file save"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="