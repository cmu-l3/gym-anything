#!/bin/bash
# set -euo pipefail

echo "=== Exporting Guitar Practice Log Result ==="

source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name
OUTPUT_FILE="/home/ga/Documents/guitar_practice_log.ods"

echo "Saving as ODS file..."
# Use Save As dialog
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing text and type new filename
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Return to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Handle potential "file exists" dialog
safe_xdotool ga :1 key --delay 200 Return || true
sleep 1

# Verify file was saved
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found, trying regular save..."
    # Try regular save as fallback
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="

# Check alternative filenames in case user saved differently
if [ -f "/home/ga/Documents/practice_notes_raw.ods" ]; then
    echo "📄 Found: practice_notes_raw.ods (imported CSV)"
fi
if [ -f "/home/ga/Documents/guitar_practice.ods" ]; then
    echo "📄 Found: guitar_practice.ods (alternative name)"
fi