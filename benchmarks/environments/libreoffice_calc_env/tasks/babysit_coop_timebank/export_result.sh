#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Babysitting Co-op Time Bank Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save as ODS file
OUTPUT_FILE="/home/ga/Documents/babysit_coop_reconciled.ods"

echo "Saving file as ODS..."
# Use Save As dialog
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and enter new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If overwrite dialog appears, confirm
safe_xdotool ga :1 key --delay 200 Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Try regular save as fallback
    echo "⚠️ Save As may have failed, trying regular Save..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="