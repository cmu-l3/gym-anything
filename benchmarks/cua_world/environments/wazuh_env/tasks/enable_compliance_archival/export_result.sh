#!/bin/bash
echo "=== Exporting enable_compliance_archival results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROOF_FILE="/home/ga/archive_proof.json"

# 1. Check Configuration (ossec.conf)
echo "Checking ossec.conf configuration..."
CONFIG_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf)

# Check logall_json
LOGALL_JSON_ENABLED="false"
if echo "$CONFIG_CONTENT" | grep -q "<logall_json>yes</logall_json>"; then
    LOGALL_JSON_ENABLED="true"
fi

# Check localfile
LOCALFILE_CONFIGURED="false"
# Look for the filename inside a localfile block. 
# Simple grep is usually sufficient for verification unless XML is very broken.
if echo "$CONFIG_CONTENT" | grep -A 5 "<localfile>" | grep -q "/var/log/legacy_fin_app.log"; then
    LOCALFILE_CONFIGURED="true"
fi

# 2. Check for the specific event in archives.json inside the container
echo "Checking archives.json for target event..."
TOKEN="Transaction ID 998877"
EVENT_FOUND_IN_ARCHIVE="false"

# We grep inside the container. 
# We look for the token.
if docker exec "${CONTAINER}" grep -q "$TOKEN" /var/ossec/logs/archives/archives.json 2>/dev/null; then
    EVENT_FOUND_IN_ARCHIVE="true"
fi

# 3. Check Proof File on Host
PROOF_FILE_EXISTS="false"
PROOF_VALID="false"
PROOF_CONTENT=""

if [ -f "$PROOF_FILE" ]; then
    PROOF_FILE_EXISTS="true"
    # Read content
    PROOF_CONTENT=$(cat "$PROOF_FILE")
    # Validate content has token
    if echo "$PROOF_CONTENT" | grep -q "$TOKEN"; then
        PROOF_VALID="true"
    fi
fi

# 4. Check if manager process is running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" pgrep ossec-analysisd > /dev/null; then
    MANAGER_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "logall_json_enabled": $LOGALL_JSON_ENABLED,
    "localfile_configured": $LOCALFILE_CONFIGURED,
    "event_found_in_archive": $EVENT_FOUND_IN_ARCHIVE,
    "proof_file_exists": $PROOF_FILE_EXISTS,
    "proof_valid": $PROOF_VALID,
    "manager_running": $MANAGER_RUNNING,
    "task_start_timestamp": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="