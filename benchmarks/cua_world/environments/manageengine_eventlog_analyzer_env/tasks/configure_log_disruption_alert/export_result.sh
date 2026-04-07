#!/bin/bash
echo "=== Exporting Configure Log Disruption Alert result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if screenshot exists
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# Query the database for the alert configuration
# We look for configurations related to Log Collection or Device Status
# Note: In ELA, table names might vary by version, so we try a couple of likely candidates.
# We output the raw rows for the python verifier to parse.

echo "Querying database for alert configuration..."
DB_DUMP_FILE="/tmp/db_dump.txt"

# Try SystemAlertConfig (common for system alerts)
echo "--- SystemAlertConfig ---" > "$DB_DUMP_FILE"
ela_db_query "SELECT * FROM SystemAlertConfig" >> "$DB_DUMP_FILE" 2>/dev/null || echo "Table not found" >> "$DB_DUMP_FILE"

# Try AlertProfile (common for user alerts)
echo "--- AlertProfile ---" >> "$DB_DUMP_FILE"
ela_db_query "SELECT * FROM AlertProfile WHERE PROFILE_NAME LIKE '%Log%' OR PROFILE_NAME LIKE '%Device%'" >> "$DB_DUMP_FILE" 2>/dev/null || echo "Table not found" >> "$DB_DUMP_FILE"

# Try querying generic settings if specific tables fail
echo "--- GlobalConfig ---" >> "$DB_DUMP_FILE"
ela_db_query "SELECT * FROM SystemConfig WHERE PARAMETER LIKE '%Alert%'" >> "$DB_DUMP_FILE" 2>/dev/null || true

# Read the dump content safely into a variable for JSON embedding
# We use python to escape it properly
DB_CONTENT=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" < "$DB_DUMP_FILE")

# Compare with initial state to see if DB changed
INITIAL_HASH=$(md5sum /tmp/initial_alert_config.txt 2>/dev/null | awk '{print $1}')
FINAL_HASH=$(md5sum "$DB_DUMP_FILE" 2>/dev/null | awk '{print $1}')
DB_CHANGED="false"
if [ "$INITIAL_HASH" != "$FINAL_HASH" ]; then
    DB_CHANGED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "db_content": $DB_CONTENT,
    "db_changed": $DB_CHANGED
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="