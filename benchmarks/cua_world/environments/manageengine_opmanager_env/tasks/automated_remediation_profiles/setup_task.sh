#!/bin/bash
# setup_task.sh — Automated Remediation Profiles
# Waits for OpManager, writes the playbook to the desktop, and records timestamps.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Automated Remediation Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 2. Write the remediation playbook to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
PLAYBOOK_FILE="$DESKTOP_DIR/remediation_playbook.txt"
mkdir -p "$DESKTOP_DIR"

cat > "$PLAYBOOK_FILE" << 'PLAYBOOK_EOF'
=== NOC Automated Remediation Playbook v1.2 ===
Effective Date: 2024-11-01
Approved By: Network Operations Director

SECTION 1: Remediation Scripts
All scripts must be placed in /opt/remediation-scripts/ and be executable (chmod +x).
Note: You may need to use sudo to create the directory in /opt.

Script 1: restart_snmpd.sh
  Purpose: Restart the SNMP agent when SNMP polling failures are detected
  Content:
    #!/bin/bash
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SNMP remediation triggered" >> /var/log/remediation.log
    systemctl restart snmpd
    sleep 5
    snmpwalk -v2c -c public 127.0.0.1 sysUpTime > /dev/null 2>&1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SNMP agent restarted, exit code: $?" >> /var/log/remediation.log

Script 2: clear_disk_cache.sh
  Purpose: Free filesystem cache when disk utilization alarms trigger
  Content:
    #!/bin/bash
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk cache clear triggered" >> /var/log/remediation.log
    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Disk cache cleared successfully" >> /var/log/remediation.log

Script 3: check_service_health.sh
  Purpose: Run comprehensive health check when device-down alarms fire
  Content:
    #!/bin/bash
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Service health check triggered" >> /var/log/remediation.log
    ping -c 3 127.0.0.1 >> /var/log/remediation.log 2>&1
    curl -s -o /dev/null -w "%{http_code}" http://localhost:8060 >> /var/log/remediation.log
    echo "" >> /var/log/remediation.log
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Health check complete" >> /var/log/remediation.log

SECTION 2: OpManager Notification Profiles
Create the following notification profiles in OpManager (Settings > Notifications > Notification Profiles).
Each profile must use the "Run Program" or "Execute Program" delivery method (not Email).

Profile 1:
  Name: Auto-Remediate-SNMP-Failure
  Type: Run Program
  Program Path: /opt/remediation-scripts/restart_snmpd.sh
  Trigger: Critical severity alarms

Profile 2:
  Name: Auto-Remediate-Disk-Usage
  Type: Run Program
  Program Path: /opt/remediation-scripts/clear_disk_cache.sh
  Trigger: Trouble severity alarms

Profile 3:
  Name: Auto-Remediate-Device-Down
  Type: Run Program
  Program Path: /opt/remediation-scripts/check_service_health.sh
  Trigger: Device Down events

=== END OF PLAYBOOK ===
PLAYBOOK_EOF

chown ga:ga "$PLAYBOOK_FILE" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Remediation playbook written to $PLAYBOOK_FILE"

# ------------------------------------------------------------
# 3. Record task start timestamps
# ------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
# Record initial access time of the playbook
stat -c %X "$PLAYBOOK_FILE" > /tmp/playbook_initial_atime.txt 2>/dev/null || echo "0" > /tmp/playbook_initial_atime.txt

echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/automated_remediation_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="