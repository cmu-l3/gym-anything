#!/bin/bash
echo "=== Exporting Query Optimization Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_PATH="/home/ga/query_optimization_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING="false"
REPORT_CONTENT_PREVIEW=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read first 1000 chars for preview/keywords check in Python (safe reading)
    REPORT_CONTENT_PREVIEW=$(head -c 1000 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Analyze Database State (Indexes and Explain Plans)

# Helper to run explain and check for index usage
check_query_optimization() {
    local query="$1"
    # Run EXPLAIN command
    local explain_json
    explain_json=$(orientdb_sql "demodb" "EXPLAIN $query")
    
    # Parse JSON to check if index was used (look for 'indexIsUsed' or absence of 'fullScan')
    # Note: OrientDB EXPLAIN structure varies slightly by version, but usually contains execution plan
    echo "$explain_json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Result is usually in 'result' list, first item
    plan = data.get('result', [{}])[0].get('executionPlan', {})
    
    # Traverse plan to find index usage
    def finds_index(node):
        if not isinstance(node, dict): return False
        # Check specific properties often found in OrientDB plans
        if node.get('type') == 'FetchFromIndex' or 'index' in node.get('type', '').lower():
            return True
        if 'indexes' in node and node['indexes']:
            return True
        # Recursive check
        for k, v in node.items():
            if isinstance(v, list):
                for i in v: 
                    if finds_index(i): return True
            elif isinstance(v, dict):
                if finds_index(v): return True
        return False

    print('true' if finds_index(plan) else 'false')
except:
    print('false')
"
}

# Check Query 1: Hotels.City
Q1_OPTIMIZED=$(check_query_optimization "SELECT FROM Hotels WHERE City = 'Rome'")

# Check Query 2: Hotels(Country, Stars)
Q2_OPTIMIZED=$(check_query_optimization "SELECT FROM Hotels WHERE Country = 'Italy' AND Stars >= 4")

# Check Query 3: Profiles.Nationality
Q3_OPTIMIZED=$(check_query_optimization "SELECT FROM Profiles WHERE Nationality = 'British'")

# 4. Get List of Current Indexes for granular scoring
# We fetch the schema and extract relevant indexes
INDEXES_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    relevant_indexes = []
    for cls in data.get('classes', []):
        if cls['name'] in ['Hotels', 'Profiles']:
            for idx in cls.get('indexes', []):
                relevant_indexes.append({
                    'class': cls['name'],
                    'name': idx['name'],
                    'type': idx['type'],
                    'fields': idx.get('fields', [])
                })
    print(json.dumps(relevant_indexes))
except:
    print('[]')
")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "created_during_task": $REPORT_CREATED_DURING,
        "content_base64": "$REPORT_CONTENT_PREVIEW"
    },
    "optimization_status": {
        "query1_hotels_city": $Q1_OPTIMIZED,
        "query2_hotels_composite": $Q2_OPTIMIZED,
        "query3_profiles_nationality": $Q3_OPTIMIZED
    },
    "current_indexes": $INDEXES_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json