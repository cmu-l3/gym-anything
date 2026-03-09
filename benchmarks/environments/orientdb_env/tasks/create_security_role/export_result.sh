#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_security_role results ==="

DB="demodb"
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Query Role Information ---
echo "Querying Role 'data_analyst'..."
# Fetch full role object including rules and inheritance
ROLE_DATA_RAW=$(orientdb_sql "$DB" "SELECT name, mode, rules, inheritedRole.name as parent_role FROM ORole WHERE name = 'data_analyst'")

# Check if role exists
ROLE_EXISTS="false"
ROLE_PARENT=""
HAS_CLASS_PERM="false"
HAS_CLUSTER_PERM="false"

if [ -n "$ROLE_DATA_RAW" ] && [[ "$ROLE_DATA_RAW" != *"result\":[]"* ]]; then
    ROLE_EXISTS="true"
    
    # Parse parent role
    ROLE_PARENT=$(echo "$ROLE_DATA_RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    res = d.get('result', [{}])[0]
    parent = res.get('parent_role', '')
    if isinstance(parent, list): parent = parent[0] if parent else ''
    print(parent)
except: print('')
")

    # Check permissions (OrientDB permissions: 1=Create, 2=Read, 4=Update, 8=Delete)
    # We need Create (1) on database.class and database.cluster
    # Permissions map can be complex, parsing via python
    PERMS=$(echo "$ROLE_DATA_RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    res = d.get('result', [{}])[0]
    rules = res.get('rules', {})
    
    # Helper to check CREATE bit (1)
    def has_create(val):
        if isinstance(val, int): return (val & 1) > 0
        if isinstance(val, dict): return (val.get('access', 0) & 1) > 0
        return False

    cls_perm = has_create(rules.get('database.class', 0))
    clus_perm = has_create(rules.get('database.cluster', 0))
    print(f'{str(cls_perm).lower()},{str(clus_perm).lower()}')
except: print('false,false')
")
    HAS_CLASS_PERM=$(echo "$PERMS" | cut -d, -f1)
    HAS_CLUSTER_PERM=$(echo "$PERMS" | cut -d, -f2)
fi

# --- 2. Query User Information ---
echo "Querying User 'maria_garcia'..."
USER_DATA_RAW=$(orientdb_sql "$DB" "SELECT name, status, roles.name as role_names FROM OUser WHERE name = 'maria_garcia'")

USER_EXISTS="false"
USER_STATUS=""
USER_ROLES=""

if [ -n "$USER_DATA_RAW" ] && [[ "$USER_DATA_RAW" != *"result\":[]"* ]]; then
    USER_EXISTS="true"
    
    USER_STATUS=$(echo "$USER_DATA_RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('result', [{}])[0].get('status', ''))
except: print('')
")
    
    USER_ROLES=$(echo "$USER_DATA_RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    roles = d.get('result', [{}])[0].get('role_names', [])
    if isinstance(roles, list): print(','.join(roles))
    else: print(str(roles))
except: print('')
")
fi

# --- 3. Authentication Test ---
echo "Testing authentication as maria_garcia..."
# Try to list Hotels using the new user
AUTH_TEST_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "maria_garcia:Analyst2024!" \
    "${ORIENTDB_URL}/query/${DB}/sql/SELECT%20count(*)%20FROM%20Hotels/1" 2>/dev/null || echo "000")

AUTH_SUCCESS="false"
if [ "$AUTH_TEST_CODE" = "200" ]; then
    AUTH_SUCCESS="true"
fi

# --- 4. Anti-Gaming Checks ---
INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

CREATED_DURING_TASK="false"
if [ "$INITIAL_ROLE_COUNT" = "0" ] && [ "$ROLE_EXISTS" = "true" ]; then
    # Simplistic check: if it wasn't there before and is there now, it was created during task
    CREATED_DURING_TASK="true"
fi

# --- 5. Generate Result JSON ---
cat > "$RESULT_JSON" << EOF
{
  "role_exists": $ROLE_EXISTS,
  "role_parent": "$ROLE_PARENT",
  "perm_database_class_create": $HAS_CLASS_PERM,
  "perm_database_cluster_create": $HAS_CLUSTER_PERM,
  "user_exists": $USER_EXISTS,
  "user_status": "$USER_STATUS",
  "user_roles": "$USER_ROLES",
  "auth_success": $AUTH_SUCCESS,
  "created_during_task": $CREATED_DURING_TASK,
  "task_start_time": $TASK_START_TIME,
  "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat "$RESULT_JSON"