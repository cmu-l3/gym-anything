#!/bin/bash
# Setup script for configure_hipaa_compliance_monitoring
# Adds 3 healthcare-named syslog devices via ELA REST API,
# seeds PHI-access simulation events, and records baseline state.

echo "=== Setting up configure_hipaa_compliance_monitoring ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Lesson 120: chmod +x export_result.sh inside VM (new files arrive without execute bit)
chmod +x /workspace/tasks/configure_hipaa_compliance_monitoring/export_result.sh 2>/dev/null || true

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

# --- Step 3: Add healthcare syslog devices via ELA REST API ---
echo "Adding healthcare server devices to ELA..."

# Get authentication cookie
COOKIE_JAR="/tmp/ela_setup_cookies.txt"
rm -f "$COOKIE_JAR"

LOGIN_RESP=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "j_username=admin&j_password=admin&Submit=Login" \
    "http://localhost:8095/event/j_security_check" \
    -o /dev/null -w "%{http_code}" 2>/dev/null)
echo "  Login response code: $LOGIN_RESP"

# Add ehr-server-01
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"deviceName":"ehr-server-01","deviceIP":"10.10.1.10","deviceType":"Linux","syslogPort":514}' \
    "http://localhost:8095/event/api/v1/devices" > /tmp/device_add_1.json 2>/dev/null
echo "  Added ehr-server-01: $(cat /tmp/device_add_1.json 2>/dev/null | head -c 100)"

# Add pharmacy-db
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"deviceName":"pharmacy-db","deviceIP":"10.10.1.11","deviceType":"Linux","syslogPort":514}' \
    "http://localhost:8095/event/api/v1/devices" > /tmp/device_add_2.json 2>/dev/null
echo "  Added pharmacy-db: $(cat /tmp/device_add_2.json 2>/dev/null | head -c 100)"

# Add billing-system
curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"deviceName":"billing-system","deviceIP":"10.10.1.12","deviceType":"Linux","syslogPort":514}' \
    "http://localhost:8095/event/api/v1/devices" > /tmp/device_add_3.json 2>/dev/null
echo "  Added billing-system: $(cat /tmp/device_add_3.json 2>/dev/null | head -c 100)"

# Record initial device count
INITIAL_DEVICE_COUNT=$(curl -s -b "$COOKIE_JAR" \
    "http://localhost:8095/event/api/v1/devices" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('devices',d) if isinstance(d,dict) else d))" 2>/dev/null || echo "0")
echo "$INITIAL_DEVICE_COUNT" > /tmp/initial_device_count_hipaa
echo "  Current device count: $INITIAL_DEVICE_COUNT"

# --- Step 4: Record baseline alert count ---
INITIAL_ALERT_COUNT=0
ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
echo "$ALERT_TABLES" > /tmp/alert_table_names_hipaa
for TABLE in $ALERT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_ALERT_COUNT=$((INITIAL_ALERT_COUNT + COUNT))
    fi
done
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count_hipaa
echo "  Initial alert count: $INITIAL_ALERT_COUNT"

# --- Step 5: Seed real PHI access simulation events via logger ---
# These are real OS log events (Lesson 38: real system events are legitimate data)
echo "Seeding PHI access simulation events..."
for i in $(seq 1 5); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.10.1.10 user=phi_user"
    sleep 0.2
done
logger -p auth.info "pam_unix(su:session): session opened for user root by ga(uid=1000)"
logger -p daemon.info "EHR application: user phi_user accessed patient record ID 4892"
echo "  PHI simulation events injected"

sleep 3

# --- Step 6: Launch Firefox ---
ensure_firefox_on_ela "/event/AppsHome.do#/compliance" 2>/dev/null || true
sleep 3

# --- Step 7: Take screenshot ---
take_screenshot /tmp/configure_hipaa_compliance_start.png
echo "=== Setup Complete ==="
