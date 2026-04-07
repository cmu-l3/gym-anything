#!/bin/bash
# Export script for Implement Custom Active Response task
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RESULT_JSON=$(mktemp /tmp/result.XXXXXX.json)

echo "Capturing final state..."

# 1. LIVE FIRE TEST (The ultimate verification)
# We create a file and see if it gets moved.
echo "Running Live Fire Test..."

# Ensure directories exist for the test (if agent deleted them by mistake)
mkdir -p /home/ga/contracts /home/ga/quarantine
chmod 777 /home/ga/contracts /home/ga/quarantine

# Generate a unique test file
TEST_FILENAME="verification_payload_$(date +%s).txt"
TEST_FILE="/home/ga/contracts/${TEST_FILENAME}"
EXPECTED_DEST="/home/ga/quarantine/${TEST_FILENAME}.suspect"

echo "Creating trigger file: ${TEST_FILE}"
echo "Malware payload simulation" > "${TEST_FILE}"
# Ensure wazuh user can read it (Docker user mapping can be tricky, so make it world readable for test)
chmod 666 "${TEST_FILE}"

# Wait for reaction (FIM scan + Analysis + Active Response)
# Real-time FIM should be fast, but we give it 30s buffer
echo "Waiting 30 seconds for Active Response..."
sleep 30

# Check results
LIVE_TEST_PASSED="false"
FILE_MOVED="false"
FILE_RENAMED="false"

if [ ! -f "${TEST_FILE}" ]; then
    echo "Source file gone (Good)"
    FILE_MOVED="true"
else
    echo "Source file still exists (Fail)"
fi

if [ -f "${EXPECTED_DEST}" ]; then
    echo "Destination file found (Good)"
    FILE_RENAMED="true"
else
    echo "Destination file not found (Fail)"
fi

if [ "$FILE_MOVED" = "true" ] && [ "$FILE_RENAMED" = "true" ]; then
    LIVE_TEST_PASSED="true"
fi

# 2. CONFIGURATION EXTRACTION
# We extract the files to analyze *why* it passed or failed

# Extract ossec.conf content related to task
OSSEC_CONF_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf 2>/dev/null | base64 -w 0)

# Extract local_rules.xml content
RULES_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null | base64 -w 0)

# Extract the script
SCRIPT_PATH="/var/ossec/active-response/bin/quarantine.sh"
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""
SCRIPT_PERMS=""

if docker exec "${CONTAINER}" [ -f "${SCRIPT_PATH}" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_CONTENT=$(docker exec "${CONTAINER}" cat "${SCRIPT_PATH}" 2>/dev/null | base64 -w 0)
    SCRIPT_PERMS=$(docker exec "${CONTAINER}" stat -c "%a %U:%G" "${SCRIPT_PATH}" 2>/dev/null)
fi

# Check directories on host
DIR_CONTRACTS_EXISTS=$( [ -d "/home/ga/contracts" ] && echo "true" || echo "false" )
DIR_QUARANTINE_EXISTS=$( [ -d "/home/ga/quarantine" ] && echo "true" || echo "false" )

# Take final screenshot
take_screenshot /tmp/task_final.png

# Build JSON result
cat > "${RESULT_JSON}" << EOF
{
    "task_start_time": ${TASK_START},
    "live_test": {
        "passed": ${LIVE_TEST_PASSED},
        "source_removed": ${FILE_MOVED},
        "dest_created": ${FILE_RENAMED},
        "test_filename": "${TEST_FILENAME}"
    },
    "static_analysis": {
        "dir_contracts_exists": ${DIR_CONTRACTS_EXISTS},
        "dir_quarantine_exists": ${DIR_QUARANTINE_EXISTS},
        "script_exists": ${SCRIPT_EXISTS},
        "script_perms": "${SCRIPT_PERMS}",
        "ossec_conf_b64": "${OSSEC_CONF_CONTENT}",
        "rules_b64": "${RULES_CONTENT}",
        "script_content_b64": "${SCRIPT_CONTENT}"
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "${RESULT_JSON}" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "${RESULT_JSON}"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json