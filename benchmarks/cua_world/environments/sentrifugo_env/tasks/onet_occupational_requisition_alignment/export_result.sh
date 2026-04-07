#!/bin/bash
echo "=== Exporting O*NET Task Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Job Titles in database
echo "Checking Job Titles..."
FIN_MGR_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Financial Manager' AND isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "0")
TRAIN_MGR_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Training and Development Manager' AND isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "0")

# 2. Check Requisition Table for specific O*NET text
# To be robust against table name changes, we dump the DB schema and grep for the exact text strings
echo "Checking Database for O*NET Text (Requisitions)..."
docker exec sentrifugo-db mysqldump -u root -prootpass123 sentrifugo > /tmp/db_dump.sql

# Look for the exact expected text in the SQL dump
FIN_TEXT_HITS=$(grep -c "Direct and coordinate financial activities of workers in a branch, office, or department." /tmp/db_dump.sql 2>/dev/null || echo "0")
TRAIN_TEXT_HITS=$(grep -c "Plan, direct, or coordinate the training and development activities and staff of an organization." /tmp/db_dump.sql 2>/dev/null || echo "0")

# Check if application was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "financial_manager_title_count": $FIN_MGR_COUNT,
    "training_manager_title_count": $TRAIN_MGR_COUNT,
    "financial_req_text_hits": $FIN_TEXT_HITS,
    "training_req_text_hits": $TRAIN_TEXT_HITS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissive rights so verifier can read it
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="