#!/bin/bash
set -e
echo "=== Exporting create_function task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/function_results.txt"

# 1. Check if output file exists and was modified during task
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content (limit to first 1KB to avoid huge files)
    FILE_CONTENT=$(head -c 1024 "$OUTPUT_PATH")
fi

# 2. Verify Function Existence in OrientDB
FUNCTION_EXISTS="false"
FUNC_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM OFunction WHERE name = 'getAvgHotelStars'" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

if [ "$FUNC_COUNT" -ge 1 ]; then
    FUNCTION_EXISTS="true"
fi

# 3. Verify Function Logic (Test Execution)
# We try to invoke the function via REST API to see if it works and what it returns
TEST_ITALY="null"
TEST_JAPAN="null"
FUNCTION_CALLABLE="false"

if [ "$FUNCTION_EXISTS" = "true" ]; then
    # Test Italy
    ITALY_RESP=$(curl -s -X POST \
        -u "${ORIENTDB_AUTH}" \
        -H "Content-Type: application/json" \
        -d '{"country":"Italy"}' \
        "${ORIENTDB_URL}/function/demodb/getAvgHotelStars" 2>/dev/null)
    
    # Parse result using python for robustness
    TEST_ITALY=$(echo "$ITALY_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Result structure varies based on return type. Usually {result: [...]}
    res = data.get('result', [])
    if isinstance(res, list) and len(res) > 0:
        val = res[0]
        # If it returns a row/document, look for 'value', 'avg', or just the first value
        if isinstance(val, dict):
            # Flatten dict values to find the number
            for k,v in val.items():
                if isinstance(v, (int, float)):
                    print(v); sys.exit(0)
        print(val)
    else:
        print('null')
except:
    print('null')
")

    # Test Japan
    JAPAN_RESP=$(curl -s -X POST \
        -u "${ORIENTDB_AUTH}" \
        -H "Content-Type: application/json" \
        -d '{"country":"Japan"}' \
        "${ORIENTDB_URL}/function/demodb/getAvgHotelStars" 2>/dev/null)

    TEST_JAPAN=$(echo "$JAPAN_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    res = data.get('result', [])
    if isinstance(res, list) and len(res) > 0:
        val = res[0]
        if isinstance(val, dict):
            for k,v in val.items():
                if isinstance(v, (int, float)):
                    print(v); sys.exit(0)
        print(val)
    else:
        print('null')
except:
    print('null')
")
    
    # Determine if callable (if we got non-null results)
    if [ "$TEST_ITALY" != "null" ] && [ "$TEST_JAPAN" != "null" ]; then
        FUNCTION_CALLABLE="true"
    fi
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": $(echo "$FILE_CONTENT" | jq -R .),
    "function_exists": $FUNCTION_EXISTS,
    "function_callable": $FUNCTION_CALLABLE,
    "test_result_italy": "$TEST_ITALY",
    "test_result_japan": "$TEST_JAPAN",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="