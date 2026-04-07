#!/bin/bash
echo "=== Exporting task results ==="

WORKSPACE="/home/ga/workspace/fintech_crypto"
OUTPUT_FILE="$WORKSPACE/data/output_encrypted.csv"
RESULT_JSON="/tmp/task_result.json"

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the output pipeline file was successfully generated
FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Capture source code for static analysis
ENC_CODE=$(cat "$WORKSPACE/crypto_utils/encryption.py" 2>/dev/null || echo "FILE_NOT_FOUND")
TOK_CODE=$(cat "$WORKSPACE/crypto_utils/tokens.py" 2>/dev/null || echo "FILE_NOT_FOUND")
AUTH_CODE=$(cat "$WORKSPACE/crypto_utils/auth.py" 2>/dev/null || echo "FILE_NOT_FOUND")

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Write to JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'code': {
        'encryption': '''$ENC_CODE''',
        'tokens': '''$TOK_CODE''',
        'auth': '''$AUTH_CODE'''
    }
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# Move and set permissions
mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
echo "=== Export complete ==="