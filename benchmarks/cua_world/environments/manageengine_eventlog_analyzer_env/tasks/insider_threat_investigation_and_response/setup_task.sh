#!/bin/bash
# Setup script for insider_threat_investigation_and_response
# Injects a multi-phase attack via real syslog events:
#   Phase 1: 35 credential stuffing failures against svc_dataops from 10.55.3.88
#   Phase 2: Successful login for svc_dataops from 10.55.3.88
#   Phase 3: 18 credential stuffing failures against svc_reporting from 10.55.3.88
#   Phase 4: Successful login for svc_reporting from 10.55.3.88
#   Phase 5: Privilege escalation by svc_dataops (sudo to root, DB query)
#   Noise: Normal logins from legitimate IPs

echo "=== Setting up insider_threat_investigation_and_response ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure export_result.sh is executable inside VM
chmod +x /workspace/tasks/insider_threat_investigation_and_response/export_result.sh 2>/dev/null || true

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
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

# --- Step 1: Wait for EventLog Analyzer ---
wait_for_eventlog_analyzer 900

# --- Step 2: Delete stale output files BEFORE recording timestamp ---
rm -f /home/ga/Desktop/insider_threat_report.txt 2>/dev/null || true
rm -f /home/ga/Desktop/insider_threat_evidence.pdf 2>/dev/null || true

# --- Step 3: Record task start timestamp ---
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# --- Step 4: Record baseline alert count ---
INITIAL_ALERT_COUNT=0
if "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -c "\q" 2>/dev/null; then
    ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
    echo "$ALERT_TABLES" > /tmp/alert_table_names_insider
    for TABLE in $ALERT_TABLES; do
        TABLE=$(echo "$TABLE" | tr -d '|' | xargs)
        [ -z "$TABLE" ] && continue
        COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
        if echo "$COUNT" | grep -qE '^[0-9]+$'; then
            INITIAL_ALERT_COUNT=$((INITIAL_ALERT_COUNT + COUNT))
        fi
    done
fi
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count_insider
echo "Initial alert count: $INITIAL_ALERT_COUNT"

# --- Step 5: Record baseline incident count via API ---
INITIAL_INCIDENT_COUNT=0
# Try API first
if type ela_api_call &>/dev/null; then
    INCIDENTS_RAW=$(ela_api_call "/event/api/v2/incidents" "GET" 2>/dev/null)
    INITIAL_INCIDENT_COUNT=$(echo "$INCIDENTS_RAW" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    incidents = data.get('incidents', data.get('data', []))
    print(len(incidents))
except:
    print('0')
" 2>/dev/null || echo "0")
fi
echo "$INITIAL_INCIDENT_COUNT" > /tmp/initial_incident_count_insider
echo "Initial incident count: $INITIAL_INCIDENT_COUNT"

# --- Step 6: Inject multi-phase attack events via logger ---
# These are REAL syslog events via the OS logger utility.
# Events go into /var/log/auth.log and are forwarded to ELA via rsyslog on port 514.

echo "Injecting multi-phase insider threat attack events..."

# Phase 1: Credential stuffing against svc_dataops — 35 failures from 10.55.3.88
echo "  Phase 1: 35 failed logins for svc_dataops from 10.55.3.88"
for i in $(seq 1 35); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.55.3.88 user=svc_dataops"
    sleep 0.15
done

# Phase 2: Successful login for svc_dataops
echo "  Phase 2: Successful login for svc_dataops from 10.55.3.88"
logger -p auth.info -t sshd "Accepted password for svc_dataops from 10.55.3.88 port 42222 ssh2"
logger -p auth.info -t sshd "pam_unix(sshd:session): session opened for user svc_dataops(uid=1050) by svc_dataops(uid=0)"
sleep 1

# Phase 3: Credential stuffing against svc_reporting — 18 failures from same IP
echo "  Phase 3: 18 failed logins for svc_reporting from 10.55.3.88"
for i in $(seq 1 18); do
    logger -p auth.warning "pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.55.3.88 user=svc_reporting"
    sleep 0.15
done

# Phase 4: Successful login for svc_reporting
echo "  Phase 4: Successful login for svc_reporting from 10.55.3.88"
logger -p auth.info -t sshd "Accepted password for svc_reporting from 10.55.3.88 port 42333 ssh2"
logger -p auth.info -t sshd "pam_unix(sshd:session): session opened for user svc_reporting(uid=1051) by svc_reporting(uid=0)"
sleep 1

# Phase 5: Privilege escalation by svc_dataops
echo "  Phase 5: Privilege escalation events for svc_dataops"
logger -p auth.info -t sudo "svc_dataops : TTY=pts/2 ; PWD=/home/svc_dataops ; USER=root ; COMMAND=/bin/bash"
sleep 0.5
logger -p auth.info -t sudo "svc_dataops : TTY=pts/2 ; PWD=/root ; USER=root ; COMMAND=/usr/bin/psql -h localhost -d production_db -c SELECT * FROM customer_pii"
sleep 0.5

# Noise: Normal logins from legitimate users/IPs (realism)
echo "  Noise: Normal activity from legitimate users"
logger -p auth.info -t sshd "Accepted publickey for ga from 192.168.1.1 port 22 ssh2"
logger -p auth.info -t sshd "Accepted publickey for admin from 192.168.1.1 port 22 ssh2"
logger -p auth.info -t sshd "Accepted publickey for webadmin from 10.0.0.1 port 22 ssh2"
logger -p auth.info -t sudo "ga : TTY=pts/0 ; PWD=/home/ga ; USER=root ; COMMAND=/usr/bin/apt update"

echo "Injection complete: 63 total events"

# --- Step 7: Wait for rsyslog forwarding and ELA indexing ---
echo "Waiting for ELA to index injected events..."
sleep 15

# --- Step 8: Ensure Firefox is open on ELA Search page ---
# Start agent on Search page — natural starting point for investigation
ensure_firefox_on_ela "/event/AppsHome.do#/search/index" 2>/dev/null || true
sleep 3

# --- Step 9: Take initial screenshot ---
take_screenshot /tmp/insider_threat_investigation_start.png
echo "Start screenshot saved"

echo "=== Setup Complete ==="
echo "Seeded insider threat attack data:"
echo "  - 35 failed logins: user=svc_dataops, source=10.55.3.88 (PRIMARY ATTACK)"
echo "  - 1 successful login: user=svc_dataops, source=10.55.3.88"
echo "  - 18 failed logins: user=svc_reporting, source=10.55.3.88 (LATERAL MOVEMENT)"
echo "  - 1 successful login: user=svc_reporting, source=10.55.3.88"
echo "  - 2 privilege escalation events: svc_dataops -> root (sudo bash, psql query)"
echo "  - 4 noise events: ga, admin, webadmin normal logins"
echo "Agent must investigate, create incident, create alert, export evidence, write report."
