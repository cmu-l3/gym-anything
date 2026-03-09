#!/bin/bash
# Setup script for advanced_correlation_rule_creation
# Seeds a multi-stage attack pattern (brute force + successful auth + privilege escalation)
# via real logger events. Agent must reconstruct the attack chain and create correlation rules.

echo "=== Setting up advanced_correlation_rule_creation ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Lesson 120: chmod +x export_result.sh inside VM (new files arrive without execute bit)
chmod +x /workspace/tasks/advanced_correlation_rule_creation/export_result.sh 2>/dev/null || true

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

# --- Step 3: Record baseline counts for alerts and correlation rules ---
INITIAL_ALERT_COUNT=0
ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
echo "$ALERT_TABLES" > /tmp/alert_table_names_corr
for TABLE in $ALERT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_ALERT_COUNT=$((INITIAL_ALERT_COUNT + COUNT))
    fi
done
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count_corr
echo "  Initial alert count: $INITIAL_ALERT_COUNT"

INITIAL_CORR_COUNT=0
CORR_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%corr%' OR tablename ILIKE '%rule%')" 2>/dev/null)
echo "$CORR_TABLES" > /tmp/corr_table_names
for TABLE in $CORR_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_CORR_COUNT=$((INITIAL_CORR_COUNT + COUNT))
    fi
done
echo "$INITIAL_CORR_COUNT" > /tmp/initial_corr_count
echo "  Initial correlation rule count: $INITIAL_CORR_COUNT"

# --- Step 4: Seed multi-stage attack events via logger (real OS events) ---
echo "Injecting multi-stage attack events..."

# Stage 1: Brute force — 22 failed logins for sysadmin from 203.0.113.42 (PRIMARY SIGNAL)
for i in $(seq 1 22); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=203.0.113.42 user=sysadmin"
    sleep 0.1
done
echo "  Stage 1 seeded: 22 failed logins for sysadmin from 203.0.113.42"

# Noise: 6 failed logins for admin from 198.51.100.77
for i in $(seq 1 6); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=198.51.100.77 user=admin"
    sleep 0.1
done
echo "  Noise seeded: 6 failed logins for admin from 198.51.100.77"

# Noise: 3 failed logins for root from 192.0.2.111
for i in $(seq 1 3); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=192.0.2.111 user=root"
    sleep 0.1
done
echo "  Noise seeded: 3 failed logins for root from 192.0.2.111"

# Stage 2: Successful authentication for sysadmin from same attacker IP
sleep 1
logger -p auth.info "pam_unix(sshd:session): session opened for user sysadmin by (uid=0)"
logger -p auth.info "Accepted password for sysadmin from 203.0.113.42 port 54231 ssh2"
echo "  Stage 2 seeded: successful login for sysadmin from 203.0.113.42"

# Stage 3: Privilege escalation (sudo usage after login)
sleep 1
logger -p auth.warning "sudo: sysadmin : TTY=pts/0 ; PWD=/home/sysadmin ; USER=root ; COMMAND=/bin/bash"
logger -p auth.warning "sudo: sysadmin : TTY=pts/0 ; PWD=/root ; USER=root ; COMMAND=/bin/cat /etc/shadow"
echo "  Stage 3 seeded: privilege escalation events for sysadmin"

sleep 5

# --- Step 5: Launch Firefox ---
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0" 2>/dev/null || true
sleep 3

# --- Step 6: Take screenshot ---
take_screenshot /tmp/advanced_correlation_rule_start.png
echo "=== Setup Complete ==="
echo "Multi-stage attack seeded:"
echo "  - 22 failed logins: sysadmin from 203.0.113.42 (PRIMARY ATTACKER)"
echo "  - 1 successful login: sysadmin from 203.0.113.42"
echo "  - 2 sudo escalation events by sysadmin"
echo "  - Noise: 6 + 3 failed logins from other IPs"
