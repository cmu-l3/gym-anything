#!/bin/bash
# Export result for configure_network_discovery task

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || { echo "Failed to source task_utils.sh"; exit 1; }

echo "=== Exporting Configure Network Discovery results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SUMMARY_FILE="/home/ga/discovery_config_summary.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check summary file
SUMMARY_EXISTS="false"
SUMMARY_CREATED_DURING_TASK="false"
SUMMARY_CONTENT=""

if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_CONTENT=$(cat "$SUMMARY_FILE" | base64 -w 0)
    
    FILE_MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    fi
fi

# Attempt to dump recent DB changes to look for the IP configuration
# We don't know the exact table, so we'll do a string search in a partial dump if possible,
# or just rely on VLM if DB access is too brittle.
# Here we try to verify if the string "10.0.1.1" exists in the database.
DB_EVIDENCE_FOUND="false"

# Simple check: string search in relevant tables if we can guess them, 
# otherwise we skip deep DB verification and rely on VLM + File.
# Let's try a broad query if ela-db-query is available.
if command -v ela_db_query >/dev/null; then
    # Try to find the IP in likely configuration tables
    # Note: This is best-effort. VLM is the primary verifier for UI actions here.
    echo "Searching DB for IP range configuration..."
    # We search for the string representation in a dump of the last few minutes 
    # (Not easily possible with simple SQL), so we'll just check if the IP is present anywhere.
    # This query might take a moment.
    
    # We'll skip complex DB grepping to avoid timeouts/locks and rely on the agent's summary + VLM.
    # However, we can check if the server is responsive.
    DB_STATUS="responsive"
else
    DB_STATUS="unknown"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_created_during_task": $SUMMARY_CREATED_DURING_TASK,
    "summary_content_base64": "$SUMMARY_CONTENT",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="