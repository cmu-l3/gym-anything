#!/bin/bash
echo "=== Exporting Graph Traversal Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_PATH="/home/ga/graph_analysis_report.txt"

# 1. Capture Report File State
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
    FILE_CREATED_DURING_TASK="false"
fi

# 2. Generate Ground Truth Data directly from Database
# We query the DB now to get the authoritative answers to compare against agent's work
echo "Generating ground truth..."

# Helper to run query and extract single integer value
get_count() {
    local query="$1"
    # Use python to safely parse JSON response from orientdb_sql utility
    orientdb_sql "demodb" "$query" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Result is usually a list of dicts. We look for 'count', 'cnt', or just the first value.
    res = data.get('result', [])
    if res:
        # Handle cases like [{'count': 10}] or [{'cnt': 10}]
        val = list(res[0].values())
        # Filter for numeric values (ignore @rid, @class meta fields if present, though projection usually clean)
        nums = [v for k,v in res[0].items() if isinstance(v, (int, float)) and not k.startswith('@')]
        if nums: print(int(nums[0]))
        else: print(0)
    else:
        print(0)
except Exception:
    print(0)
" 2>/dev/null || echo "0"
}

# Execute Ground Truth Queries
GT_VERTICES=$(get_count "SELECT count(*) FROM V")
GT_EDGES=$(get_count "SELECT count(*) FROM E")
GT_5STAR=$(get_count "SELECT count(*) FROM Hotels WHERE Stars = 5")
GT_COUNTRIES=$(get_count "SELECT count(DISTINCT(Country)) FROM Hotels")
# Luca Network: 2-hop traversal count. 
# Query: SELECT count(*) FROM (TRAVERSE out('HasFriend') FROM (SELECT FROM Profiles WHERE Email = 'luca.rossi@example.com') MAXDEPTH 2) WHERE @class = 'Profiles'
GT_LUCA=$(get_count "SELECT count(*) FROM (TRAVERSE out('HasFriend') FROM (SELECT FROM Profiles WHERE Email = 'luca.rossi@example.com') MAXDEPTH 2) WHERE @class = 'Profiles'")

echo "Ground Truth: V=$GT_VERTICES, E=$GT_EDGES, 5*=$GT_5STAR, C=$GT_COUNTRIES, L=$GT_LUCA"

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "ground_truth": {
        "TOTAL_VERTICES": $GT_VERTICES,
        "TOTAL_EDGES": $GT_EDGES,
        "FIVE_STAR_HOTELS": $GT_5STAR,
        "HOTEL_COUNTRIES": $GT_COUNTRIES,
        "LUCA_NETWORK_SIZE": $GT_LUCA
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save and cleanup
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="