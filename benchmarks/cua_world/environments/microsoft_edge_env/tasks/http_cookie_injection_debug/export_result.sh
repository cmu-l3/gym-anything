#!/bin/bash
# export_result.sh - Verify cookie injection and export results
set -e

echo "=== Exporting Cookie Injection Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Kill Edge to force SQLite WAL flush to disk
# This ensures the Cookies database is readable and up-to-date
echo "Stopping Edge to flush database..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# Path definitions
COOKIES_DB="/home/ga/.config/microsoft-edge/Default/Cookies"
OUTPUT_FILE="/home/ga/Desktop/cookie_verification.json"
RESULT_JSON="/tmp/task_result.json"

# --- 1. Verify Output File (Content Check) ---
FILE_EXISTS="false"
FILE_VALID_JSON="false"
FILE_CONTENT="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check if valid JSON and extract content
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        FILE_VALID_JSON="true"
        FILE_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# --- 2. Verify SQLite Database (Injection & Flags Check) ---
# We use SQLite to verify the flags (Secure/HttpOnly) which might not be visible in the JSON response body
DB_RECORDS="[]"

if [ -f "$COOKIES_DB" ]; then
    # Copy DB to temp to avoid locks
    TMP_DB=$(mktemp /tmp/cookies.sqlite.XXXXXX)
    cp "$COOKIES_DB" "$TMP_DB"
    
    # Query for httpbin.org cookies
    # Schema typically includes: name, value (encrypted), host_key, path, is_secure, is_httponly
    # We select name, is_secure, is_httponly
    # Note: value is usually encrypted, so we rely on the output file for value verification
    
    DB_DATA=$(sqlite3 "$TMP_DB" -json "SELECT name, is_secure, is_httponly FROM cookies WHERE host_key LIKE '%httpbin.org%';" 2>/dev/null || echo "[]")
    
    if [ -n "$DB_DATA" ]; then
        DB_RECORDS="$DB_DATA"
    fi
    
    rm -f "$TMP_DB"
fi

# Create Result JSON
# Using python to safely construct JSON to avoid escaping issues
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_check': {
        'exists': $FILE_EXISTS,
        'created_during_task': $FILE_CREATED_DURING_TASK,
        'valid_json': $FILE_VALID_JSON,
        'content': json.loads('''$FILE_CONTENT''') if $FILE_VALID_JSON else {}
    },
    'db_check': {
        'records': json.loads('''$DB_RECORDS''')
    }
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Results exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="