#!/bin/bash
echo "=== Exporting task results ==="

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths (using Windows paths mapped to Linux if possible, or direct checks)
# Assuming standard mount: /home/ga/Desktop maps to C:\Users\Docker\Desktop
DESKTOP_DIR="/home/ga/Desktop"
# Fallback if mapped differently
if [ ! -d "$DESKTOP_DIR" ]; then
    DESKTOP_DIR="/mnt/c/Users/Docker/Desktop"
fi

PBIX_PATH="$DESKTOP_DIR/Commission_Model.pbix"
CSV_PATH="$DESKTOP_DIR/commission_report.csv"

# Check PBIX
PBIX_EXISTS="false"
PBIX_SIZE="0"
PBIX_CREATED_DURING="false"

if [ -f "$PBIX_PATH" ]; then
    PBIX_EXISTS="true"
    PBIX_SIZE=$(stat -c %s "$PBIX_PATH" 2>/dev/null || echo "0")
    PBIX_MTIME=$(stat -c %Y "$PBIX_PATH" 2>/dev/null || echo "0")
    if [ "$PBIX_MTIME" -gt "$TASK_START" ]; then
        PBIX_CREATED_DURING="true"
    fi
fi

# Check CSV
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_CREATED_DURING="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# Unzip PBIX to inspect internals (for verifier)
LAYOUT_JSON_PATH="/tmp/Layout.json"
DATA_MODEL_PATH="/tmp/DataModel"

if [ "$PBIX_EXISTS" = "true" ]; then
    echo "Unzipping PBIX structure..."
    # PBIX is a zip file. We extract specific components.
    unzip -p "$PBIX_PATH" "Report/Layout" > "$LAYOUT_JSON_PATH" 2>/dev/null || echo "{}" > "$LAYOUT_JSON_PATH"
    unzip -p "$PBIX_PATH" "DataModel" > "$DATA_MODEL_PATH" 2>/dev/null || touch "$DATA_MODEL_PATH"
else
    echo "{}" > "$LAYOUT_JSON_PATH"
    touch "$DATA_MODEL_PATH"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pbix_exists": $PBIX_EXISTS,
    "pbix_created_during_task": $PBIX_CREATED_DURING,
    "pbix_size_bytes": $PBIX_SIZE,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "csv_size_bytes": $CSV_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Also copy the CSV and Layout for the verifier to consume
cp "$CSV_PATH" /tmp/exported_commission.csv 2>/dev/null || touch /tmp/exported_commission.csv
chmod 666 /tmp/exported_commission.csv
chmod 666 "$LAYOUT_JSON_PATH"
chmod 666 "$DATA_MODEL_PATH"

echo "=== Export complete ==="