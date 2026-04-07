#!/bin/bash
echo "=== Exporting record_social_history task ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/task_final.png

PATIENT_ID=$(cat /tmp/james_wilson_id 2>/dev/null || echo "0")

# Create final DB dump
echo "Creating final database state snapshot..."
mysqldump -u freemed -pfreemed --skip-extended-insert --no-create-info freemed > /tmp/final_db.sql
sort /tmp/final_db.sql > /tmp/final_sorted.sql

# Extract ONLY newly added/modified lines in the database into db_diff.sql
echo "Extracting new database records..."
comm -13 /tmp/initial_sorted.sql /tmp/final_sorted.sql > /tmp/db_diff.sql

# Check if the app is still running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create resulting JSON metrics
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure proper permissions and move to exposed location
chmod 666 /tmp/db_diff.sql 2>/dev/null || sudo chmod 666 /tmp/db_diff.sql
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON and DB Diff exported successfully."
cat /tmp/task_result.json
echo "=== Export complete ==="