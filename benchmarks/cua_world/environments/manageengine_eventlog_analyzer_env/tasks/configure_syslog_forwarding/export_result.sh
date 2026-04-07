#!/bin/bash
# Export results for "configure_syslog_forwarding" task

echo "=== Exporting Syslog Forwarding Configuration ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Database Inspection
# We try to dump the contents of the forwarding table to check for the specific IP/Port
echo "Querying database for forwarding rules..."
DB_DUMP=""
TABLE_USED=""
for table in "SyslogForwarding" "SL_SyslogForwarding" "ForwardingList"; do
    # Try to select all columns
    DUMP=$(ela_db_query "SELECT * FROM $table" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$DUMP" ]; then
        DB_DUMP="$DUMP"
        TABLE_USED="$table"
        echo "Dumped table $table"
        break
    fi
done

# 2. Config File Inspection (Fallback)
# Sometimes settings are serialized to XML/Properties
echo "Grepping config files..."
CONFIG_GREP=$(grep -r "10.200.50.25" /opt/ManageEngine/EventLog/conf/ 2>/dev/null | head -n 5)

# 3. Web API Inspection (Fallback/Confirmation)
# Try to scrape the forwarding page using authenticated curl
echo "Scraping web settings..."
COOKIE_JAR=$(ela_login)
WEB_CONTENT=""
# Try common URL patterns for forwarding settings
for endpoint in "/event/syslogForwarding.do" "/event/api/v1/forwarding"; do
    CONTENT=$(curl -s -b "$COOKIE_JAR" "http://localhost:8095$endpoint" 2>/dev/null)
    if echo "$CONTENT" | grep -q "10.200.50.25"; then
        WEB_CONTENT="Found IP in $endpoint"
        break
    fi
done

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We construct the JSON carefully to avoid syntax errors with the raw dump
# Escape the DB dump for JSON inclusion
DB_DUMP_ESCAPED=$(echo "$DB_DUMP" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
CONFIG_GREP_ESCAPED=$(echo "$CONFIG_GREP" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
WEB_CONTENT_ESCAPED=$(echo "$WEB_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_table_used": "$TABLE_USED",
    "db_records": $DB_DUMP_ESCAPED,
    "config_grep": $CONFIG_GREP_ESCAPED,
    "web_content_evidence": $WEB_CONTENT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to accessible location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="