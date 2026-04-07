#!/bin/bash
echo "=== Exporting evaluate_network_capacity_mfd result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create staging directory for files to verify
STAGING_DIR="/tmp/mfd_export"
rm -rf "$STAGING_DIR" 2>/dev/null || true
mkdir -p "$STAGING_DIR"
chmod 777 "$STAGING_DIR"

OUTPUT_DIR="/home/ga/SUMO_Output"
CSV_EXISTS="false"
XML_COUNT=0

# Stage the CSV file
if [ -f "$OUTPUT_DIR/mfd_data.csv" ]; then
    CSV_EXISTS="true"
    cp "$OUTPUT_DIR/mfd_data.csv" "$STAGING_DIR/mfd_data.csv"
    chmod 666 "$STAGING_DIR/mfd_data.csv"
fi

# Stage the Summary XML files
SCALES=("0.5" "1.0" "1.5" "2.0" "3.0")
for scale in "${SCALES[@]}"; do
    FILE="$OUTPUT_DIR/summary_${scale}.xml"
    if [ -f "$FILE" ]; then
        # Check if modified during task
        FILE_MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
            cp "$FILE" "$STAGING_DIR/summary_${scale}.xml"
            chmod 666 "$STAGING_DIR/summary_${scale}.xml"
            XML_COUNT=$((XML_COUNT + 1))
        fi
    fi
done

# Create JSON metadata result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "staged_xml_count": $XML_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "Staged files in $STAGING_DIR:"
ls -l "$STAGING_DIR"

echo "=== Export complete ==="