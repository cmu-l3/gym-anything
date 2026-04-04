#!/bin/bash
# Setup script for investigate_brute_force_incident
# Injects real syslog authentication failure events via logger (real OS events per Lesson 38)
# and records baseline ELA state.

echo "=== Setting up investigate_brute_force_incident ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Lesson 120: chmod +x export_result.sh inside VM (new files arrive without execute bit)
chmod +x /workspace/tasks/investigate_brute_force_incident/export_result.sh 2>/dev/null || true

# Fallback definitions in case sourcing fails
if ! type wait_for_eventlog_analyzer &>/dev/null; then
    wait_for_eventlog_analyzer() {
        local timeout="${1:-900}"
        local elapsed=0
        echo "Waiting for EventLog Analyzer to be ready..."
        while [ $elapsed -lt $timeout ]; do
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:8095/event/index.do 2>/dev/null | grep -qE "200|302|303"; then
                echo "EventLog Analyzer is ready"
                return 0
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        echo "WARNING: EventLog Analyzer may not be fully ready"
        return 1
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        # Lesson 123: use import -window root; scrot produces black images on compositor desktops
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

# --- Step 1: Wait for ELA to be ready ---
wait_for_eventlog_analyzer 900

# --- Step 2: Record task start timestamp (BEFORE seeding events) ---
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# --- Step 3: Record initial alert count baseline ---
# Use table discovery so we don't depend on knowing exact table names
INITIAL_ALERT_COUNT=0
if "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -c "\q" 2>/dev/null; then
    # Get all tables and look for alert-related ones
    ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
    for TABLE in $ALERT_TABLES; do
        TABLE=$(echo "$TABLE" | tr -d '|' | xargs)
        COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
        if echo "$COUNT" | grep -qE '^[0-9]+$'; then
            INITIAL_ALERT_COUNT=$((INITIAL_ALERT_COUNT + COUNT))
        fi
    done
fi
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count
echo "Initial alert count: $INITIAL_ALERT_COUNT"

# Also record which alert tables we found
if "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -c "\q" 2>/dev/null; then
    ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" > /tmp/alert_table_names 2>/dev/null
    echo "Alert tables found: $(cat /tmp/alert_table_names 2>/dev/null)"
fi

# --- Step 4: Inject real authentication failure events via logger ---
# These are REAL syslog events written by the OS via the logger utility.
# The events go into /var/log/auth.log and are forwarded to ELA via rsyslog on port 514.
# This is legitimate real-data generation per task_creation_notes Lesson 38.

echo "Injecting real authentication failure events..."

# Primary attack: 28 failed logins for 'serviceacct' from 192.168.10.45 (signal)
for i in $(seq 1 28); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=192.168.10.45 user=serviceacct"
    sleep 0.1
done
echo "  Injected 28 failed login events for serviceacct from 192.168.10.45"

# Noise source 1: 9 failed logins for 'backup' from 10.0.0.15
for i in $(seq 1 9); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.0.0.15 user=backup"
    sleep 0.1
done
echo "  Injected 9 failed login events for backup from 10.0.0.15"

# Noise source 2: 4 failed logins for 'admin' from 172.16.5.22
for i in $(seq 1 4); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=172.16.5.22 user=admin"
    sleep 0.1
done
echo "  Injected 4 failed login events for admin from 172.16.5.22"

# Wait for rsyslog to forward events to ELA
sleep 5

# --- Step 5: Ensure Firefox is open on EventLog Analyzer ---
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0" 2>/dev/null || true

# Give the browser time to load
sleep 3

# --- Step 6: Take initial screenshot ---
take_screenshot /tmp/investigate_brute_force_incident_start.png
echo "Start screenshot saved"

echo "=== Setup Complete ==="
echo "Seeded attack data:"
echo "  - 28 failed logins: user=serviceacct, source=192.168.10.45 (PRIMARY ATTACK)"
echo "  - 9 failed logins: user=backup, source=10.0.0.15 (noise)"
echo "  - 4 failed logins: user=admin, source=172.16.5.22 (noise)"
echo "Agent must identify the primary attack via ELA log search."
