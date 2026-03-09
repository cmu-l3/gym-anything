#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Manuscript Submission Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Try to save as ODS format with specific filename
OUTPUT_FILE="/home/ga/Documents/manuscript_submissions_cleaned.ods"

# Use Save As dialog (Ctrl+Shift+S)
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
echo "Setting filename..."
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If overwrite dialog appears, confirm
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: Expected file not found, trying fallback locations..."
    
    # Check if original CSV was modified
    if [ -f "/home/ga/Documents/manuscript_submissions_messy.csv" ]; then
        echo "ℹ️ Original CSV still exists, attempting to save it as ODS"
        # Save current file
        safe_xdotool ga :1 key --delay 200 ctrl+s
        sleep 1
    fi
    
    # Also check for .ods version of original
    if [ -f "/home/ga/Documents/manuscript_submissions_messy.ods" ]; then
        echo "ℹ️ Found ODS version of file"
        cp /home/ga/Documents/manuscript_submissions_messy.ods "$OUTPUT_FILE" 2>/dev/null || true
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Double-check if file exists after close
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Export confirmed: $OUTPUT_FILE"
elif [ -f "/home/ga/Documents/manuscript_submissions_messy.ods" ]; then
    echo "ℹ️ Found alternative file: manuscript_submissions_messy.ods"
elif [ -f "/home/ga/Documents/manuscript_submissions_messy.csv" ]; then
    echo "ℹ️ Found original CSV file"
fi

echo "=== Export Complete ==="