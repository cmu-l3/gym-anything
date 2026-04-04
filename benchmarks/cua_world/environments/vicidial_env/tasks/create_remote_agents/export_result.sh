#!/bin/bash
echo "=== Exporting create_remote_agents results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/initial_ra_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for the expected agents
# We use JSON_OBJECT if available, or manual construction for compatibility
# Vicidial MariaDB version might be old, so we use safe concat method or python formatting
echo "Querying database..."

# Helper to run query safely
db_query() {
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "$1" 2>/dev/null
}

# Get current total count
CURRENT_TOTAL_COUNT=$(db_query "SELECT COUNT(*) FROM vicidial_remote_agents")

# Get details for the specific agents we care about
# We fetch them line by line to ensure clean parsing
get_agent_json() {
    local user_start="$1"
    local data
    data=$(db_query "SELECT number_of_lines, conf_exten, status, campaign_id, external_extension, server_ip FROM vicidial_remote_agents WHERE user_start='$user_start' LIMIT 1")
    
    if [ -n "$data" ]; then
        # Parse tab separated values
        local lines=$(echo "$data" | awk '{print $1}')
        local conf=$(echo "$data" | awk '{print $2}')
        local status=$(echo "$data" | awk '{print $3}')
        local camp=$(echo "$data" | awk '{print $4}')
        local ext=$(echo "$data" | awk '{print $5}')
        local server=$(echo "$data" | awk '{print $6}')
        
        echo "{\"exists\": true, \"lines\": \"$lines\", \"conf_ext\": \"$conf\", \"status\": \"$status\", \"campaign\": \"$camp\", \"external_extension\": \"$ext\", \"server_ip\": \"$server\"}"
    else
        echo "{\"exists\": false}"
    fi
}

AGENT_7201_JSON=$(get_agent_json "7201")
AGENT_7202_JSON=$(get_agent_json "7202")
AGENT_7203_JSON=$(get_agent_json "7203")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_total_count": ${INITIAL_TOTAL_COUNT:-0},
    "current_total_count": ${CURRENT_TOTAL_COUNT:-0},
    "agents": {
        "7201": $AGENT_7201_JSON,
        "7202": $AGENT_7202_JSON,
        "7203": $AGENT_7203_JSON
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="