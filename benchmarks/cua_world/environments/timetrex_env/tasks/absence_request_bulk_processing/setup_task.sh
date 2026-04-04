#!/bin/bash
echo "=== Setting up absence_request_bulk_processing ==="

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

# Get absence policy IDs for Vacation and Sick
VACATION_POLICY_ID=$(timetrex_query "SELECT id FROM absence_policy WHERE LOWER(name) LIKE '%vacation%' AND deleted=0 LIMIT 1;" | head -1 | tr -d '[:space:]')
SICK_POLICY_ID=$(timetrex_query "SELECT id FROM absence_policy WHERE LOWER(name) LIKE '%sick%' AND deleted=0 LIMIT 1;" | head -1 | tr -d '[:space:]')

# Fallback: use 10 for Vacation and 20 for Sick if not found
if [ -z "$VACATION_POLICY_ID" ]; then VACATION_POLICY_ID=10; fi
if [ -z "$SICK_POLICY_ID" ]; then SICK_POLICY_ID=20; fi

echo "Vacation policy id=$VACATION_POLICY_ID, Sick policy id=$SICK_POLICY_ID"

# Clean up stale test data
for EMP_NUM in EM-RQ001 EM-RQ002 EM-RQ003 EM-RQ004 EM-RQ005; do
    UID_TO_DEL=$(timetrex_query "SELECT id FROM users WHERE employee_number='$EMP_NUM' AND deleted=0;" | head -1 | tr -d '[:space:]')
    if [ -n "$UID_TO_DEL" ]; then
        timetrex_query "UPDATE request SET deleted=1 WHERE user_id=$UID_TO_DEL;" > /dev/null 2>&1
        timetrex_query "UPDATE users SET deleted=1 WHERE id=$UID_TO_DEL;" > /dev/null 2>&1
    fi
done

# Insert 5 employees and their pending absence requests
insert_employee_with_request() {
    local EMP_NUM="$1"
    local FNAME="$2"
    local LNAME="$3"
    local UNAME="$4"
    local POLICY_ID="$5"
    local START_DATE="$6"
    local END_DATE="$7"

    timetrex_query "
    DO \$\$
    DECLARE
      v_uid INTEGER;
    BEGIN
      INSERT INTO users (company_id, status_id, employee_number, first_name, last_name, user_name, password, created_date, deleted)
      VALUES ($COMPANY_ID, 10, '$EMP_NUM', '$FNAME', '$LNAME', '$UNAME', md5('changeme'), extract(epoch from now())::integer, 0)
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_uid;

      IF v_uid IS NULL THEN
        SELECT id INTO v_uid FROM users WHERE employee_number='$EMP_NUM' AND deleted=0;
      END IF;

      INSERT INTO request (user_id, type_id, status_id, date_stamp, start_date, end_date, company_id, created_date, deleted)
      VALUES (v_uid, $POLICY_ID, 10, '$START_DATE', '$START_DATE', '$END_DATE', $COMPANY_ID, extract(epoch from now())::integer, 0);
    END;
    \$\$;
    " > /dev/null 2>&1
}

# Lisa Anderson — 1-day Sick (approve per policy)
insert_employee_with_request "EM-RQ001" "Lisa" "Anderson" "lisa.anderson.rq001" "$SICK_POLICY_ID" "2026-03-16" "2026-03-16"

# Tom Peterson — 3-day Vacation (deny per policy: >=3 days)
insert_employee_with_request "EM-RQ002" "Tom" "Peterson" "tom.peterson.rq002" "$VACATION_POLICY_ID" "2026-03-16" "2026-03-18"

# Olivia Martinez — 2-day Vacation (approve per policy: <=2 days)
insert_employee_with_request "EM-RQ003" "Olivia" "Martinez" "olivia.martinez.rq003" "$VACATION_POLICY_ID" "2026-03-19" "2026-03-20"

# Kevin Chang — 5-day Vacation (deny per policy: >=3 days)
insert_employee_with_request "EM-RQ004" "Kevin" "Chang" "kevin.chang.rq004" "$VACATION_POLICY_ID" "2026-03-23" "2026-03-27"

# Sandra Brown — 1-day Sick (approve per policy)
insert_employee_with_request "EM-RQ005" "Sandra" "Brown" "sandra.brown.rq005" "$SICK_POLICY_ID" "2026-03-24" "2026-03-24"

echo "Inserted 5 employees with pending absence requests."

# Save policy IDs for use in export script
echo "$VACATION_POLICY_ID" > /tmp/absence_request_bulk_processing_vacation_pid
echo "$SICK_POLICY_ID" > /tmp/absence_request_bulk_processing_sick_pid

date +%s > /tmp/absence_request_bulk_processing_start_ts

# Ensure browser is open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

sleep 2
take_screenshot /tmp/absence_request_bulk_processing_start_screenshot.png

echo "=== Setup Complete ==="
