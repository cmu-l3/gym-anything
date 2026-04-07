#!/bin/bash
echo "=== Exporting reporting_chain_reconfig task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get final reporting managers from the database
EMP002_MGR=$(sentrifugo_db_query "SELECT reporting_manager FROM main_employees_summary WHERE user_id=(SELECT id FROM main_users WHERE employeeId='EMP002' LIMIT 1);" | tr -d '[:space:]')
EMP006_MGR=$(sentrifugo_db_query "SELECT reporting_manager FROM main_employees_summary WHERE user_id=(SELECT id FROM main_users WHERE employeeId='EMP006' LIMIT 1);" | tr -d '[:space:]')
EMP010_MGR=$(sentrifugo_db_query "SELECT reporting_manager FROM main_employees_summary WHERE user_id=(SELECT id FROM main_users WHERE employeeId='EMP010' LIMIT 1);" | tr -d '[:space:]')
EMP012_MGR=$(sentrifugo_db_query "SELECT reporting_manager FROM main_employees_summary WHERE user_id=(SELECT id FROM main_users WHERE employeeId='EMP012' LIMIT 1);" | tr -d '[:space:]')
EMP014_MGR=$(sentrifugo_db_query "SELECT reporting_manager FROM main_employees_summary WHERE user_id=(SELECT id FROM main_users WHERE employeeId='EMP014' LIMIT 1);" | tr -d '[:space:]')

# Get expected target managers IDs based on the provided names
JESSICA_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Jessica' AND lastname='Liu' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
CHRISTOPHER_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Christopher' AND lastname='Lee' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
THOMAS_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Thomas' AND lastname='Wright' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
AMANDA_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Amanda' AND lastname='Torres' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
DAVID_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='David' AND lastname='Kim' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')

# Export state to JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "actual": {
        "EMP002": "${EMP002_MGR:-}",
        "EMP006": "${EMP006_MGR:-}",
        "EMP010": "${EMP010_MGR:-}",
        "EMP012": "${EMP012_MGR:-}",
        "EMP014": "${EMP014_MGR:-}"
    },
    "expected": {
        "EMP002": "${JESSICA_ID:-}",
        "EMP006": "${CHRISTOPHER_ID:-}",
        "EMP010": "${THOMAS_ID:-}",
        "EMP012": "${AMANDA_ID:-}",
        "EMP014": "${DAVID_ID:-}"
    },
    "initial": $(cat /tmp/initial_reporting_managers.json 2>/dev/null || echo "{}"),
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end": $(date +%s)
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="