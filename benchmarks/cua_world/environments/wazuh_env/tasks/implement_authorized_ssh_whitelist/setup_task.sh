#!/bin/bash
echo "=== Setting up implement_authorized_ssh_whitelist ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts to ensure a fresh state
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

echo "Cleaning up previous configurations..."
docker exec "${CONTAINER}" rm -f /var/ossec/etc/lists/authorized_users 2>/dev/null || true
docker exec "${CONTAINER}" rm -f /var/ossec/etc/lists/authorized_users.cdb 2>/dev/null || true

# Reset local_rules.xml (remove our target rule if it exists)
docker exec "${CONTAINER}" sed -i '/id="100500"/,/<\/rule>/d' /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

# Remove list reference from ossec.conf if it exists
docker exec "${CONTAINER}" sed -i '/<list>etc\/lists\/authorized_users<\/list>/d' /var/ossec/etc/ossec.conf 2>/dev/null || true

# Restart manager to apply clean state
echo "Restarting Wazuh manager to ensure clean state..."
restart_wazuh_manager > /dev/null

# 2. Create test logs file for the agent
cat > /home/ga/ssh_test_logs.txt << 'EOF'
Dec 10 10:00:00 server sshd[1234]: Accepted password for ga from 192.168.1.100 port 22 ssh2
Dec 10 10:05:00 server sshd[1235]: Accepted password for intruder from 192.168.1.101 port 22 ssh2
EOF
chown ga:ga /home/ga/ssh_test_logs.txt

# 3. Ensure Firefox is open to the Dashboard (standard starting state)
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="