#!/bin/bash
set -euo pipefail

echo "=== Exporting edit_user_account_settings results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Define fallback if seb_db_query is not available
if ! type seb_db_query >/dev/null 2>&1; then
    seb_db_query() {
        docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "$1" 2>/dev/null
    }
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Retrieve timing data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Retrieve initial state data
INITIAL_TZ=$(cat /tmp/initial_timezone.txt 2>/dev/null || echo "UTC")
INITIAL_EMAIL=$(cat /tmp/initial_email.txt 2>/dev/null || echo "emily.chen@westlake-university.edu")

# Query current state from database
CURRENT_TZ=$(seb_db_query "SELECT timezone FROM user WHERE username='emily.chen';" | tr -d '[:space:]')
CURRENT_EMAIL=$(seb_db_query "SELECT email FROM user WHERE username='emily.chen';" | tr -d '[:space:]')

# Check if Firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result with safe temp file handling
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_tz": "$INITIAL_TZ",
    "initial_email": "$INITIAL_EMAIL",
    "current_tz": "$CURRENT_TZ",
    "current_email": "$CURRENT_EMAIL",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Make sure the file is properly copied and readable
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="