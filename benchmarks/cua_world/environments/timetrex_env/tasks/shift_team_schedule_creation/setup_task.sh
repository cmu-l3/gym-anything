#!/bin/bash
echo "=== Setting up shift_team_schedule_creation ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type preflight_check &>/dev/null; then
    preflight_check() { ensure_docker_containers; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi
if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
        sleep 3
    }
fi
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | tr -d ' '
    }
fi

preflight_check

COMPANY_ID=$(timetrex_query "SELECT company_id FROM users WHERE deleted=0 AND status_id=10 LIMIT 1;" | head -1 | tr -d '[:space:]')
if [ -z "$COMPANY_ID" ]; then COMPANY_ID=1; fi
echo "Using company_id=$COMPANY_ID"

# Remove stale test employees and their schedules
for EMP_NUM in EM-SC001 EM-SC002 EM-SC003 EM-SC004; do
    UID_TO_DEL=$(timetrex_query "SELECT id FROM users WHERE employee_number='$EMP_NUM' AND deleted=0;" | head -1 | tr -d '[:space:]')
    if [ -n "$UID_TO_DEL" ]; then
        timetrex_query "UPDATE schedule SET deleted=1 WHERE user_id=$UID_TO_DEL;" > /dev/null 2>&1
        timetrex_query "UPDATE users SET deleted=1 WHERE id=$UID_TO_DEL;" > /dev/null 2>&1
    fi
done

# Delete any existing schedules for the target dates to avoid contamination
timetrex_query "UPDATE schedule SET deleted=1 WHERE date_stamp IN ('2026-03-09','2026-03-10','2026-03-11','2026-03-12','2026-03-13','2026-03-14') AND company_id=$COMPANY_ID;" > /dev/null 2>&1

# Insert the 4 employees (no pre-existing schedules)
for ROW in "EM-SC001:Emma:Johnson:emma.johnson.sc001" "EM-SC002:Ryan:Garcia:ryan.garcia.sc002" "EM-SC003:Sarah:Mitchell:sarah.mitchell.sc003" "EM-SC004:David:Kim:david.kim.sc004"; do
    EMP_NUM=$(echo "$ROW" | cut -d: -f1)
    FNAME=$(echo "$ROW" | cut -d: -f2)
    LNAME=$(echo "$ROW" | cut -d: -f3)
    UNAME=$(echo "$ROW" | cut -d: -f4)
    timetrex_query "
    INSERT INTO users (company_id, status_id, employee_number, first_name, last_name, user_name, password, created_date, deleted)
    VALUES ($COMPANY_ID, 10, '$EMP_NUM', '$FNAME', '$LNAME', '$UNAME', md5('changeme'), extract(epoch from now())::integer, 0)
    ON CONFLICT DO NOTHING;
    " > /dev/null 2>&1
done

echo "Inserted 4 shift employees."

# Record initial schedule count for the target dates as baseline
INITIAL=$(timetrex_query "
SELECT COUNT(*) FROM schedule s
JOIN users u ON s.user_id=u.id
WHERE u.employee_number IN ('EM-SC001','EM-SC002','EM-SC003','EM-SC004')
AND s.deleted=0
AND s.date_stamp IN ('2026-03-09','2026-03-10','2026-03-11','2026-03-12','2026-03-13','2026-03-14');
" | head -1 | tr -d '[:space:]')
echo "${INITIAL:-0}" > /tmp/shift_team_schedule_creation_initial_count

date +%s > /tmp/shift_team_schedule_creation_start_ts

# Ensure browser is open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

sleep 2
take_screenshot /tmp/shift_team_schedule_creation_start_screenshot.png

echo "=== Setup Complete ==="
