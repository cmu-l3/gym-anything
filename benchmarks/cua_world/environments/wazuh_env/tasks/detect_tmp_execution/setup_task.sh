#!/bin/bash
set -e
echo "=== Setting up detect_tmp_execution task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Clean up previous artifacts to ensure a fresh start
echo "Cleaning up previous task artifacts..."
docker exec "${CONTAINER}" sed -i '/<localfile>/,/\/localfile>/ { /replay.log/d; }' /var/ossec/etc/ossec.conf 2>/dev/null || true
docker exec "${CONTAINER}" sed -i '/rule id="100150"/,/rule>/d' /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

# 2. Create sample audit log data
echo "Creating sample audit log data..."
SAMPLE_LOG_CONTENT='type=EXECVE msg=audit(1693234001.123:101): argc=1 a0="/usr/bin/ls"
type=EXECVE msg=audit(1693234002.456:102): argc=2 a0="/usr/bin/grep" a1="foo"
type=EXECVE msg=audit(1693234005.789:103): argc=1 a0="/tmp/miner.sh"
type=EXECVE msg=audit(1693234010.012:104): argc=1 a0="/var/tmp/.hidden/exploit"
type=EXECVE msg=audit(1693234015.345:105): argc=1 a0="/home/user/script.sh"'

# Write sample log to container
# We use a temp file on host then copy to avoid complex quoting issues with docker exec
echo "$SAMPLE_LOG_CONTENT" > /tmp/audit_sample.log
docker cp /tmp/audit_sample.log "${CONTAINER}:/root/audit_sample.log"
rm -f /tmp/audit_sample.log

# 3. Create empty replay log file
docker exec "${CONTAINER}" touch /root/replay.log
docker exec "${CONTAINER}" chmod 666 /root/replay.log

# 4. Ensure Firefox is open (standard for environment)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Sample log created at: /root/audit_sample.log (inside container)"
echo "Target replay log: /root/replay.log (inside container)"