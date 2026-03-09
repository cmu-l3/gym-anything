#!/bin/bash
echo "=== Setting up comprehensive_employee_onboarding ==="

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

# Remove any stale Robert Nakamura record
UID_OLD=$(timetrex_query "SELECT id FROM users WHERE employee_number='EM-ON001' AND deleted=0;" | head -1 | tr -d '[:space:]')
if [ -n "$UID_OLD" ]; then
    timetrex_query "UPDATE user_wage SET deleted=1 WHERE user_id=$UID_OLD;" > /dev/null 2>&1
    timetrex_query "UPDATE schedule SET deleted=1 WHERE user_id=$UID_OLD;" > /dev/null 2>&1
    timetrex_query "UPDATE users SET deleted=1 WHERE id=$UID_OLD;" > /dev/null 2>&1
fi

# Also clear any schedules on the target dates that might belong to other injected test users
timetrex_query "
UPDATE schedule SET deleted=1
WHERE date_stamp IN (
    '2026-03-09','2026-03-10','2026-03-11','2026-03-12','2026-03-13',
    '2026-03-16','2026-03-17','2026-03-18','2026-03-19','2026-03-20'
)
AND user_id IN (
    SELECT id FROM users WHERE employee_number='EM-ON001' AND deleted=0
);
" > /dev/null 2>&1

# Insert Robert Nakamura — no wage, no schedule (agent must add them)
timetrex_query "
INSERT INTO users (company_id, status_id, employee_number, first_name, last_name, user_name, password, created_date, deleted)
VALUES ($COMPANY_ID, 10, 'EM-ON001', 'Robert', 'Nakamura', 'robert.nakamura.on001', md5('changeme'), extract(epoch from now())::integer, 0)
ON CONFLICT DO NOTHING;
" > /dev/null 2>&1

echo "Inserted Robert Nakamura (EM-ON001) with no wage/schedule."

date +%s > /tmp/comprehensive_employee_onboarding_start_ts

# Ensure browser is open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

sleep 2
take_screenshot /tmp/comprehensive_employee_onboarding_start_screenshot.png

echo "=== Setup Complete ==="
