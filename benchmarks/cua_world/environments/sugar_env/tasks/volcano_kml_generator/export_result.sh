#!/bin/bash
echo "=== Exporting volcano_kml_generator task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

OUTPUT_PATH="/home/ga/Documents/high_stratovolcanoes.kml"

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE
}
EOF

# Ensure safe copying
cp "$TEMP_JSON" /tmp/volcano_kml_result.json
chmod 666 /tmp/volcano_kml_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/volcano_kml_result.json"
cat /tmp/volcano_kml_result.json
echo "=== Export complete ==="