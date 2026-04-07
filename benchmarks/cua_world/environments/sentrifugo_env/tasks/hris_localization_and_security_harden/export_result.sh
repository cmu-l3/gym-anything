#!/bin/bash
echo "=== Exporting HRIS Localization and Security Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ---- Query Database for Module States ----
echo "Extracting module states from database..."
# Build a JSON object string of modules and their active status
MODULES_JSON="{"
# Get all modules and format them as "Name": isactive
DB_OUTPUT=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SELECT CONCAT('\"', modulename, '\": ', isactive) FROM main_modules;" 2>/dev/null)
if [ -n "$DB_OUTPUT" ]; then
    MODULES_JSON+=$(echo "$DB_OUTPUT" | paste -sd "," -)
fi
MODULES_JSON+="}"

# ---- Export to JSON ----
TEMP_JSON=$(mktemp /tmp/hris_security_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "export_timestamp": $(date +%s),
    "modules": $MODULES_JSON
}
EOF

# Move to final location securely
rm -f /tmp/hris_security_result.json 2>/dev/null || sudo rm -f /tmp/hris_security_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hris_security_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hris_security_result.json
chmod 666 /tmp/hris_security_result.json 2>/dev/null || sudo chmod 666 /tmp/hris_security_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/hris_security_result.json"
cat /tmp/hris_security_result.json

echo "=== Export Complete ==="