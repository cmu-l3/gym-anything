#!/bin/bash
echo "=== Exporting generate_ssl_csr results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
CSR_FILE="/home/ga/Documents/acmecorp.csr"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Initialize variables
FILE_EXISTS="false"
FILE_SIZE="0"
IS_NEW="false"
VALID_CSR="false"
SUBJECT_RAW=""
KEY_SIZE="0"

# 1. Check if file exists
if [ -f "$CSR_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CSR_FILE")
    FILE_MTIME=$(stat -c %Y "$CSR_FILE")
    
    # Check if created during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # 2. Parse CSR with OpenSSL
    # Check validity
    if openssl req -in "$CSR_FILE" -verify -noout 2>/dev/null; then
        VALID_CSR="true"
        
        # Extract Subject
        # Output format usually: subject=C = US, ST = Washington, L = Seattle, O = Acme Corporation, OU = Web Operations, CN = acmecorp.test, emailAddress = admin@acmecorp.test
        SUBJECT_RAW=$(openssl req -in "$CSR_FILE" -noout -subject -nameopt RFC2253 2>/dev/null || echo "")
        
        # Extract Key Size
        KEY_INFO=$(openssl req -in "$CSR_FILE" -noout -text 2>/dev/null | grep "Public Key Algorithm" -A 1 || echo "")
        if echo "$KEY_INFO" | grep -q "2048"; then
            KEY_SIZE="2048"
        elif echo "$KEY_INFO" | grep -q "4096"; then
            KEY_SIZE="4096"
        else
            KEY_SIZE="unknown"
        fi
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Generate JSON result
# Use python to safely construct JSON
python3 -c "
import json
result = {
    'file_exists': $FILE_EXISTS,
    'file_created_during_task': $IS_NEW,
    'file_size': $FILE_SIZE,
    'valid_csr': $VALID_CSR,
    'subject_raw': '''$SUBJECT_RAW''',
    'key_size': '$KEY_SIZE',
    'task_start': $TASK_START,
    'task_end': $TASK_END
}
print(json.dumps(result))
" > "$RESULT_FILE"

# Set permissions so verifier can copy it
chmod 644 "$RESULT_FILE"

echo "=== Export complete ==="
cat "$RESULT_FILE"