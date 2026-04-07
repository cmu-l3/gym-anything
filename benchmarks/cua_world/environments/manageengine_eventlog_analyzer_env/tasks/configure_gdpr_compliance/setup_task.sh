#!/bin/bash
echo "=== Setting up GDPR Compliance Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# 3. Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 4. Generate real log activity to ensure reports are not empty
echo "Generating log activity for compliance report..."
# Failed SSH logins (GDPR Article 32 - Security of processing)
for i in {1..5}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=1 \
        -o PasswordAuthentication=yes \
        invaliduser@127.0.0.1 "exit" < /dev/null 2>/dev/null || true
done
# Sudo usage (Accountability)
su - ga -c "sudo -l" 2>/dev/null
# System logs
logger -t gdpr_audit "Manual compliance check started"

# 5. Navigate Firefox to the main dashboard
# We start at the dashboard so the agent has to navigate to 'Compliance'
ensure_firefox_on_ela "/event/index.do"
sleep 5

# 6. Clean up any previous run artifacts
rm -f /home/ga/Documents/gdpr_compliance_report.pdf
rm -f /home/ga/Documents/gdpr_compliance_report.csv

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="