#!/bin/bash
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Firefox NSS DB for the certificate and its trust flags
# Format: certutil -L -d sql:/path/to/profile
CERT_INFO=$(certutil -L -d "sql:$PROFILE_DIR" 2>/dev/null | grep "Acme Corp Root CA" || echo "")

CERT_IMPORTED="false"
TRUST_FLAGS=""

if [ -n "$CERT_INFO" ]; then
    CERT_IMPORTED="true"
    # Extract trust flags (usually looks like "CT,C,C" or "CT,,")
    TRUST_FLAGS=$(echo "$CERT_INFO" | awk '{print $NF}')
fi

# 3. Check for security exception bypasses
OVERRIDE_USED="false"
if [ -f "$PROFILE_DIR/cert_override.txt" ]; then
    if grep -q "internal.corp.local" "$PROFILE_DIR/cert_override.txt"; then
        OVERRIDE_USED="true"
    fi
fi

# 4. Check extracted text file
OUTPUT_PATH="/home/ga/Documents/policy_focus.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | tr -d '\n' | sed 's/"/\\"/g' | head -c 500)
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "cert_imported": $CERT_IMPORTED,
    "trust_flags": "$TRUST_FLAGS",
    "override_used": $OVERRIDE_USED,
    "output_file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": "$FILE_CONTENT"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="