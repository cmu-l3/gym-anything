#!/bin/bash
set -e
echo "=== Setting up configure_syslog_forwarding task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker is running
systemctl start docker 2>/dev/null || true
sleep 3

# Ensure Wazuh stack is running
cd /home/ga/wazuh
docker compose up -d 2>/dev/null || true

# Wait for Wazuh manager to be healthy
echo "Waiting for Wazuh manager..."
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-analysisd is running"; then
        echo "Wazuh manager is ready (${ELAPSED}s)"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  Still waiting for manager (${ELAPSED}/${TIMEOUT}s)..."
done

# Record initial state: check if any syslog_output exists (should not)
echo "Recording initial configuration state..."
docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/ossec.conf 2>/dev/null > /tmp/initial_ossec_conf.txt || true
INITIAL_SYSLOG_COUNT=$(grep -c "<syslog_output>" /tmp/initial_ossec_conf.txt 2>/dev/null || echo "0")
echo "$INITIAL_SYSLOG_COUNT" > /tmp/initial_syslog_count.txt
echo "Initial syslog_output block count: $INITIAL_SYSLOG_COUNT"

# Verify csyslogd is NOT running initially
INITIAL_CSYSLOGD=$(docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null | grep csyslogd || echo "not found")
echo "$INITIAL_CSYSLOGD" > /tmp/initial_csyslogd_status.txt
echo "Initial csyslogd status: $INITIAL_CSYSLOGD"

# Remove any existing syslog_output blocks (ensure clean state)
# We use a python script inside the container to safely remove XML blocks if they exist
docker exec wazuh-wazuh.manager-1 bash -c '
    cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak
    python3 -c "
import re
try:
    with open(\"/var/ossec/etc/ossec.conf\", \"r\") as f:
        content = f.read()
    # Remove any syslog_output blocks using regex
    cleaned = re.sub(r\"<syslog_output>.*?</syslog_output>\", \"\", content, flags=re.DOTALL)
    if len(content) != len(cleaned):
        with open(\"/var/ossec/etc/ossec.conf\", \"w\") as f:
            f.write(cleaned)
        print(\"Cleaned syslog_output blocks from ossec.conf\")
except Exception as e:
    print(f\"Error cleaning config: {e}\")
" 2>/dev/null || echo "No cleanup needed"
' 2>/dev/null || true

# Restart manager to ensure clean state (csyslogd should NOT be running)
# Only restart if we actually changed something or if csyslogd was running
if echo "$INITIAL_CSYSLOGD" | grep -q "running"; then
    echo "Restarting manager to stop csyslogd..."
    docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control restart 2>/dev/null || true
    sleep 15
fi

# Ensure Firefox is open to Wazuh dashboard
source /workspace/scripts/task_utils.sh 2>/dev/null || true
ensure_firefox_wazuh "https://localhost" 2>/dev/null || true
sleep 5

# Focus and maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="