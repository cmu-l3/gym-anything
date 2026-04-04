#!/bin/bash
echo "=== Exporting Nationality Friendship Projection Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_PATH="/home/ga/nationality_network_report.txt"

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    # Read the first 50 lines of the report safely
    REPORT_CONTENT=$(head -n 50 "$REPORT_PATH" | base64 -w 0)
    
    # Check if created during task
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
else
    REPORT_CREATED_DURING_TASK="false"
fi

# 2. Query OrientDB for the Graph State
# We need to extract the nodes and edges the agent created to verify them.

DB="demodb"
USER="admin"
PASS="admin"
AUTH_HEADER="Authorization: Basic $(echo -n "$USER:$PASS" | base64)"

echo "Querying graph state..."

# Check if classes exist
NODES_EXIST=$(orientdb_class_exists "$DB" "NationalityNode"; echo $?) # 0=yes, 1=no
LINKS_EXIST=$(orientdb_class_exists "$DB" "NationalityLink"; echo $?) # 0=yes, 1=no

# Get NationalityNode data (Name, ProfileCount)
NODES_JSON="[]"
if [ "$NODES_EXIST" -eq 0 ]; then
    NODES_JSON=$(curl -s -X POST \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d '{"command": "SELECT Name, ProfileCount FROM NationalityNode"}' \
        "http://localhost:2480/command/${DB}/sql" | \
        python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('result', [])))" 2>/dev/null || echo "[]")
fi

# Get NationalityLink data (out.Name, in.Name, FriendshipCount)
LINKS_JSON="[]"
if [ "$LINKS_EXIST" -eq 0 ]; then
    LINKS_JSON=$(curl -s -X POST \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d '{"command": "SELECT out.Name as FromNat, in.Name as ToNat, FriendshipCount FROM NationalityLink"}' \
        "http://localhost:2480/command/${DB}/sql" | \
        python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('result', [])))" 2>/dev/null || echo "[]")
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 3. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "size": $REPORT_SIZE,
        "content_base64": "$REPORT_CONTENT"
    },
    "graph_state": {
        "nodes_class_exists": $([ "$NODES_EXIST" -eq 0 ] && echo "true" || echo "false"),
        "links_class_exists": $([ "$LINKS_EXIST" -eq 0 ] && echo "true" || echo "false"),
        "nodes": $NODES_JSON,
        "links": $LINKS_JSON
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result size: $(stat -c %s /tmp/task_result.json)"