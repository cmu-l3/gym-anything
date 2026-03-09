#!/bin/bash
echo "=== Exporting absence_request_bulk_processing Result ==="

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
take_screenshot /tmp/absence_request_bulk_processing_end_screenshot.png

# Fetch status_id for each employee's most recent request
# status_id: 10=Pending, 20=Approved, 30=Denied
get_request_status() {
    local EMP_NUM="$1"
    local DATE="$2"
    timetrex_query "
    SELECT r.status_id
    FROM request r
    JOIN users u ON r.user_id=u.id
    WHERE u.employee_number='$EMP_NUM' AND u.deleted=0 AND r.deleted=0
    AND r.start_date='$DATE'
    ORDER BY r.id DESC LIMIT 1;
    " | head -1 | tr -d '[:space:]'
}

ANDERSON_STATUS=$(get_request_status "EM-RQ001" "2026-03-16")
PETERSON_STATUS=$(get_request_status "EM-RQ002" "2026-03-16")
MARTINEZ_STATUS=$(get_request_status "EM-RQ003" "2026-03-19")
CHANG_STATUS=$(get_request_status "EM-RQ004" "2026-03-23")
BROWN_STATUS=$(get_request_status "EM-RQ005" "2026-03-24")

echo "Anderson=$ANDERSON_STATUS Peterson=$PETERSON_STATUS Martinez=$MARTINEZ_STATUS Chang=$CHANG_STATUS Brown=$BROWN_STATUS"

RESULT_JSON=$(mktemp)
cat > "$RESULT_JSON" << EOF
{
    "lisa_anderson_status": "${ANDERSON_STATUS:-10}",
    "tom_peterson_status": "${PETERSON_STATUS:-10}",
    "olivia_martinez_status": "${MARTINEZ_STATUS:-10}",
    "kevin_chang_status": "${CHANG_STATUS:-10}",
    "sandra_brown_status": "${BROWN_STATUS:-10}"
}
EOF

cp "$RESULT_JSON" /tmp/absence_request_bulk_processing_result.json
chmod 666 /tmp/absence_request_bulk_processing_result.json
rm -f "$RESULT_JSON"

echo "=== Export Complete ==="
