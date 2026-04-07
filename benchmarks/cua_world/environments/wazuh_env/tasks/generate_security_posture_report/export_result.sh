#!/bin/bash
set -e
echo "=== Exporting generate_security_posture_report result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/security_posture_report.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Collect Ground Truth Data (Live from API) ---
echo "Collection ground truth data..."

# Helper to get clean JSON response
get_json() {
    echo "$1" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)))" 2>/dev/null || echo "{}"
}

# 1. Manager Info
MGR_INFO_RAW=$(wazuh_api GET "/manager/info")
GT_MANAGER=$(echo "$MGR_INFO_RAW" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d.get('data',{}).get('affected_items',[{}])[0]))" 2>/dev/null || echo "{}")

# 2. Agent Summary
AGENT_SUM_RAW=$(wazuh_api GET "/agents/summary/status")
GT_AGENTS=$(echo "$AGENT_SUM_RAW" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d.get('data',{})))" 2>/dev/null || echo "{}")

# 3. Rules/Decoders
RULES_RAW=$(wazuh_api GET "/rules?limit=1")
GT_RULES_COUNT=$(echo "$RULES_RAW" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data',{}).get('total_affected_items', 0))" 2>/dev/null || echo "0")

DECODERS_RAW=$(wazuh_api GET "/decoders?limit=1")
GT_DECODERS_COUNT=$(echo "$DECODERS_RAW" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data',{}).get('total_affected_items', 0))" 2>/dev/null || echo "0")

# 4. Groups
GROUPS_RAW=$(wazuh_api GET "/groups")
GT_GROUPS=$(echo "$GROUPS_RAW" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps([x['name'] for x in d.get('data',{}).get('affected_items',[])]))" 2>/dev/null || echo "[]")

# 5. Indexer Health
IDX_HEALTH_RAW=$(wazuh_indexer_query "/_cluster/health")
GT_INDEXER=$(echo "$IDX_HEALTH_RAW" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps({'status': d.get('status'), 'number_of_nodes': d.get('number_of_nodes'), 'active_shards': d.get('active_shards')}))" 2>/dev/null || echo "{}")

# 6. Indices
IDX_INDICES_RAW=$(wazuh_indexer_query "/_cat/indices?format=json")
GT_INDICES=$(echo "$IDX_INDICES_RAW" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps([x['index'] for x in d]))" 2>/dev/null || echo "[]")


# --- Check User Output File ---
FILE_EXISTS="false"
FILE_VALID="false"
FILE_CONTENT="{}"
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Try to parse content
    if cat "$REPORT_FILE" | python3 -m json.tool > /dev/null 2>&1; then
        FILE_VALID="true"
        FILE_CONTENT=$(cat "$REPORT_FILE")
    fi
fi

# --- Compile Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_valid_json": $FILE_VALID,
    "file_created_during_task": $CREATED_DURING_TASK,
    "agent_report": $FILE_CONTENT,
    "ground_truth": {
        "manager": $GT_MANAGER,
        "agents": $GT_AGENTS,
        "rules_count": $GT_RULES_COUNT,
        "decoders_count": $GT_DECODERS_COUNT,
        "groups": $GT_GROUPS,
        "indexer": $GT_INDEXER,
        "indices": $GT_INDICES
    }
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="