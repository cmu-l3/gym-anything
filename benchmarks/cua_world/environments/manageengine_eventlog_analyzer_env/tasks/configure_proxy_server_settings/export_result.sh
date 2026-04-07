#!/bin/bash
# Export results for "configure_proxy_server_settings" task

echo "=== Exporting Configure Proxy Server Settings results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture Database State
# We dump relevant tables to text files for the python verifier to parse
# We look for typical ManageEngine configuration tables
echo "Dumping database configuration..."
DB_DUMP_FILE="/tmp/ela_db_dump.txt"

{
    echo "=== TABLE: SystemConfig ==="
    ela_db_query "SELECT * FROM SystemConfig" 
    echo "=== TABLE: GlobalConfig ==="
    ela_db_query "SELECT * FROM GlobalConfig"
    echo "=== TABLE: ProxyConfiguration ==="
    ela_db_query "SELECT * FROM ProxyConfiguration"
} > "$DB_DUMP_FILE" 2>/dev/null

# Also check for config files on disk (secondary storage)
grep -r "proxy.dmz.corp" /opt/ManageEngine/EventLog/conf/ > /tmp/conf_grep_host.txt 2>/dev/null || true
grep -r "8080" /opt/ManageEngine/EventLog/conf/ > /tmp/conf_grep_port.txt 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Check screenshot existence
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Basic check inside bash to see if values appear in the dump (helpful for debugging log)
FOUND_HOST=$(grep -c "proxy.dmz.corp" "$DB_DUMP_FILE")
FOUND_PORT=$(grep -c "8080" "$DB_DUMP_FILE")
echo "Debug: Found host count: $FOUND_HOST, Found port count: $FOUND_PORT"

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "db_dump_path": "/tmp/ela_db_dump.txt",
    "conf_grep_host_path": "/tmp/conf_grep_host.txt"
}
EOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="