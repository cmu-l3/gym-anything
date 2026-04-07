#!/bin/bash
set -e
echo "=== Exporting mass_update_accounts results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_MYSQL=$(date -d "@$TASK_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")

# 3. Query DB for verification data
echo "Querying Technology accounts..."
TECH_HOT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE industry='Technology' AND rating='Hot' AND deleted=0" | tr -d '[:space:]')
TECH_TOTAL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE industry='Technology' AND deleted=0" | tr -d '[:space:]')
TECH_VALID_TS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE industry='Technology' AND rating='Hot' AND deleted=0 AND date_modified >= '$TASK_START_MYSQL'" | tr -d '[:space:]')

echo "Querying non-Technology accounts..."
suitecrm_db_query "SELECT id, IFNULL(rating,'') FROM accounts WHERE (industry != 'Technology' OR industry IS NULL) AND deleted=0 ORDER BY id" > /tmp/final_non_tech_ratings.txt

# Compare initial vs final non-Technology accounts to detect unauthorized changes
CHANGED_COUNT=0
if [ -f /tmp/initial_non_tech_ratings.txt ]; then
    while IFS=$'\t' read -r id initial_rating; do
        # Find current rating for this ID
        current_rating=$(grep "^${id}"$'\t' /tmp/final_non_tech_ratings.txt | cut -f2 || echo "")
        initial_clean=$(echo "$initial_rating" | tr -d '[:space:]')
        current_clean=$(echo "$current_rating" | tr -d '[:space:]')
        
        if [ "$current_clean" != "$initial_clean" ]; then
            CHANGED_COUNT=$((CHANGED_COUNT + 1))
            echo "Account $id changed from '$initial_clean' to '$current_clean'"
        fi
    done < /tmp/initial_non_tech_ratings.txt
fi

# 4. Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "tech_hot_count": ${TECH_HOT_COUNT:-0},
    "tech_total_count": ${TECH_TOTAL_COUNT:-0},
    "tech_valid_ts_count": ${TECH_VALID_TS:-0},
    "non_tech_changed_count": ${CHANGED_COUNT:-0},
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure file is readable
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="