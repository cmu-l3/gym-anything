#!/bin/bash
set -euo pipefail

echo "=== Exporting customize_quit_warning_message results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final state screenshot
take_screenshot /tmp/task_final.png

TARGET_TEXT="WARNING: Quitting will SUBMIT your exam permanently."
TARGET_EXAM="Chemistry 201 - Midterm"

echo "Checking database state..."

# 1. Check if the configuration node exists
CONFIG_EXISTS=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "
SELECT COUNT(*) FROM configuration_node WHERE name LIKE '%${TARGET_EXAM}%';
" 2>/dev/null || echo "0")

# 2. Extract configuration data specifically for this exam
CONFIG_DATA=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "
SELECT data FROM configuration_node WHERE name LIKE '%${TARGET_EXAM}%' LIMIT 1;
" 2>/dev/null || echo "")

# 3. Check if text is present specifically in the target config
TEXT_IN_CONFIG="false"
if echo "$CONFIG_DATA" | grep -Fq "$TARGET_TEXT"; then
    TEXT_IN_CONFIG="true"
    echo "Success: Target text found directly in configuration data."
fi

# 4. Fallback: Dump entire DB and check if text exists *anywhere* (catches alternate table schemas)
TEXT_IN_DB="false"
docker exec seb-server-mariadb mysqldump -u root -psebserver123 SEBServer > /tmp/seb_dump.sql
if grep -Fq "$TARGET_TEXT" /tmp/seb_dump.sql; then
    TEXT_IN_DB="true"
    echo "Success: Target text found in database dump."
fi

# Clean up dump
rm -f /tmp/seb_dump.sql

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Write results to JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "text_in_config": $TEXT_IN_CONFIG,
    "text_in_db": $TEXT_IN_DB,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Use safe permission transfer
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json