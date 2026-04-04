#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Tool Library Investigation Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS using Save As dialog
echo "Saving file as ODS..."
OUTPUT_FILE="/home/ga/Documents/tool_damage_investigation.ods"

# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# Handle potential "file exists" dialog by pressing Enter again
safe_xdotool ga :1 key Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Investigation spreadsheet saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found at expected location"
    # Check if original CSV was modified instead
    if [ -f "/home/ga/Documents/tool_library_log.ods" ]; then
        echo "   Found: /home/ga/Documents/tool_library_log.ods"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 0.5

echo "=== Export Complete ==="