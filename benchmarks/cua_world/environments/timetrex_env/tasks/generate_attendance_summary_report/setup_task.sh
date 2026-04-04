#!/bin/bash
echo "=== Setting up generate_attendance_summary_report ==="

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

# Remove any stale output file from a previous run
rm -f /home/ga/Desktop/attendance_feb2026.csv 2>/dev/null || true
# Also clean up any auto-named downloads that might match
rm -f /home/ga/Downloads/attendance_feb2026.csv 2>/dev/null || true
rm -f /home/ga/Desktop/TimeSheet*.csv 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/generate_attendance_summary_report_start_ts

# Verify demo data has punch records in February 2026 (the demo data populates ~3 months back)
# If none exist for Feb 2026, inject minimal punch data for a couple of demo employees
FEB_PUNCH_COUNT=$(timetrex_query "
SELECT COUNT(*) FROM punch
WHERE time_stamp >= extract(epoch from '2026-02-01'::timestamp)::integer
AND time_stamp < extract(epoch from '2026-03-01'::timestamp)::integer
AND deleted=0;
" | head -1 | tr -d '[:space:]')

echo "Punch records in Feb 2026: ${FEB_PUNCH_COUNT:-0}"

if [ "${FEB_PUNCH_COUNT:-0}" -lt 2 ]; then
    echo "Injecting demo punch data for February 2026..."
    COMPANY_ID=$(timetrex_query "SELECT company_id FROM users WHERE deleted=0 AND status_id=10 LIMIT 1;" | head -1 | tr -d '[:space:]')
    if [ -z "$COMPANY_ID" ]; then COMPANY_ID=1; fi

    # Get first two active user IDs
    USERS=$(timetrex_query "SELECT id FROM users WHERE deleted=0 AND status_id=10 AND company_id=$COMPANY_ID ORDER BY id LIMIT 2;" | tr -d ' \n')

    UID1=$(echo "$USERS" | head -c 10 | tr -d '\n')
    UID1=$(timetrex_query "SELECT id FROM users WHERE deleted=0 AND status_id=10 AND company_id=$COMPANY_ID ORDER BY id LIMIT 1;" | head -1 | tr -d '[:space:]')
    UID2=$(timetrex_query "SELECT id FROM users WHERE deleted=0 AND status_id=10 AND company_id=$COMPANY_ID ORDER BY id OFFSET 1 LIMIT 1;" | head -1 | tr -d '[:space:]')

    if [ -n "$UID1" ] && [ -n "$UID2" ]; then
        # Feb 3, 2026: 09:00 in, 17:00 out for UID1
        T_IN1=$(date -d "2026-02-03 09:00:00" +%s 2>/dev/null || echo "1738580400")
        T_OUT1=$(date -d "2026-02-03 17:00:00" +%s 2>/dev/null || echo "1738609200")
        # Feb 3, 2026 for UID2
        T_IN2=$(date -d "2026-02-03 08:00:00" +%s 2>/dev/null || echo "1738576800")
        T_OUT2=$(date -d "2026-02-03 16:00:00" +%s 2>/dev/null || echo "1738605600")

        timetrex_query "
        DO \$\$
        DECLARE pc_id INTEGER;
        BEGIN
          INSERT INTO punch_control (user_id, date_stamp, company_id, created_date, deleted)
          VALUES ($UID1, '2026-02-03', $COMPANY_ID, extract(epoch from now())::integer, 0)
          RETURNING id INTO pc_id;
          INSERT INTO punch (punch_control_id, user_id, status_id, type_id, time_stamp, company_id, created_date, deleted)
          VALUES (pc_id, $UID1, 10, 10, $T_IN1, $COMPANY_ID, extract(epoch from now())::integer, 0);
          INSERT INTO punch (punch_control_id, user_id, status_id, type_id, time_stamp, company_id, created_date, deleted)
          VALUES (pc_id, $UID1, 20, 10, $T_OUT1, $COMPANY_ID, extract(epoch from now())::integer, 0);
        END;
        \$\$;
        " > /dev/null 2>&1

        timetrex_query "
        DO \$\$
        DECLARE pc_id INTEGER;
        BEGIN
          INSERT INTO punch_control (user_id, date_stamp, company_id, created_date, deleted)
          VALUES ($UID2, '2026-02-03', $COMPANY_ID, extract(epoch from now())::integer, 0)
          RETURNING id INTO pc_id;
          INSERT INTO punch (punch_control_id, user_id, status_id, type_id, time_stamp, company_id, created_date, deleted)
          VALUES (pc_id, $UID2, 10, 10, $T_IN2, $COMPANY_ID, extract(epoch from now())::integer, 0);
          INSERT INTO punch (punch_control_id, user_id, status_id, type_id, time_stamp, company_id, created_date, deleted)
          VALUES (pc_id, $UID2, 20, 10, $T_OUT2, $COMPANY_ID, extract(epoch from now())::integer, 0);
        END;
        \$\$;
        " > /dev/null 2>&1
        echo "Demo punch data injected."
    fi
fi

# Ensure browser is open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

sleep 2
take_screenshot /tmp/generate_attendance_summary_report_start_screenshot.png

echo "=== Setup Complete ==="
