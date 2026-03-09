#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Progressive Overload Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

OUTPUT_FILE="/home/ga/Documents/workout_progression.ods"

# Save file as ODS (Ctrl+Shift+S for Save As)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 1

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If format dialog appears, press Enter again to confirm ODS format
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: ODS file not found, trying to save CSV"
    # Try saving current file
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="