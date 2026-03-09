#!/bin/bash
echo "=== Exporting take_snapshot task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/DICOM/exports"
INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG} 2>/dev/null | wc -l || echo "0")

FOUND="false"
EXPORT_FILE=""
EXPORT_SIZE=0

# Find any new export files
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    FOUND="true"
    # Get the most recent export
    EXPORT_FILE=$(ls -t "$EXPORT_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG} 2>/dev/null | head -1)
    if [ -n "$EXPORT_FILE" ] && [ -f "$EXPORT_FILE" ]; then
        EXPORT_SIZE=$(stat -f%z "$EXPORT_FILE" 2>/dev/null || stat --printf="%s" "$EXPORT_FILE" 2>/dev/null || echo "0")
    fi
fi

# Also check common snapshot locations
for DIR in "$EXPORT_DIR" "/home/ga/Pictures" "/home/ga/Desktop" "/tmp"; do
    if [ "$FOUND" = "false" ]; then
        NEW_FILE=$(find "$DIR" -maxdepth 1 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -mmin -5 2>/dev/null | head -1)
        if [ -n "$NEW_FILE" ]; then
            FOUND="true"
            EXPORT_FILE="$NEW_FILE"
            EXPORT_SIZE=$(stat -f%z "$NEW_FILE" 2>/dev/null || stat --printf="%s" "$NEW_FILE" 2>/dev/null || echo "0")
        fi
    fi
done

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "export_file": "$EXPORT_FILE",
    "export_size": $EXPORT_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
