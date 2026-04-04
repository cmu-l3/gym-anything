#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Mileage Tax Deduction Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format with specific name
OUTPUT_FILE="/home/ga/Documents/mileage_log_complete.ods"

# Try Save As dialog
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 1

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If format confirmation appears, press Enter again
safe_xdotool ga :1 key Return
sleep 1

# Also do a regular Ctrl+S save to ensure CSV is updated
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if files were saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ ODS file saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif wait_for_file "/home/ga/Documents/mileage_log.csv" 5; then
    echo "✅ CSV file updated: /home/ga/Documents/mileage_log.csv"
    ls -lh /home/ga/Documents/mileage_log.csv
    # Also try to export to ODS using command line
    echo "Attempting background export to ODS..."
    su - ga -c "libreoffice --headless --convert-to ods /home/ga/Documents/mileage_log.csv --outdir /home/ga/Documents/" || true
    sleep 2
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="