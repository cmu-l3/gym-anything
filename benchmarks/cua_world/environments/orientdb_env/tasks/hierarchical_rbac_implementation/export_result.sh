#!/bin/bash
echo "=== Exporting Hierarchical RBAC Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_PATH="/home/ga/sarah_entitlements.json"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT="[]"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Capture content (up to 10KB safely)
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | tr -d '\n' | tr -d '\r' | sed 's/"/\\"/g')
fi

# 2. Extract Database State via API (for Verifier)
# We need to know if the schema and data exist.
# Since we can't exec_in_env in verifier, we dump the state here to JSON.

echo "Dumping DB schema and graph topology..."

# Get Schema (Classes)
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null)

# Query Users
USERS_JSON=$(orientdb_sql "demodb" "SELECT username FROM AppUser")

# Query Groups
GROUPS_JSON=$(orientdb_sql "demodb" "SELECT name FROM AppGroup")

# Query Resources
RESOURCES_JSON=$(orientdb_sql "demodb" "SELECT name FROM AppResource")

# Query MemberOf Topology (Source -> Target)
MEMBER_EDGES_JSON=$(orientdb_sql "demodb" "SELECT out.username AS user, out.name AS group_src, in.name AS group_tgt FROM MemberOf")

# Query Access Topology
ACCESS_EDGES_JSON=$(orientdb_sql "demodb" "SELECT out.name AS group, in.name AS resource, level FROM HasAccess")

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file": {
        "exists": $FILE_EXISTS,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "content_raw": "$FILE_CONTENT"
    },
    "db_state": {
        "schema": $SCHEMA_JSON,
        "users": $USERS_JSON,
        "groups": $GROUPS_JSON,
        "resources": $RESOURCES_JSON,
        "member_edges": $MEMBER_EDGES_JSON,
        "access_edges": $ACCESS_EDGES_JSON
    }
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="