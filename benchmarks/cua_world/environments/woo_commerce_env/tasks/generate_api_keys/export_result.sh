#!/bin/bash
# Export script for Generate API Keys task

echo "=== Exporting Generate API Keys Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. CHECK DATABASE STATE
# ---------------------
# Find the key created during the task (highest ID with correct description)
KEY_DATA=$(wc_query "SELECT key_id, user_id, permissions, truncated_key 
    FROM wp_woocommerce_api_keys 
    WHERE description = 'ShipStation Integration' 
    ORDER BY key_id DESC LIMIT 1" 2>/dev/null)

DB_RECORD_FOUND="false"
DB_KEY_ID=""
DB_USER_ID=""
DB_PERMISSIONS=""
DB_TRUNCATED_KEY=""

if [ -n "$KEY_DATA" ]; then
    DB_RECORD_FOUND="true"
    DB_KEY_ID=$(echo "$KEY_DATA" | cut -f1)
    DB_USER_ID=$(echo "$KEY_DATA" | cut -f2)
    DB_PERMISSIONS=$(echo "$KEY_DATA" | cut -f3)
    DB_TRUNCATED_KEY=$(echo "$KEY_DATA" | cut -f4)
    echo "Found DB Record: ID=$DB_KEY_ID, Perms=$DB_PERMISSIONS, Trunc=$DB_TRUNCATED_KEY"
else
    echo "No matching record found in wp_woocommerce_api_keys"
fi

# 2. CHECK OUTPUT FILE
# --------------------
FILE_PATH="/home/ga/api_credentials.txt"
FILE_EXISTS="false"
FILE_CK=""
FILE_CS=""

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    # Extract keys using grep and awk/sed. Assuming format "Consumer Key: ck_..."
    FILE_CK=$(grep -i "Consumer Key" "$FILE_PATH" | head -1 | sed 's/.*: //' | tr -d '[:space:]')
    FILE_CS=$(grep -i "Consumer Secret" "$FILE_PATH" | head -1 | sed 's/.*: //' | tr -d '[:space:]')
    
    # Also try to just find patterns if labels are missing
    if [ -z "$FILE_CK" ]; then
        FILE_CK=$(grep -o "ck_[a-zA-Z0-9]*" "$FILE_PATH" | head -1)
    fi
    if [ -z "$FILE_CS" ]; then
        FILE_CS=$(grep -o "cs_[a-zA-Z0-9]*" "$FILE_PATH" | head -1)
    fi
    
    echo "File found. Extracted CK: ${FILE_CK:0:10}... CS: ${FILE_CS:0:10}..."
else
    echo "Output file not found at $FILE_PATH"
fi

# 3. VERIFY KEYS (LIVE TEST & MATCH)
# ----------------------------------
API_TEST_SUCCESS="false"
TRUNCATED_MATCH="false"

if [ "$FILE_EXISTS" = "true" ] && [ -n "$FILE_CK" ] && [ -n "$FILE_CS" ]; then
    # Test A: Check against DB truncated key
    # WooCommerce stores last 7 chars of the consumer key in `truncated_key`
    CK_LEN=${#FILE_CK}
    if [ $CK_LEN -ge 7 ]; then
        FILE_TRUNCATED=${FILE_CK: -7}
        if [ "$FILE_TRUNCATED" = "$DB_TRUNCATED_KEY" ]; then
            TRUNCATED_MATCH="true"
            echo "Key from file matches DB record (truncated check passed)"
        else
            echo "Mismatch: File ends in $FILE_TRUNCATED, DB expects $DB_TRUNCATED_KEY"
        fi
    fi

    # Test B: Live API connection
    echo "Testing keys against API..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${FILE_CK}:${FILE_CS}" \
        "http://localhost/wp-json/wc/v3/system_status")
    
    echo "API Test HTTP Code: $HTTP_CODE"
    
    if [ "$HTTP_CODE" = "200" ]; then
        API_TEST_SUCCESS="true"
    fi
fi

# 4. EXPORT JSON
# --------------
TEMP_JSON=$(mktemp /tmp/api_keys_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_record_found": $DB_RECORD_FOUND,
    "db_permissions": "$(json_escape "$DB_PERMISSIONS")",
    "db_user_id": "$(json_escape "$DB_USER_ID")",
    "file_exists": $FILE_EXISTS,
    "file_has_ck": $([ -n "$FILE_CK" ] && echo "true" || echo "false"),
    "file_has_cs": $([ -n "$FILE_CS" ] && echo "true" || echo "false"),
    "truncated_match": $TRUNCATED_MATCH,
    "api_test_success": $API_TEST_SUCCESS,
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="