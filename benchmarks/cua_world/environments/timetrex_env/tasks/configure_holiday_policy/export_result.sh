#!/bin/bash
# Export script for Configure Holiday Policy task
# Queries PostgreSQL for created policies and holidays, returning JSON for the verifier

echo "=== Exporting Configure Holiday Policy Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback queries
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
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "$1" 2>/dev/null
    }
fi

# Ensure containers are running
ensure_docker_containers

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch JSON representations using PostgreSQL's json_agg (robust parsing)
# Query matching recurring holidays
HOLIDAYS_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'id', id,
    'name', name,
    'type_id', type_id,
    'month', month,
    'day_of_month', day_of_month,
    'created_date', created_date
)), '[]'::json)
FROM recurring_holiday 
WHERE deleted = 0 
  AND (name ILIKE '%New Year%' OR name ILIKE '%Independence%' OR name ILIKE '%Christmas%');
")

# Query matching holiday policy
POLICY_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'id', id,
    'name', name,
    'created_date', created_date
)), '[]'::json)
FROM holiday_policy 
WHERE deleted = 0 
  AND name ILIKE '%2026 Standard Holidays%';
")

# Query associations specifically for the target policy
ASSOC_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'policy_name', hp.name,
    'holiday_name', rh.name
)), '[]'::json)
FROM holiday_policy_recurring_holiday hprh
JOIN holiday_policy hp ON hprh.holiday_policy_id = hp.id
JOIN recurring_holiday rh ON hprh.recurring_holiday_id = rh.id
WHERE hp.deleted = 0 AND rh.deleted = 0 
  AND hp.name ILIKE '%2026 Standard Holidays%';
")

# Provide safe fallbacks if the queries failed to return proper arrays
if [ -z "$HOLIDAYS_JSON" ]; then HOLIDAYS_JSON="[]"; fi
if [ -z "$POLICY_JSON" ]; then POLICY_JSON="[]"; fi
if [ -z "$ASSOC_JSON" ]; then ASSOC_JSON="[]"; fi

# Assemble the final result JSON
TEMP_JSON=$(mktemp /tmp/configure_holiday_policy.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "holidays": $HOLIDAYS_JSON,
    "policies": $POLICY_JSON,
    "associations": $ASSOC_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/configure_holiday_policy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_holiday_policy_result.json
chmod 666 /tmp/configure_holiday_policy_result.json
rm -f "$TEMP_JSON"

echo "JSON result exported successfully:"
cat /tmp/configure_holiday_policy_result.json
echo ""
echo "=== Export Complete ==="