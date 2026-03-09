#!/bin/bash
echo "=== Exporting payroll_wage_audit_correction Result ==="

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

take_screenshot /tmp/payroll_wage_audit_correction_end_screenshot.png

# Query wage for each employee — take the most recent effective_date row
CHEN_WAGE=$(timetrex_query "
SELECT uw.wage
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-W001' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

CHEN_DATE=$(timetrex_query "
SELECT uw.effective_date::text
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-W001' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

WILLIAMS_WAGE=$(timetrex_query "
SELECT uw.wage
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-W002' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

WILLIAMS_DATE=$(timetrex_query "
SELECT uw.effective_date::text
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-W002' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

NGUYEN_WAGE=$(timetrex_query "
SELECT uw.wage
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-W003' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

NGUYEN_DATE=$(timetrex_query "
SELECT uw.effective_date::text
FROM user_wage uw
JOIN users u ON uw.user_id=u.id
WHERE u.employee_number='EM-W003' AND u.deleted=0 AND uw.deleted=0
ORDER BY uw.effective_date DESC
LIMIT 1;
" | head -1 | tr -d '[:space:]')

echo "Victoria Chen wage=$CHEN_WAGE date=$CHEN_DATE"
echo "Marcus Williams wage=$WILLIAMS_WAGE date=$WILLIAMS_DATE"
echo "Patricia Nguyen wage=$NGUYEN_WAGE date=$NGUYEN_DATE"

RESULT_JSON=$(mktemp)
cat > "$RESULT_JSON" << EOF
{
    "victoria_chen_wage": "$CHEN_WAGE",
    "victoria_chen_effective_date": "$CHEN_DATE",
    "marcus_williams_wage": "$WILLIAMS_WAGE",
    "marcus_williams_effective_date": "$WILLIAMS_DATE",
    "patricia_nguyen_wage": "$NGUYEN_WAGE",
    "patricia_nguyen_effective_date": "$NGUYEN_DATE"
}
EOF

cp "$RESULT_JSON" /tmp/payroll_wage_audit_correction_result.json
chmod 666 /tmp/payroll_wage_audit_correction_result.json
rm -f "$RESULT_JSON"

echo "=== Export Complete ==="
