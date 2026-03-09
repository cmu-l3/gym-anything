#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Manuscript Timeline Validator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file as ODS (Ctrl+S should save as ODS since it was opened as CSV)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# If it prompts for format, confirm ODS
safe_xdotool ga :1 key Return
sleep 1

# Wait for file to be saved
OUTPUT_FILE="/home/ga/Documents/mystery_novel_scenes.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Might still be CSV
    if [ -f "/home/ga/Documents/mystery_novel_scenes.csv" ]; then
        echo "⚠️ File saved as CSV (original format)"
        ls -lh /home/ga/Documents/mystery_novel_scenes.csv
    else
        echo "⚠️ Warning: Output file not found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="