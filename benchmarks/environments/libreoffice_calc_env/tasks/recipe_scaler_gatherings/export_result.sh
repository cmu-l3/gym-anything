#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Recipe Scaler Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save as ODS format
OUTPUT_FILE="/home/ga/Documents/scaled_recipe.ods"

echo "Saving file as $OUTPUT_FILE..."

# Use Save As dialog
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists confirmation dialog appears, press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Recipe scaled and saved to: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found or not recently modified"
    # Try regular save as fallback
    echo "Attempting regular save (Ctrl+S)..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Wait for process to terminate
sleep 1

echo "=== Export Complete ==="