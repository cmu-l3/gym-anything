#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Science Fair Score Sheet Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Verify file exists and was recently modified
OUTPUT_FILE="/home/ga/Documents/science_fair_scoresheet.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Score sheet saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
    
    # Get file size to confirm it's not empty
    filesize=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$filesize" -gt 2000 ]; then
        echo "✅ File size OK: $filesize bytes"
    else
        echo "⚠️  Warning: File may be too small ($filesize bytes)"
    fi
else
    echo "⚠️ Warning: File not found or not recently modified"
    # Try to list what files exist
    echo "Files in Documents:"
    ls -la /home/ga/Documents/ || true
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Close any requirements text file windows
pkill -f "scoresheet_requirements.txt" || true

# Wait a moment to ensure clean shutdown
sleep 0.5

echo "=== Export Complete ==="