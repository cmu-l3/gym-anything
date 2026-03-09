#!/bin/bash
# Setup script for forensic_export_and_scheduled_reporting
# Seeds real root user activity events and records baseline state.

echo "=== Setting up forensic_export_and_scheduled_reporting ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Lesson 120: chmod +x export_result.sh inside VM (new files arrive without execute bit)
chmod +x /workspace/tasks/forensic_export_and_scheduled_reporting/export_result.sh 2>/dev/null || true

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

# --- Step 3: Record baseline counts ---
# Alert tables
INITIAL_ALERT_COUNT=0
ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
echo "$ALERT_TABLES" > /tmp/alert_table_names_forensic
for TABLE in $ALERT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_ALERT_COUNT=$((INITIAL_ALERT_COUNT + COUNT))
    fi
done
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count_forensic

# Report/schedule tables
INITIAL_REPORT_COUNT=0
REPORT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%report%' OR tablename ILIKE '%schedule%')" 2>/dev/null)
echo "$REPORT_TABLES" > /tmp/report_table_names_forensic
for TABLE in $REPORT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        INITIAL_REPORT_COUNT=$((INITIAL_REPORT_COUNT + COUNT))
    fi
done
echo "$INITIAL_REPORT_COUNT" > /tmp/initial_report_count_forensic

echo "  Baseline: alerts=$INITIAL_ALERT_COUNT, reports=$INITIAL_REPORT_COUNT"

# --- Step 4: Seed real root activity events via logger ---
echo "Seeding root user activity events..."

# Root authentication events (real OS syslog events via logger)
logger -p auth.info "pam_unix(su:session): session opened for user root by ga(uid=1000)"
sleep 0.2
logger -p auth.warning "sudo: ga : TTY=pts/0 ; PWD=/home/ga ; USER=root ; COMMAND=/usr/bin/cat /etc/shadow"
sleep 0.2
logger -p auth.warning "sudo: ga : TTY=pts/0 ; PWD=/home/ga ; USER=root ; COMMAND=/bin/bash"
sleep 0.2
logger -p auth.info "pam_unix(sudo:session): session opened for user root by ga(uid=1000)"
sleep 0.2
logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.20.30.40 user=root"
sleep 0.2
logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.20.30.40 user=root"
sleep 0.2
logger -p auth.info "Accepted publickey for root from 192.168.1.50 port 52391 ssh2"
sleep 0.2
logger -p auth.info "pam_unix(sshd:session): session opened for user root by (uid=0)"
sleep 0.2
# Kernel events involving root
logger -p kern.warning "kernel: audit: type=1400 audit(1.0:1): apparmor=DENIED operation=exec profile=unconfined name=/bin/mount pid=1234 comm=root"
sleep 0.2
logger -p syslog.info "useradd[12345]: new user: name=tempaccount, UID=1500, GID=1000, by root"
echo "  Root activity events injected"

sleep 5

# --- Step 5: Launch Firefox ---
ensure_firefox_on_ela "/event/AppsHome.do#/search/index" 2>/dev/null || true
sleep 3

# --- Step 6: Screenshot ---
take_screenshot /tmp/forensic_export_start.png
echo "=== Setup Complete ==="
echo "Root activity events seeded. Agent must search, export, configure archival, schedule report, and create alert."
