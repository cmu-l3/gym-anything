#!/bin/bash
# Export script for Holiday Pay Audit Correction task
# Queries PostgreSQL for all target entities and exports results as JSON

echo "=== Exporting Holiday Pay Audit Correction Result ==="

# Source shared utilities
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
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "$1" 2>/dev/null
    }
fi

# Ensure containers are running
ensure_docker_containers

# Final database accessibility check
if ! docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
    echo "FATAL: Database not accessible. Generating failure result."
    cat > /tmp/holiday_audit_result.json << EOF
{
    "error": "Docker containers not running or database inaccessible",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/holiday_audit_result.json 2>/dev/null || true
    exit 0
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load initial state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_RH_IDS=$(cat /tmp/initial_rh_ids.json 2>/dev/null || echo "[]")
INITIAL_LINK_COUNT=$(cat /tmp/initial_link_count.txt 2>/dev/null || echo "0")
INITIAL_PAYCODE_COUNT=$(cat /tmp/initial_paycode_count.txt 2>/dev/null || echo "0")
INITIAL_STATION_COUNT=$(cat /tmp/initial_station_count.txt 2>/dev/null || echo "0")

# ===== Query 1: Recurring Holidays =====
RECURRING_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'id', id,
    'name', name,
    'type_id', type_id,
    'month_int', month_int,
    'day_of_month', day_of_month,
    'created_date', created_date
)), '[]'::json)
FROM recurring_holiday
WHERE deleted = 0
  AND (name ILIKE '%New Year%'
    OR name ILIKE '%MLK%'
    OR name ILIKE '%Martin Luther King%'
    OR name ILIKE '%Presidents%');
")
if [ -z "$RECURRING_JSON" ]; then RECURRING_JSON="[]"; fi

# ===== Query 2: Holiday Policy =====
POLICY_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'id', id,
    'name', name,
    'created_date', created_date
)), '[]'::json)
FROM holiday_policy
WHERE deleted = 0
  AND name ILIKE '%Standard Q1 Holidays%';
")
if [ -z "$POLICY_JSON" ]; then POLICY_JSON="[]"; fi

# ===== Query 3: Policy-Recurring Holiday Links =====
LINKS_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'policy_name', hp.name,
    'holiday_name', rh.name
)), '[]'::json)
FROM holiday_policy_recurring_holiday hprh
JOIN holiday_policy hp ON hprh.holiday_policy_id = hp.id
JOIN recurring_holiday rh ON hprh.recurring_holiday_id = rh.id
WHERE hp.deleted = 0 AND rh.deleted = 0
  AND hp.name ILIKE '%Standard Q1 Holidays%';
")
if [ -z "$LINKS_JSON" ]; then LINKS_JSON="[]"; fi

# ===== Query 4: Pay Codes =====
PAYCODE_JSON=$(timetrex_query "
SELECT COALESCE(json_agg(json_build_object(
    'id', id,
    'name', name,
    'type_id', type_id,
    'created_date', created_date
)), '[]'::json)
FROM pay_code
WHERE deleted = 0
  AND name IN ('Shift Differential', 'Holiday Premium');
")
if [ -z "$PAYCODE_JSON" ]; then PAYCODE_JSON="[]"; fi

# ===== Query 5: Station =====
STATION_FOUND="false"
STATION_DESC=""
STATION_SOURCE=""
STATION_TYPE=""
STATION_CREATED=""

STATION_EXISTS=$(timetrex_query "SELECT COUNT(*) FROM station WHERE source LIKE '%10.0.75.10%' AND deleted=0" 2>/dev/null || echo "0")
if [ "$STATION_EXISTS" -gt 0 ] 2>/dev/null; then
    STATION_FOUND="true"
    STATION_DESC=$(timetrex_query "SELECT description FROM station WHERE source LIKE '%10.0.75.10%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" 2>/dev/null | tr -d '\n\r')
    STATION_SOURCE=$(timetrex_query "SELECT source FROM station WHERE source LIKE '%10.0.75.10%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" 2>/dev/null | tr -d '\n\r')
    STATION_TYPE=$(timetrex_query "SELECT type_id FROM station WHERE source LIKE '%10.0.75.10%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" 2>/dev/null | tr -d '\n\r')
    STATION_CREATED=$(timetrex_query "SELECT created_date FROM station WHERE source LIKE '%10.0.75.10%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" 2>/dev/null | tr -d '\n\r')
fi

# Escape strings for JSON
STATION_DESC_ESC=$(echo "$STATION_DESC" | sed 's/"/\\"/g' | tr -d '\n\r')

# Current counts
CURRENT_PAYCODE_COUNT=$(timetrex_query "SELECT COUNT(*) FROM pay_code WHERE deleted=0;" 2>/dev/null || echo "0")
CURRENT_STATION_COUNT=$(timetrex_query "SELECT COUNT(*) FROM station WHERE deleted=0;" 2>/dev/null || echo "0")

# ===== Assemble final result JSON =====
TEMP_JSON=$(mktemp /tmp/holiday_audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_rh_ids": $INITIAL_RH_IDS,
    "initial_link_count": ${INITIAL_LINK_COUNT:-0},
    "initial_paycode_count": ${INITIAL_PAYCODE_COUNT:-0},
    "initial_station_count": ${INITIAL_STATION_COUNT:-0},
    "recurring_holidays": $RECURRING_JSON,
    "policy": $POLICY_JSON,
    "policy_links": $LINKS_JSON,
    "pay_codes": $PAYCODE_JSON,
    "current_paycode_count": ${CURRENT_PAYCODE_COUNT:-0},
    "current_station_count": ${CURRENT_STATION_COUNT:-0},
    "station": {
        "found": $STATION_FOUND,
        "description": "$STATION_DESC_ESC",
        "source": "$STATION_SOURCE",
        "type_id": "$STATION_TYPE",
        "created_date": ${STATION_CREATED:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/holiday_audit_result.json 2>/dev/null || sudo rm -f /tmp/holiday_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/holiday_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/holiday_audit_result.json
chmod 666 /tmp/holiday_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/holiday_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "JSON result exported to /tmp/holiday_audit_result.json:"
cat /tmp/holiday_audit_result.json
echo ""
echo "=== Export Complete ==="
