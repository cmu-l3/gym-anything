#!/bin/bash
# Setup script for Holiday Pay Audit Correction task
# Fixes login credentials, cleans target records, records baselines, launches browser

echo "=== Setting up Holiday Pay Audit Correction task ==="

# Source shared utilities safely
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions in case task_utils.sh is unavailable
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

# Ensure TimeTrex Docker containers are running
ensure_docker_containers

# ===== Phase 1: Fix login credentials =====
# The demo data generation may have failed during initial setup.
# Ensure demoadmin user can log in with password 'demo'.
echo "Fixing login credentials for demoadmin..."

# Compute correct password hash using TimeTrex v3 algorithm:
# hash('sha512', salt + company_id + user_id + password)
COMPANY_ID=$(timetrex_query "SELECT id FROM company LIMIT 1;" 2>/dev/null)
USER_ID=$(timetrex_query "SELECT id FROM users WHERE user_name='demoadmin' AND deleted=0 LIMIT 1;" 2>/dev/null)
SALT=$(docker exec timetrex-app grep -oP "salt\s*=\s*\K.*" /var/www/html/timetrex/timetrex.ini.php 2>/dev/null | tr -d '\r\n ')

if [ -n "$COMPANY_ID" ] && [ -n "$USER_ID" ] && [ -n "$SALT" ]; then
    PW_HASH="3:$(echo -n "${SALT}${COMPANY_ID}${USER_ID}demo" | sha512sum | awk '{print $1}')"
    docker exec timetrex-postgres psql -U timetrex -d timetrex -c "
        UPDATE users SET
            password='${PW_HASH}',
            password_updated_date=EXTRACT(EPOCH FROM NOW())::integer,
            last_login_date=EXTRACT(EPOCH FROM NOW())::integer
        WHERE user_name='demoadmin' AND deleted=0;
    " 2>/dev/null || true
    echo "Password hash set for demoadmin."
else
    echo "WARNING: Could not determine IDs for password reset. company=$COMPANY_ID user=$USER_ID salt=$SALT"
fi

# ===== Phase 2: Clean stale outputs from any prior runs =====
echo "Cleaning stale output files..."
rm -f /tmp/holiday_audit_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true
rm -f /tmp/initial_rh_ids.json 2>/dev/null || true
rm -f /tmp/initial_link_count.txt 2>/dev/null || true
rm -f /tmp/initial_paycode_count.txt 2>/dev/null || true
rm -f /tmp/initial_station_count.txt 2>/dev/null || true

# ===== Phase 3: Delete all target records to ensure clean slate =====
echo "Cleaning up pre-existing target records..."

# Soft-delete target recurring holidays
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "
UPDATE recurring_holiday SET deleted=1
WHERE name ILIKE '%New Year%'
   OR name ILIKE '%MLK%'
   OR name ILIKE '%Martin Luther King%'
   OR name ILIKE '%Presidents%';
" 2>/dev/null || true

# Delete associations for the target holiday policy
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "
DELETE FROM holiday_policy_recurring_holiday
WHERE holiday_policy_id IN (
    SELECT id FROM holiday_policy WHERE name ILIKE '%Standard Q1 Holidays%'
);
" 2>/dev/null || true

# Soft-delete the target holiday policy
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "
UPDATE holiday_policy SET deleted=1
WHERE name ILIKE '%Standard Q1 Holidays%';
" 2>/dev/null || true

# Soft-delete target pay codes
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "
UPDATE pay_code SET deleted=1
WHERE name IN ('Shift Differential', 'Holiday Premium');
" 2>/dev/null || true

# Soft-delete target station
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "
UPDATE station SET deleted=1
WHERE source LIKE '%10.0.75.10%';
" 2>/dev/null || true

# ===== Phase 4: Record task start timestamp (AFTER deletes, BEFORE baselines) =====
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start timestamp: $TASK_START"

# ===== Phase 5: Record initial baselines for anti-gaming verification =====
echo "Recording initial baselines..."

# Initial recurring holiday IDs
INITIAL_RH_IDS=$(timetrex_query "SELECT COALESCE(json_agg(id), '[]'::json) FROM recurring_holiday WHERE deleted=0;" 2>/dev/null)
if [ -z "$INITIAL_RH_IDS" ]; then INITIAL_RH_IDS="[]"; fi
echo "$INITIAL_RH_IDS" > /tmp/initial_rh_ids.json

# Initial policy link count (should be 0 since we deleted the target policy)
INITIAL_LINK_COUNT=$(timetrex_query "
SELECT COUNT(*)
FROM holiday_policy_recurring_holiday hprh
JOIN holiday_policy hp ON hprh.holiday_policy_id = hp.id
WHERE hp.name ILIKE '%Standard Q1 Holidays%' AND hp.deleted = 0;
" 2>/dev/null || echo "0")
echo "$INITIAL_LINK_COUNT" > /tmp/initial_link_count.txt

# Initial pay code count
INITIAL_PAYCODE_COUNT=$(timetrex_query "SELECT COUNT(*) FROM pay_code WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_PAYCODE_COUNT" > /tmp/initial_paycode_count.txt

# Initial station count
INITIAL_STATION_COUNT=$(timetrex_query "SELECT COUNT(*) FROM station WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_STATION_COUNT" > /tmp/initial_station_count.txt

echo "Baselines: rh_ids=$(cat /tmp/initial_rh_ids.json | wc -c)B, links=$INITIAL_LINK_COUNT, paycodes=$INITIAL_PAYCODE_COUNT, stations=$INITIAL_STATION_COUNT"

# ===== Phase 6: Launch Firefox on TimeTrex login page =====
# Kill any existing Firefox to get a clean session
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
sleep 8

# Maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Task Setup Complete ==="
echo "Task: Configure Q1 2026 holiday infrastructure, pay codes, and station."
echo "All target records have been cleaned. Agent must create everything from scratch."
echo "Login credentials: demoadmin / demo"
echo ""
