#!/bin/bash
echo "=== Exporting Evaluate Image Seeing Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CSV_PATH="/home/ga/AstroImages/measurements/seeing_data.csv"
TXT_PATH="/home/ga/AstroImages/measurements/seeing_report.txt"
FITS_PATH="/home/ga/AstroImages/raw/Vcomb.fits"

# 1. Check CSV File
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for verifier access
    cp "$CSV_PATH" /tmp/seeing_data.csv
    chmod 666 /tmp/seeing_data.csv
fi

# 2. Check TXT File
TXT_EXISTS="false"
TXT_CREATED_DURING_TASK="false"
if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -ge "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for verifier access
    cp "$TXT_PATH" /tmp/seeing_report.txt
    chmod 666 /tmp/seeing_report.txt
fi

# 3. Copy FITS file for dynamic verification
if [ -f "$FITS_PATH" ]; then
    cp "$FITS_PATH" /tmp/Vcomb.fits
    chmod 666 /tmp/Vcomb.fits
fi

# 4. Check if AstroImageJ is still running
AIJ_RUNNING="false"
if pgrep -f "AstroImageJ\|aij" > /dev/null; then
    AIJ_RUNNING="true"
fi

# 5. Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING_TASK,
    "aij_running": $AIJ_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Results saved to /tmp/task_result.json"