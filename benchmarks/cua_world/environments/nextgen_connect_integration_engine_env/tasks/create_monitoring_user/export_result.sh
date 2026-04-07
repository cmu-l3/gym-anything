#!/bin/bash
# Export script for create_monitoring_user task
# verifies the user details via API and DB query

echo "=== Exporting create_monitoring_user results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 1. VERIFY USER EXISTENCE & ATTRIBUTES VIA API
# ==============================================================================
echo "Querying API for 'monitor_analyst'..."

# Fetch all users
ALL_USERS_JSON=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/json" \
    "https://localhost:8443/api/users" 2>/dev/null)

# Extract specific user details using python
# Output format: JSON object of the found user or empty object
FOUND_USER_JSON=$(echo "$ALL_USERS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    users = []
    if isinstance(data, list):
        users = data
    elif isinstance(data, dict):
        l = data.get('list', {})
        if isinstance(l, dict):
            u = l.get('user', [])
            users = u if isinstance(u, list) else [u]
    
    found = {}
    for u in users:
        if u.get('username') == 'monitor_analyst':
            found = u
            break
    print(json.dumps(found))
except:
    print('{}')
" 2>/dev/null)

USER_EXISTS=$(echo "$FOUND_USER_JSON" | python3 -c "import sys, json; print('true' if json.load(sys.stdin) else 'false')")

# ==============================================================================
# 2. VERIFY PASSWORD AUTHENTICATION
# ==============================================================================
AUTH_SUCCESS="false"
if [ "$USER_EXISTS" = "true" ]; then
    echo "Verifying password authentication..."
    # Try to hit a protected endpoint using the new credentials
    # Credentials from task description: monitor_analyst / M0nitor2024!Secure
    AUTH_HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
        -u "monitor_analyst:M0nitor2024!Secure" \
        -H "X-Requested-With: OpenAPI" \
        "https://localhost:8443/api/server/version" 2>/dev/null)
    
    if [ "$AUTH_HTTP_CODE" = "200" ]; then
        AUTH_SUCCESS="true"
        echo "Authentication successful (HTTP 200)"
    else
        echo "Authentication failed (HTTP $AUTH_HTTP_CODE)"
        
        # Try login endpoint explicitly as fallback
        LOGIN_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "X-Requested-With: OpenAPI" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=monitor_analyst&password=M0nitor2024%21Secure" \
            "https://localhost:8443/api/users/_login" 2>/dev/null)
        
        if [ "$LOGIN_CODE" = "200" ]; then
            AUTH_SUCCESS="true"
            echo "Login endpoint successful"
        fi
    fi
fi

# ==============================================================================
# 3. DB VERIFICATION (Backup)
# ==============================================================================
DB_USER_COUNT=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c \
    "SELECT COUNT(*) FROM person WHERE username = 'monitor_analyst';" 2>/dev/null || echo "0")

DB_EXISTS="false"
if [ "$DB_USER_COUNT" -gt 0 ]; then
    DB_EXISTS="true"
fi

# ==============================================================================
# 4. CALCULATE COUNTS
# ==============================================================================
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(echo "$ALL_USERS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list): print(len(data))
    elif isinstance(data, dict):
        u = data.get('list', {}).get('user', [])
        print(len(u) if isinstance(u, list) else 1)
    else: print(1)
except: print(0)" 2>/dev/null)

# ==============================================================================
# 5. COMPILE RESULT
# ==============================================================================
# Create a safe JSON with all gathered data
cat > /tmp/task_result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_user_count": $INITIAL_COUNT,
    "current_user_count": $CURRENT_COUNT,
    "user_exists_api": $USER_EXISTS,
    "user_details": $FOUND_USER_JSON,
    "auth_success": $AUTH_SUCCESS,
    "db_record_exists": $DB_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
write_result_json "/tmp/task_result.json" "$(cat /tmp/task_result_temp.json)"
rm -f /tmp/task_result_temp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="