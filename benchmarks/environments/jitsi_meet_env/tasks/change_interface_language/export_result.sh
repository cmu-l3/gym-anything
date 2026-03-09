#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting change_interface_language results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract LocalStorage Data (Programmatic Verification)
# Firefox locks the sqlite database, so we copy it first.
# Path format depends on Firefox version (Snap vs Deb), checking both.
LS_DB_PATH=""
DETECTED_LANG="none"

# Search for the localStorage database for localhost:8080
# Typical path: storage/default/http+++localhost+8080/ls/data.sqlite
FOUND_DBS=$(find /home/ga/snap/firefox/ /home/ga/.mozilla/firefox/ \
    -name "data.sqlite" 2>/dev/null | grep "http+++localhost+8080" || true)

if [ -n "$FOUND_DBS" ]; then
    # Take the most recently modified one
    LS_DB_PATH=$(ls -t $FOUND_DBS | head -n 1)
    echo "Found localStorage DB: $LS_DB_PATH"

    # Copy to temp to avoid locks
    cp "$LS_DB_PATH" /tmp/ls_check.sqlite
    if [ -f "${LS_DB_PATH}-wal" ]; then cp "${LS_DB_PATH}-wal" /tmp/ls_check.sqlite-wal; fi
    if [ -f "${LS_DB_PATH}-shm" ]; then cp "${LS_DB_PATH}-shm" /tmp/ls_check.sqlite-shm; fi

    # Query the database
    # Firefox stores values as UTF-16LE in 'value' column, key in 'key' column
    # We use sqlite3 to get the hex output, then try to decode or grep broadly
    
    # Query: Get the hex value for the settings key
    HEX_VAL=$(sqlite3 /tmp/ls_check.sqlite "SELECT hex(value) FROM data WHERE key = 'features/base/settings';" 2>/dev/null || echo "")
    
    if [ -n "$HEX_VAL" ]; then
        # Check for the pattern "language":"fr" in hex (UTF-16LE)
        # "l" is 6C 00, "a" is 61 00 ...
        # Instead of constructing complex hex, we convert back to ASCII if possible or use xxd
        # Simple heuristic: grep the output of xxd for "language" and "fr"
        
        DECODED_VAL=$(echo "$HEX_VAL" | xxd -r -p | tr -d '\000') # Strip null bytes to make it ASCII-ish
        echo "Decoded Settings: $DECODED_VAL"
        
        # Parse JSON from the decoded string
        if echo "$DECODED_VAL" | grep -q '"language":"fr"'; then
            DETECTED_LANG="fr"
        elif echo "$DECODED_VAL" | grep -q '"language":"en"'; then
            DETECTED_LANG="en"
        elif echo "$DECODED_VAL" | grep -q '"language":'; then
             # Extract what it is
             DETECTED_LANG=$(echo "$DECODED_VAL" | grep -o '"language":"[^"]*"' | cut -d'"' -f4)
        fi
    else
        echo "Key 'features/base/settings' not found in DB."
    fi
    
    # Cleanup
    rm -f /tmp/ls_check.sqlite*
else
    echo "WARNING: Could not locate Firefox localStorage database."
fi

# 3. Check App State (Running?)
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "detected_language": "$DETECTED_LANG",
    "screenshot_path": "/tmp/task_final.png",
    "initial_screenshot_path": "/tmp/task_initial.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="