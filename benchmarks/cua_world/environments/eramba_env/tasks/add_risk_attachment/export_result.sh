#!/bin/bash
echo "=== Exporting add_risk_attachment result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_attachment_count.txt 2>/dev/null || echo "0")

RISK_TITLE="Phishing Attacks on Employees"
FILE_PATTERN="phishing_simulation_report"

# 1. Get Risk ID
RISK_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM risks WHERE title='$RISK_TITLE' AND deleted=0 LIMIT 1;" 2>/dev/null)

ATTACHMENT_FOUND="false"
ATTACHMENT_ID=""
FINAL_COUNT="0"
DB_FILENAME=""
DB_CREATED=""

if [ -n "$RISK_ID" ]; then
    # 2. Check current attachment count
    FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
        "SELECT count(*) FROM attachments WHERE model='Risks' AND foreign_key=$RISK_ID AND deleted=0;" 2>/dev/null || echo "0")
    
    # 3. Check for specific file
    # Get the latest attachment for this risk matching the filename pattern
    RESULT_ROW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
        "SELECT id, original_filename, created FROM attachments WHERE model='Risks' AND foreign_key=$RISK_ID AND original_filename LIKE '%$FILE_PATTERN%' AND deleted=0 ORDER BY created DESC LIMIT 1;" 2>/dev/null)
    
    if [ -n "$RESULT_ROW" ]; then
        ATTACHMENT_FOUND="true"
        ATTACHMENT_ID=$(echo "$RESULT_ROW" | awk '{print $1}')
        DB_FILENAME=$(echo "$RESULT_ROW" | awk '{print $2}')
        DB_CREATED=$(echo "$RESULT_ROW" | awk '{print $3" "$4}') # Date and time
    fi
fi

# 4. Check if file physically exists (optional, depends on eramba storage config, usually local file system mapped to docker)
# Eramba usually stores files in /var/www/eramba/app/webroot/files/attachments/
# We check inside the container
PHYSICAL_FILE_EXISTS="false"
if [ "$ATTACHMENT_FOUND" = "true" ] && [ -n "$ATTACHMENT_ID" ]; then
    # Look for file with attachment ID in name or just check if recent files exist in attachments dir
    # Eramba naming convention varies, but we can check if *any* file was added recently
    PHYSICAL_CHECK=$(docker exec eramba-app find /var/www/eramba/app/webroot/files/attachments -type f -mmin -10 2>/dev/null | wc -l)
    if [ "$PHYSICAL_CHECK" -gt "0" ]; then
        PHYSICAL_FILE_EXISTS="true"
    fi
fi

# 5. Capture final screenshot
take_screenshot /tmp/add_risk_attachment_final.png

# 6. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "risk_id": "${RISK_ID:-0}",
    "initial_attachment_count": $INITIAL_COUNT,
    "final_attachment_count": $FINAL_COUNT,
    "attachment_found": $ATTACHMENT_FOUND,
    "attachment_id": "${ATTACHMENT_ID:-0}",
    "db_filename": "$DB_FILENAME",
    "db_created": "$DB_CREATED",
    "physical_file_exists": $PHYSICAL_FILE_EXISTS,
    "screenshot_path": "/tmp/add_risk_attachment_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="