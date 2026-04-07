#!/bin/bash
set -e
echo "=== Setting up validate_log_decoding task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh API is ready before starting
echo "Waiting for Wazuh API..."
wait_for_service "Wazuh API" "check_api_health" 180

# Create the log samples file
# These correspond to the metadata in task.json
cat > /home/ga/log_samples.txt << 'LOGSEOF'
Mar  5 14:32:11 server1 sshd[12345]: Failed password for invalid user admin from 192.168.1.100 port 54321 ssh2
Mar  5 14:35:22 server1 sshd[12346]: Accepted password for john from 10.0.0.50 port 43210 ssh2
Mar  5 14:40:33 server1 sudo:    john : TTY=pts/0 ; PWD=/home/john ; USER=root ; COMMAND=/bin/cat /etc/shadow
Mar  5 15:01:44 server1 sshd[12400]: Failed password for root from 172.16.0.25 port 33333 ssh2
Mar  5 15:10:55 server1 su: FAILED SU (to root) testuser on pts/1
LOGSEOF

# Set ownership so the agent can read it
chown ga:ga /home/ga/log_samples.txt
chmod 644 /home/ga/log_samples.txt

# Remove any existing report file to ensure a clean state
rm -f /home/ga/logtest_report.json

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Log samples created at /home/ga/log_samples.txt"