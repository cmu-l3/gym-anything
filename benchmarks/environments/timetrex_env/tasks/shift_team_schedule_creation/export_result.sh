#!/bin/bash
echo "=== Exporting shift_team_schedule_creation Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | tr -d ' '
    }
fi
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

ensure_docker_containers
take_screenshot /tmp/shift_team_schedule_creation_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/shift_team_schedule_creation_initial_count 2>/dev/null || echo "0")

# Count total schedules created for each of the 4 employees across the target dates
TOTAL=$(timetrex_query "
SELECT COUNT(*) FROM schedule s
JOIN users u ON s.user_id=u.id
WHERE u.employee_number IN ('EM-SC001','EM-SC002','EM-SC003','EM-SC004')
AND s.deleted=0
AND s.date_stamp IN ('2026-03-09','2026-03-10','2026-03-11','2026-03-12','2026-03-13','2026-03-14');
" | head -1 | tr -d '[:space:]')
TOTAL=${TOTAL:-0}

# Per-employee per-date schedule check — emit one row per expected entry
# Team A: EM-SC001, EM-SC002 on 2026-03-09, 2026-03-11, 2026-03-13 (06:00–14:00)
# Team B: EM-SC003, EM-SC004 on 2026-03-10, 2026-03-12, 2026-03-14 (14:00–22:00)

build_schedule_json() {
    local EMP_NUM="$1"
    local DATE="$2"
    local EXPECTED_START="$3"
    local EXPECTED_END="$4"

    local ROW
    ROW=$(timetrex_query "
    SELECT s.start_time::text, s.end_time::text
    FROM schedule s
    JOIN users u ON s.user_id=u.id
    WHERE u.employee_number='$EMP_NUM' AND s.date_stamp='$DATE' AND s.deleted=0
    ORDER BY s.id DESC LIMIT 1;
    " | head -1 | tr -d ' ')

    local START_T END_T
    START_T=$(echo "$ROW" | cut -d'|' -f1)
    END_T=$(echo "$ROW" | cut -d'|' -f2)

    local FOUND=false
    local START_OK=false
    local END_OK=false

    if [ -n "$START_T" ]; then
        FOUND=true
        # Compare first 5 chars (HH:MM)
        [ "${START_T:0:5}" = "$EXPECTED_START" ] && START_OK=true
        [ "${END_T:0:5}" = "$EXPECTED_END" ] && END_OK=true
    fi

    echo "{\"emp\":\"$EMP_NUM\",\"date\":\"$DATE\",\"found\":$FOUND,\"start_ok\":$START_OK,\"end_ok\":$END_OK,\"start_actual\":\"$START_T\",\"end_actual\":\"$END_T\"}"
}

# Build JSON entries for all 12 expected schedule entries
SC001_09=$(build_schedule_json "EM-SC001" "2026-03-09" "06:00" "14:00")
SC001_11=$(build_schedule_json "EM-SC001" "2026-03-11" "06:00" "14:00")
SC001_13=$(build_schedule_json "EM-SC001" "2026-03-13" "06:00" "14:00")
SC002_09=$(build_schedule_json "EM-SC002" "2026-03-09" "06:00" "14:00")
SC002_11=$(build_schedule_json "EM-SC002" "2026-03-11" "06:00" "14:00")
SC002_13=$(build_schedule_json "EM-SC002" "2026-03-13" "06:00" "14:00")
SC003_10=$(build_schedule_json "EM-SC003" "2026-03-10" "14:00" "22:00")
SC003_12=$(build_schedule_json "EM-SC003" "2026-03-12" "14:00" "22:00")
SC003_14=$(build_schedule_json "EM-SC003" "2026-03-14" "14:00" "22:00")
SC004_10=$(build_schedule_json "EM-SC004" "2026-03-10" "14:00" "22:00")
SC004_12=$(build_schedule_json "EM-SC004" "2026-03-12" "14:00" "22:00")
SC004_14=$(build_schedule_json "EM-SC004" "2026-03-14" "14:00" "22:00")

RESULT_JSON=$(mktemp)
cat > "$RESULT_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "total_schedules": $TOTAL,
    "entries": [
        $SC001_09,
        $SC001_11,
        $SC001_13,
        $SC002_09,
        $SC002_11,
        $SC002_13,
        $SC003_10,
        $SC003_12,
        $SC003_14,
        $SC004_10,
        $SC004_12,
        $SC004_14
    ]
}
EOF

cp "$RESULT_JSON" /tmp/shift_team_schedule_creation_result.json
chmod 666 /tmp/shift_team_schedule_creation_result.json
rm -f "$RESULT_JSON"

echo "Total schedules created: $TOTAL"
echo "=== Export Complete ==="
