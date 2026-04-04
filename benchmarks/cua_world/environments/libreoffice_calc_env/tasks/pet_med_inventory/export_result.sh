#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Pet Medication Inventory Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        echo "✅ Calc window focused for export"
    fi
fi

# Save file using Ctrl+S
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s || true
sleep 2

# Also try Save As to ensure we have an ODS version
OUTPUT_FILE="/home/ga/Documents/pet_medications_updated.ods"

echo "Attempting Save As to ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s || true
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a || true
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE" || true
sleep 1

# Press Return to confirm save
safe_xdotool ga :1 key --delay 200 Return || true
sleep 1

# If file format confirmation dialog appears, press Return again
safe_xdotool ga :1 key --delay 200 Return || true
sleep 1

# Verify files exist
echo ""
echo "Checking for output files..."
for file in "/home/ga/Documents/pet_medications.ods" \
            "/home/ga/Documents/pet_medications.csv" \
            "/home/ga/Documents/pet_medications_updated.ods"; do
    if [ -f "$file" ]; then
        echo "✅ Found: $file"
        ls -lh "$file"
    fi
done

# Close Calc (Ctrl+Q)
echo ""
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 1

# Force close if still running (cleanup)
if pgrep -u ga soffice > /dev/null; then
    echo "⚠️ Calc still running, forcing close..."
    sudo -u ga pkill -9 soffice || true
    sleep 1
fi

echo ""
echo "=== Export Complete ==="