#!/bin/bash
# export_result.sh — REST API Key Provisioning and Integration Test
# Collects information about the target file and its contents,
# then writes /tmp/api_key_result.json for the verifier.

set -euo pipefail

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting REST API Key Provisioning Results ==="

RESULT_FILE="/tmp/api_key_result.json"
TARGET_FILE="/home/ga/Desktop/api_integration_test.json"
TMP_JSON="/tmp/api_key_result_tmp.json"

# ------------------------------------------------------------
# 1. Collect file metadata
# ------------------------------------------------------------
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CONTENT_B64=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Safely export up to 100KB of the file content in Base64
    FILE_CONTENT_B64=$(head -c 100000 "$TARGET_FILE" 2>/dev/null | base64 -w 0 || true)
    
    echo "Found output file: $TARGET_FILE ($FILE_SIZE bytes, mtime: $FILE_MTIME)"
else
    echo "Output file NOT found: $TARGET_FILE"
fi

# ------------------------------------------------------------
# 2. Extract API Key tables from DB for diagnostic logging
# ------------------------------------------------------------
DB_DUMP_B64=""
if declare -f opmanager_query > /dev/null; then
    echo "Querying DB for API Key tables..."
    API_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%api%key%' OR tablename ILIKE '%token%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
    if [ -n "$API_TABLE" ]; then
        DB_DUMP=$(opmanager_query_headers "SELECT * FROM \"${API_TABLE}\" LIMIT 50;" 2>/dev/null || true)
        DB_DUMP_B64=$(echo "$DB_DUMP" | base64 -w 0 || true)
    fi
fi

# ------------------------------------------------------------
# 3. Take final screenshot
# ------------------------------------------------------------
if declare -f take_screenshot > /dev/null; then
    take_screenshot "/tmp/api_task_final_screenshot.png" || true
else
    DISPLAY=:1 scrot "/tmp/api_task_final_screenshot.png" 2>/dev/null || true
fi

# ------------------------------------------------------------
# 4. Write Result JSON
# ------------------------------------------------------------
cat > "$TMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_content_b64": "$FILE_CONTENT_B64",
    "db_dump_b64": "$DB_DUMP_B64"
}
EOF

# Move to final location securely
if declare -f safe_write_json > /dev/null; then
    safe_write_json "$TMP_JSON" "$RESULT_FILE"
else
    mv "$TMP_JSON" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "Results exported to $RESULT_FILE"
echo "=== Export Complete ==="