#!/bin/bash
echo "=== Exporting comprehensive_employee_onboarding Result ==="

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
take_screenshot /tmp/comprehensive_employee_onboarding_end_screenshot.png

# --- Wage check ---
WAGE=$(timetrex_query "
SELECT uw.wage
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-ON001' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

WAGE_DATE=$(timetrex_query "
SELECT uw.effective_date::text
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-ON001' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

echo "Wage=$WAGE EffectiveDate=$WAGE_DATE"

# --- Schedule checks (week 1: Mar 9-13, week 2: Mar 16-20) ---
check_schedule() {
    local DATE="$1"
    local EXPECTED_START="$2"
    local EXPECTED_END="$3"

    local ROW
    ROW=$(timetrex_query "
    SELECT s.start_time::text, s.end_time::text
    FROM schedule s
    JOIN users u ON s.user_id=u.id
    WHERE u.employee_number='EM-ON001' AND u.deleted=0 AND s.deleted=0
    AND s.date_stamp='$DATE'
    ORDER BY s.id DESC LIMIT 1;
    " | head -1 | tr -d ' ')

    local START_T END_T
    START_T=$(echo "$ROW" | cut -d'|' -f1)
    END_T=$(echo "$ROW" | cut -d'|' -f2)

    local FOUND=false START_OK=false END_OK=false
    if [ -n "$START_T" ]; then
        FOUND=true
        [ "${START_T:0:5}" = "$EXPECTED_START" ] && START_OK=true
        [ "${END_T:0:5}" = "$EXPECTED_END" ] && END_OK=true
    fi
    echo "{\"date\":\"$DATE\",\"found\":$FOUND,\"start_ok\":$START_OK,\"end_ok\":$END_OK,\"start_actual\":\"$START_T\",\"end_actual\":\"$END_T\"}"
}

W1_MON=$(check_schedule "2026-03-09" "07:00" "15:00")
W1_TUE=$(check_schedule "2026-03-10" "07:00" "15:00")
W1_WED=$(check_schedule "2026-03-11" "07:00" "15:00")
W1_THU=$(check_schedule "2026-03-12" "07:00" "15:00")
W1_FRI=$(check_schedule "2026-03-13" "07:00" "15:00")
W2_MON=$(check_schedule "2026-03-16" "07:00" "15:00")
W2_TUE=$(check_schedule "2026-03-17" "07:00" "15:00")
W2_WED=$(check_schedule "2026-03-18" "07:00" "15:00")
W2_THU=$(check_schedule "2026-03-19" "07:00" "15:00")
W2_FRI=$(check_schedule "2026-03-20" "07:00" "15:00")

RESULT_JSON=$(mktemp)
cat > "$RESULT_JSON" << EOF
{
    "wage": "${WAGE:-}",
    "wage_effective_date": "${WAGE_DATE:-}",
    "week1": [$W1_MON,$W1_TUE,$W1_WED,$W1_THU,$W1_FRI],
    "week2": [$W2_MON,$W2_TUE,$W2_WED,$W2_THU,$W2_FRI]
}
EOF

cp "$RESULT_JSON" /tmp/comprehensive_employee_onboarding_result.json
chmod 666 /tmp/comprehensive_employee_onboarding_result.json
rm -f "$RESULT_JSON"

echo "=== Export Complete ==="
