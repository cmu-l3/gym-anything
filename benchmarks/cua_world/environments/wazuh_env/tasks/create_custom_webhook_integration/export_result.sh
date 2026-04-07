#!/bin/bash
# export_result.sh for create_custom_webhook_integration

echo "=== Exporting Custom Webhook Integration Result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
SHELL_SCRIPT="/var/ossec/integrations/custom-slack-alerts"
PYTHON_SCRIPT="/var/ossec/integrations/custom-slack-alerts.py"
CONFIG_FILE="/var/ossec/etc/ossec.conf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
SHELL_EXISTS="false"
SHELL_EXECUTABLE="false"
SHELL_MTIME=0
SHELL_CONTENT=""

PYTHON_EXISTS="false"
PYTHON_EXECUTABLE="false"
PYTHON_VALID_SYNTAX="false"
PYTHON_MTIME=0
PYTHON_CONTENT=""

CONFIG_HAS_INTEGRATION="false"
INTEGRATION_BLOCK=""

MANAGER_RUNNING="false"
FUNCTIONAL_TEST_PASSED="false"
FUNCTIONAL_TEST_OUTPUT=""

# ==============================================================================
# 1. Check Shell Script
# ==============================================================================
if docker exec "$CONTAINER" [ -f "$SHELL_SCRIPT" ]; then
    SHELL_EXISTS="true"
    # Check execution permission
    if docker exec "$CONTAINER" [ -x "$SHELL_SCRIPT" ]; then
        SHELL_EXECUTABLE="true"
    fi
    # Get mtime
    SHELL_MTIME=$(docker exec "$CONTAINER" stat -c %Y "$SHELL_SCRIPT" 2>/dev/null || echo "0")
    # Get content (base64 encoded to avoid JSON issues)
    SHELL_CONTENT=$(docker exec "$CONTAINER" cat "$SHELL_SCRIPT" | base64 -w 0)
fi

# ==============================================================================
# 2. Check Python Script
# ==============================================================================
if docker exec "$CONTAINER" [ -f "$PYTHON_SCRIPT" ]; then
    PYTHON_EXISTS="true"
    if docker exec "$CONTAINER" [ -x "$PYTHON_SCRIPT" ]; then
        PYTHON_EXECUTABLE="true"
    fi
    PYTHON_MTIME=$(docker exec "$CONTAINER" stat -c %Y "$PYTHON_SCRIPT" 2>/dev/null || echo "0")
    PYTHON_CONTENT=$(docker exec "$CONTAINER" cat "$PYTHON_SCRIPT" | base64 -w 0)
    
    # Check syntax
    if docker exec "$CONTAINER" python3 -m py_compile "$PYTHON_SCRIPT" >/dev/null 2>&1; then
        PYTHON_VALID_SYNTAX="true"
    fi
fi

# ==============================================================================
# 3. Check Configuration
# ==============================================================================
# Extract the integration block from ossec.conf
# We look for the block containing 'custom-slack-alerts'
RAW_CONFIG=$(docker exec "$CONTAINER" cat "$CONFIG_FILE")
if echo "$RAW_CONFIG" | grep -q "<name>custom-slack-alerts</name>"; then
    CONFIG_HAS_INTEGRATION="true"
    # Attempt to extract the specific integration block context (grep -C5 is rough but useful)
    INTEGRATION_BLOCK=$(echo "$RAW_CONFIG" | grep -C 5 "<name>custom-slack-alerts</name>" | base64 -w 0)
fi

# ==============================================================================
# 4. Check Manager Status
# ==============================================================================
# We check if the process is running inside the container
if docker exec "$CONTAINER" pgrep -f "wazuh-modulesd" >/dev/null; then
    MANAGER_RUNNING="true"
fi

# ==============================================================================
# 5. Functional Test
# ==============================================================================
# Create a sample alert file inside the container
TEST_ALERT_FILE="/tmp/test_alert_$(date +%s).json"
docker exec -i "$CONTAINER" tee "$TEST_ALERT_FILE" > /dev/null <<EOF
{
  "timestamp": "2024-01-15T10:30:00.000+0000",
  "rule": {
    "level": 12,
    "description": "High severity event detected",
    "id": "100200",
    "groups": ["authentication_failed"]
  },
  "agent": {
    "id": "001",
    "name": "web-server-01",
    "ip": "192.168.1.100"
  },
  "full_log": "Jan 15 10:30:00 web-server-01 sshd[12345]: Failed password for root"
}
EOF

# Run the python script directly to test logic (bypass shell wrapper for unit test)
# Arguments: alert_file, api_key(dummy), hook_url
if [ "$PYTHON_EXISTS" = "true" ] && [ "$PYTHON_VALID_SYNTAX" = "true" ]; then
    # We use a dummy URL that won't resolve, but we want to see if the script tries to send
    # capturing stdout/stderr to check for crashes vs network errors
    TEST_OUTPUT=$(docker exec "$CONTAINER" timeout 5s python3 "$PYTHON_SCRIPT" "$TEST_ALERT_FILE" "dummy_key" "http://localhost:9999/test" 2>&1)
    EXIT_CODE=$?
    
    # Encode output
    FUNCTIONAL_TEST_OUTPUT=$(echo "$TEST_OUTPUT" | base64 -w 0)
    
    # We consider it passed if it didn't crash with SyntaxError or ImportError
    # ConnectionRefusedError or URLError is EXPECTED and means it tried to connect
    if echo "$TEST_OUTPUT" | grep -qE "ConnectionRefused|URLError|OSError|Network is unreachable"; then
        FUNCTIONAL_TEST_PASSED="true"
    elif [ $EXIT_CODE -eq 0 ]; then
        # Some scripts might swallow exceptions and exit 0
        FUNCTIONAL_TEST_PASSED="true"
    fi
fi

# Cleanup test file
docker exec "$CONTAINER" rm -f "$TEST_ALERT_FILE" 2>/dev/null || true

# ==============================================================================
# Export JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "shell_exists": $SHELL_EXISTS,
  "shell_executable": $SHELL_EXECUTABLE,
  "shell_mtime": $SHELL_MTIME,
  "shell_content_b64": "$SHELL_CONTENT",
  "python_exists": $PYTHON_EXISTS,
  "python_executable": $PYTHON_EXECUTABLE,
  "python_valid_syntax": $PYTHON_VALID_SYNTAX,
  "python_mtime": $PYTHON_MTIME,
  "python_content_b64": "$PYTHON_CONTENT",
  "config_has_integration": $CONFIG_HAS_INTEGRATION,
  "integration_block_b64": "$INTEGRATION_BLOCK",
  "manager_running": $MANAGER_RUNNING,
  "functional_test_passed": $FUNCTIONAL_TEST_PASSED,
  "functional_test_output_b64": "$FUNCTIONAL_TEST_OUTPUT",
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"