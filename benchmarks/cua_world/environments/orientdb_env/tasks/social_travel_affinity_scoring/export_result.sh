#!/bin/bash
echo "=== Exporting social_travel_affinity_scoring results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Output File exists and was created during task
OUTPUT_FILE="/home/ga/top_travel_friends.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
    # Read first 5 lines for verification
    OUTPUT_CONTENT=$(head -n 5 "$OUTPUT_FILE" | base64 -w 0)
fi

# 2. Query Database State
echo "Querying database for verification..."

# Check HasVisited edges count
HAS_VISITED_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasVisited" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Check AffinityScore property existence (check if metadata contains it)
PROPERTY_CHECK=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
cls = next((c for c in data.get('classes',[]) if c['name']=='HasFriend'), {})
props = [p['name'] for p in cls.get('properties',[])]
print('true' if 'AffinityScore' in props else 'false')
" 2>/dev/null || echo "false")

# Get AffinityScore for the specific test friendship (Alice -> Bob)
# Alice (task_user_a) -> Bob (task_user_b)
TEST_SCORE=$(orientdb_sql "demodb" "SELECT AffinityScore FROM HasFriend WHERE out.Email='task_user_a@test.com' AND in.Email='task_user_b@test.com'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); res=d.get('result',[]); print(res[0].get('AffinityScore', -1) if res else -1)" 2>/dev/null || echo "-1")

# Get AffinityScore for Bob -> Charlie (Should be 0)
ZERO_SCORE_CHECK=$(orientdb_sql "demodb" "SELECT AffinityScore FROM HasFriend WHERE out.Email='task_user_b@test.com' AND in.Email='task_user_c@test.com'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); res=d.get('result',[]); print(res[0].get('AffinityScore', -1) if res else -1)" 2>/dev/null || echo "-1")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING,
    "output_content_base64": "$OUTPUT_CONTENT",
    "db_state": {
        "has_visited_edge_count": $HAS_VISITED_COUNT,
        "affinity_score_property_exists": $PROPERTY_CHECK,
        "test_affinity_score": $TEST_SCORE,
        "test_zero_score": $ZERO_SCORE_CHECK
    }
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json