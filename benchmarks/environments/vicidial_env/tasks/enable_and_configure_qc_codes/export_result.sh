#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check System Setting: QC Features Active
# We query the database directly
QC_ACTIVE_STATUS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -s -e \
    "SELECT qc_features_active FROM system_settings LIMIT 1;" 2>/dev/null || echo "0")

echo "QC Active Status: $QC_ACTIVE_STATUS"

# 2. Check for the created codes
# We export them to a temp file to parse into JSON
CODES_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -s -e \
    "SELECT code, code_name FROM vicidial_qc_codes WHERE code IN ('PCI_FAIL', 'RUDE', 'EXCELLENT');" | \
    while read -r code name; do
        # Escape quotes for JSON safety
        clean_name=$(echo "$name" | sed 's/"/\\"/g')
        echo "{\"code\": \"$code\", \"name\": \"$clean_name\"},"
    done)

# Remove trailing comma if exists and wrap in array
CODES_JSON="[${CODES_JSON%,}]"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "qc_features_active": "$QC_ACTIVE_STATUS",
    "found_codes": $CODES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="