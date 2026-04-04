#!/bin/bash
echo "=== Exporting Regional RLS Policy results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare export directory
EXPORT_FILE="/tmp/rls_export.json"

# Helper to run SQL and get JSON result
run_sql_json() {
    local user="$1"
    local pass="$2"
    local query="$3"
    
    curl -s -X POST \
        -u "${user}:${pass}" \
        -H "Content-Type: application/json" \
        -d "{\"command\":\"${query}\"}" \
        "${ORIENTDB_URL}/command/demodb/sql"
}

echo "Gathering verification data..."

# 1. Check Root View (Ground Truth)
# Get counts per nationality
ROOT_COUNTS=$(run_sql_json "root" "GymAnything123!" \
    "SELECT Nationality, count(*) as cnt FROM Profiles GROUP BY Nationality")

# 2. Check User Existence & Roles
USERS_INFO=$(run_sql_json "root" "GymAnything123!" \
    "SELECT name, roles.name as roles FROM OUser WHERE name IN ['manager_eu', 'manager_na']")

# 3. Check Role Configuration
ROLE_INFO=$(run_sql_json "root" "GymAnything123!" \
    "SELECT name, mode, rules FROM ORole WHERE name = 'RegionalManager'")

# 4. FUNCTIONAL TEST: Check manager_eu view
# Queries the API *as* the new user
EU_VIEW_COUNT=$(run_sql_json "manager_eu" "management_access" \
    "SELECT COUNT(*) as cnt FROM Profiles")
    
EU_VIEW_SAMPLE=$(run_sql_json "manager_eu" "management_access" \
    "SELECT Name, Nationality FROM Profiles LIMIT 10")

# 5. FUNCTIONAL TEST: Check manager_na view
NA_VIEW_COUNT=$(run_sql_json "manager_na" "management_access" \
    "SELECT COUNT(*) as cnt FROM Profiles")

NA_VIEW_SAMPLE=$(run_sql_json "manager_na" "management_access" \
    "SELECT Name, Nationality FROM Profiles LIMIT 10")

# 6. Check _allowRead usage directly (Metadata check)
# We select the raw field to see if it contains RIDs
ALLOW_READ_CHECK=$(run_sql_json "root" "GymAnything123!" \
    "SELECT Name, Nationality, _allowRead FROM Profiles WHERE _allowRead IS NOT NULL LIMIT 20")

# Compile into single JSON using python
python3 -c "
import json, os, sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'root_counts': json.loads('''$ROOT_COUNTS'''),
    'users': json.loads('''$USERS_INFO'''),
    'role': json.loads('''$ROLE_INFO'''),
    'eu_view': {
        'count': json.loads('''$EU_VIEW_COUNT'''),
        'sample': json.loads('''$EU_VIEW_SAMPLE''')
    },
    'na_view': {
        'count': json.loads('''$NA_VIEW_COUNT'''),
        'sample': json.loads('''$NA_VIEW_SAMPLE''')
    },
    'allow_read_metadata': json.loads('''$ALLOW_READ_CHECK''')
}
with open('$EXPORT_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$EXPORT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="