#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Community Fridge Safety Manager Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Prepare output path
OUTPUT_FILE="/home/ga/Documents/community_fridge_sorted.ods"

# Try Save As to ensure ODS format
echo "Saving as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Also try regular save (Ctrl+S) as fallback
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if file was saved
if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Try alternate location
    ALT_FILE="/home/ga/Documents/community_fridge_inventory.ods"
    if [ -f "$ALT_FILE" ]; then
        echo "⚠️ File saved as: $ALT_FILE"
        # Copy to expected location
        cp "$ALT_FILE" "$OUTPUT_FILE" 2>/dev/null || true
    else
        echo "⚠️ Warning: File not found at expected location"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="