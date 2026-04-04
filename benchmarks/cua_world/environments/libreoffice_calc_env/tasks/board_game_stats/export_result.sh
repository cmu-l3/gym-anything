#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Board Game Stats Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name using Save As
OUTPUT_FILE="/home/ga/Documents/board_game_stats.ods"

# Try Save As dialog (Ctrl+Shift+S)
echo "Opening Save As dialog..."
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If overwrite dialog appears, confirm
safe_xdotool ga :1 key Return
sleep 0.5

# Also try regular save as fallback
safe_xdotool ga :1 key ctrl+s
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Try alternate location
    if [ -f "/home/ga/Documents/game_log.ods" ]; then
        echo "⚠️ File saved as game_log.ods instead"
        cp /home/ga/Documents/game_log.ods "$OUTPUT_FILE" || true
    else
        echo "⚠️ Warning: Output file not found at expected location"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 0.5

echo "=== Export Complete ==="