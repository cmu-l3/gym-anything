#!/bin/bash
echo "=== Exporting log_historical_visitor_entry results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if an export file exists
EXPORT_FOUND="false"
EXPORT_PATH=""
EXPORT_SIZE="0"
EXPORT_CONTENT=""

# Check for various extensions since the user might choose csv, txt, xls
for ext in csv txt xls xlsx html; do
    f="/home/ga/Documents/verification_export.$ext"
    if [ -f "$f" ]; then
        EXPORT_FOUND="true"
        EXPORT_PATH="$f"
        EXPORT_SIZE=$(stat -c%s "$f" 2>/dev/null || echo "0")
        
        # If text-based, read content for verification
        if [[ "$ext" == "csv" || "$ext" == "txt" || "$ext" == "html" ]]; then
            # Read first 50 lines to avoid massive dumps
            EXPORT_CONTENT=$(head -n 50 "$f" | base64 -w 0)
        else
            EXPORT_CONTENT="BINARY_FILE"
        fi
        break
    fi
done

# Get the target date we expected
TARGET_DATE_US=$(cat /tmp/target_date_us.txt 2>/dev/null || echo "")
TARGET_DATE_ISO=$(cat /tmp/target_date_iso.txt 2>/dev/null || echo "")

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "export_found": $EXPORT_FOUND,
    "export_path": "$EXPORT_PATH",
    "export_size": $EXPORT_SIZE,
    "export_content_base64": "$EXPORT_CONTENT",
    "target_date_us": "$TARGET_DATE_US",
    "target_date_iso": "$TARGET_DATE_ISO",
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Save to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Found export: $EXPORT_FOUND"