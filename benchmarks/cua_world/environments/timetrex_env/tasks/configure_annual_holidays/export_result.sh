#!/bin/bash
echo "=== Exporting Configure Annual Holidays Result ==="

# Source shared utilities safely
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions
if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
        sleep 3
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Ensure containers are running before querying DB
ensure_docker_containers

take_screenshot /tmp/task_end_screenshot.png

# Query the database for all currently active holidays and output as JSON array
FINAL_HOLIDAYS=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) FROM (SELECT id, name, CAST(date_stamp AS DATE)::text as h_date FROM holiday WHERE deleted=0) t;" 2>/dev/null)

if [ -z "$FINAL_HOLIDAYS" ]; then
    FINAL_HOLIDAYS="[]"
fi

# Read initial state and start time
INITIAL_HOLIDAYS=$(cat /tmp/initial_holiday_ids.json 2>/dev/null || echo "[]")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Compile JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "initial_holiday_ids": $INITIAL_HOLIDAYS,
    "final_holidays": $FINAL_HOLIDAYS,
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely (prevents permission issues across users)
cp "$TEMP_JSON" /tmp/configure_annual_holidays_result.json
chmod 666 /tmp/configure_annual_holidays_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="