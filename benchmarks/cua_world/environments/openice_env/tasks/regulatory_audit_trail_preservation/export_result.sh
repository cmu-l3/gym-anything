#!/bin/bash
echo "=== Exporting Regulatory Audit Trail Preservation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
AUDIT_DIR="/home/ga/Desktop/QA_Audit_2026"
PRESERVED_LOG="$AUDIT_DIR/device_session_audit.log"
HASH_FILE="$AUDIT_DIR/integrity_hash.sha256"
MANIFEST_FILE="$AUDIT_DIR/audit_manifest.txt"

# 1. Verify Directory Existence
DIR_EXISTS="false"
if [ -d "$AUDIT_DIR" ]; then
    DIR_EXISTS="true"
fi

# 2. Verify Log Preservation & Content
LOG_EXISTS="false"
LOG_SIZE="0"
LOG_MTIME="0"
CONTAINS_MULTIPARAM="false"
CONTAINS_INFUSION="false"

if [ -f "$PRESERVED_LOG" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c %s "$PRESERVED_LOG")
    LOG_MTIME=$(stat -c %Y "$PRESERVED_LOG")
    
    # Check for required clinical content in the preserved log
    if grep -qi "Multiparameter" "$PRESERVED_LOG"; then
        CONTAINS_MULTIPARAM="true"
    fi
    if grep -qi "Infusion" "$PRESERVED_LOG"; then
        CONTAINS_INFUSION="true"
    fi
fi

# 3. Verify Cryptographic Integrity
HASH_FILE_EXISTS="false"
AGENT_HASH_CONTENT=""
ACTUAL_LOG_HASH=""
HASH_MATCHES="false"

if [ -f "$HASH_FILE" ]; then
    HASH_FILE_EXISTS="true"
    # Read the first "word" of the file which should be the hash
    AGENT_HASH_CONTENT=$(cat "$HASH_FILE" | grep -oE "[a-fA-F0-9]{64}" | head -1)
    
    if [ "$LOG_EXISTS" = "true" ]; then
        # Calculate actual hash of the log file the agent saved
        ACTUAL_LOG_HASH=$(sha256sum "$PRESERVED_LOG" | awk '{print $1}')
        
        # Compare (case insensitive)
        if [ "${AGENT_HASH_CONTENT,,}" == "${ACTUAL_LOG_HASH,,}" ] && [ -n "$ACTUAL_LOG_HASH" ]; then
            HASH_MATCHES="true"
        fi
    fi
fi

# 4. Verify Manifest
MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""
MANIFEST_HAS_DEVICES="false"

if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST_FILE" | head -c 500) # Read first 500 bytes to avoid huge JSON
    
    # Simple check if both device types are mentioned in manifest
    if echo "$MANIFEST_CONTENT" | grep -qi "Multiparameter" && echo "$MANIFEST_CONTENT" | grep -qi "Infusion"; then
        MANIFEST_HAS_DEVICES="true"
    fi
fi

# 5. Check OpenICE status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create Result JSON
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "dir_exists": $DIR_EXISTS,
    "log_exists": $LOG_EXISTS,
    "log_size": $LOG_SIZE,
    "log_mtime": $LOG_MTIME,
    "contains_multiparam": $CONTAINS_MULTIPARAM,
    "contains_infusion": $CONTAINS_INFUSION,
    "hash_file_exists": $HASH_FILE_EXISTS,
    "agent_hash": "$AGENT_HASH_CONTENT",
    "actual_hash": "$ACTUAL_LOG_HASH",
    "hash_matches": $HASH_MATCHES,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_has_devices": $MANIFEST_HAS_DEVICES,
    "openice_running": $OPENICE_RUNNING,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json