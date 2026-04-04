#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Tide Window Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format
echo "Saving file as tide_analysis.ods..."

# Use Save As dialog to ensure ODS format
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/tide_analysis.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# Handle potential overwrite dialog
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/tide_analysis.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/tide_analysis.ods"
    ls -lh /home/ga/Documents/tide_analysis.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/cape_cod_tides.csv" ]; then
        echo "📄 Original CSV exists (may have been modified)"
        # Try to convert CSV to ODS using LibreOffice headless
        su - ga -c "DISPLAY=:1 libreoffice --headless --convert-to ods --outdir /home/ga/Documents /home/ga/Documents/cape_cod_tides.csv" || true
        sleep 2
        if [ -f "/home/ga/Documents/cape_cod_tides.ods" ]; then
            mv /home/ga/Documents/cape_cod_tides.ods /home/ga/Documents/tide_analysis.ods || true
            echo "✅ Converted CSV to ODS format"
        fi
    fi
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Force close if still running
if pgrep -f "soffice.*calc" > /dev/null; then
    echo "Force closing LibreOffice..."
    pkill -f "soffice.*calc" || true
    sleep 1
fi

echo "=== Export Complete ==="