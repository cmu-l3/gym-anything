#!/bin/bash
# Setup script for siem_hardening_and_user_audit
# Creates over-privileged technician accounts and misconfigured alert profiles via ELA API.
# Agent must identify and remediate these.

echo "=== Setting up siem_hardening_and_user_audit ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Lesson 120: chmod +x export_result.sh inside VM (new files arrive without execute bit)
chmod +x /workspace/tasks/siem_hardening_and_user_audit/export_result.sh 2>/dev/null || true

if ! type wait_for_eventlog_analyzer &>/dev/null; then
    wait_for_eventlog_analyzer() {
        local timeout="${1:-900}"
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:8095/event/index.do 2>/dev/null | grep -qE "200|302|303"; then
                return 0
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        return 1
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        # Lesson 123: use import -window root; scrot produces black images on compositor desktops
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

# --- Step 1: Wait for ELA ---
wait_for_eventlog_analyzer 900

# --- Step 2: Record task start timestamp ---
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# --- Step 3: Get auth cookie ---
COOKIE_JAR="/tmp/ela_hardening_cookies.txt"
rm -f "$COOKIE_JAR"
LOGIN_CODE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "j_username=admin&j_password=admin&Submit=Login" \
    "http://localhost:8095/event/j_security_check" \
    -o /dev/null -w "%{http_code}" 2>/dev/null)
echo "  Login: $LOGIN_CODE"

# --- Step 4: Create over-privileged technician accounts ---
echo "Creating over-privileged technician accounts..."

# Create contractor01 with Administrator role
RESP1=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"username":"contractor01","fullName":"External Contractor","email":"contractor01@external.com","password":"Contractor@123","role":"Administrator"}' \
    "http://localhost:8095/event/api/v1/technicians" 2>/dev/null)
echo "  contractor01: ${RESP1:0:100}"

# Create it-support with Administrator role
RESP2=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"username":"it-support","fullName":"IT Support Team","email":"itsupport@company.local","password":"Support@123","role":"Administrator"}' \
    "http://localhost:8095/event/api/v1/technicians" 2>/dev/null)
echo "  it-support: ${RESP2:0:100}"

# --- Step 5: Create misconfigured alert profiles (Warning severity, should be Critical) ---
echo "Creating misconfigured alert profiles..."

# SSH Brute Force alert set to Warning (should be Critical)
RESP3=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"alertName":"SSH Brute Force - Warning","severity":"Warning","threshold":5,"timeWindow":5,"description":"SSH brute force detection - incorrectly configured as Warning"}' \
    "http://localhost:8095/event/api/v1/alerts" 2>/dev/null)
echo "  SSH Brute Force alert: ${RESP3:0:100}"

# Failed Auth Monitor set to Warning
RESP4=$(curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"alertName":"Failed Auth Monitor","severity":"Warning","threshold":3,"timeWindow":10,"description":"Authentication failure monitoring - needs Critical severity"}' \
    "http://localhost:8095/event/api/v1/alerts" 2>/dev/null)
echo "  Failed Auth Monitor: ${RESP4:0:100}"

# --- Step 6: Record baseline state ---
# Technician count
INITIAL_TECH_COUNT=0
TECH_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%tech%' OR tablename ILIKE '%user%' OR tablename ILIKE '%operator%')" 2>/dev/null)
echo "$TECH_TABLES" > /tmp/tech_table_names
for TABLE in $TECH_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_TECH_COUNT=$((INITIAL_TECH_COUNT + COUNT))
    fi
done
echo "$INITIAL_TECH_COUNT" > /tmp/initial_tech_count

# Alert count
INITIAL_ALERT_COUNT=0
ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
echo "$ALERT_TABLES" > /tmp/alert_table_names_hardening
for TABLE in $ALERT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_ALERT_COUNT=$((INITIAL_ALERT_COUNT + COUNT))
    fi
done
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count_hardening
echo "  Baseline: technicians=$INITIAL_TECH_COUNT, alerts=$INITIAL_ALERT_COUNT"

# --- Step 7: Launch Firefox ---
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0" 2>/dev/null || true
sleep 3

# --- Step 8: Screenshot ---
take_screenshot /tmp/siem_hardening_start.png
echo "=== Setup Complete ==="
echo "Created: contractor01 (Admin), it-support (Admin)"
echo "Created: 'SSH Brute Force - Warning' alert (Warning severity)"
echo "Created: 'Failed Auth Monitor' alert (Warning severity)"
echo "Agent must: downgrade accounts, create soc-analyst-02, fix alert severities, write report"
