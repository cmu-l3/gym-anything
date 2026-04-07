#!/bin/bash
echo "=== Exporting implement_ar_alert_forwarder result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
SCRIPT_PATH="/var/ossec/active-response/bin/ticket_forwarder.py"
OUTPUT_PATH="/var/ossec/logs/ticketing_queue.json"
CONF_PATH="/var/ossec/etc/ossec.conf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Export the Script
echo "Exporting script..."
docker cp "$CONTAINER:$SCRIPT_PATH" /tmp/ticket_forwarder.py 2>/dev/null || echo "Script not found"

# 2. Export ossec.conf
echo "Exporting ossec.conf..."
docker cp "$CONTAINER:$CONF_PATH" /tmp/ossec.conf 2>/dev/null

# 3. Export the output file (ticketing queue)
echo "Exporting output file..."
docker cp "$CONTAINER:$OUTPUT_PATH" /tmp/ticketing_queue.json 2>/dev/null || echo "Output file not found"

# 4. Check Script Metadata (Permissions/Time) inside container
echo "Checking script metadata..."
SCRIPT_META=$(docker exec "$CONTAINER" stat -c '{"mode": "%a", "user": "%U", "group": "%G", "mtime": %Y}' "$SCRIPT_PATH" 2>/dev/null || echo "{}")

# 5. Unit Test the Script (Functional Logic Check)
# Run the script inside the container with a mock payload to see if it actually works
echo "Running script unit test..."
MOCK_PAYLOAD='{"command":"ticket-forward","parameters":{"alert":{"id":"999999","level":12,"description":"UnitTest Alert","timestamp":"2023-01-01T00:00:00.000+0000"}}}'
UNIT_TEST_OUTPUT_FILE="/tmp/unit_test_output.json"

# We run the script and direct output to a temp file inside container
docker exec "$CONTAINER" bash -c "echo '$MOCK_PAYLOAD' | python3 $SCRIPT_PATH" 2>/dev/null
# Check if it appended to the file (assuming script appends)
# We'll read the last line of the output file
LAST_LINE=$(docker exec "$CONTAINER" tail -n 1 "$OUTPUT_PATH" 2>/dev/null || echo "")

# 6. Check if Manager is Running
MANAGER_RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "false")

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $([ -f /tmp/ticket_forwarder.py ] && echo "true" || echo "false"),
    "conf_exists": $([ -f /tmp/ossec.conf ] && echo "true" || echo "false"),
    "output_file_exists": $([ -f /tmp/ticketing_queue.json ] && echo "true" || echo "false"),
    "script_metadata": $SCRIPT_META,
    "unit_test_last_line": $(echo "$LAST_LINE" | jq -R .),
    "manager_running": $MANAGER_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="