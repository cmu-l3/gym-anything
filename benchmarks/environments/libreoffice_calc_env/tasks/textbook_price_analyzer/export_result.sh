#!/bin/bash
# set -euo pipefail

echo "=== Exporting Textbook Price Analyzer Result ==="

source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save as ODS using Save As dialog
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/textbook_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle overwrite dialog if it appears
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/textbook_analysis.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/textbook_analysis.ods"
    ls -lh /home/ga/Documents/textbook_analysis.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/textbook_prices.csv" ]; then
        echo "✅ CSV file exists (may have been modified in place)"
        # Try to convert CSV to ODS for verification
        su - ga -c "DISPLAY=:1 libreoffice --headless --convert-to ods --outdir /home/ga/Documents /home/ga/Documents/textbook_prices.csv" || true
        sleep 2
    fi
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Handle unsaved changes dialog if it appears
safe_xdotool ga :1 key Return || true
sleep 0.5

echo "=== Export Complete ==="