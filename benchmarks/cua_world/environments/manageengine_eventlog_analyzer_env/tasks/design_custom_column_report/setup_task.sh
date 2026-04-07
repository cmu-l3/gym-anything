#!/bin/bash
# Setup for "design_custom_column_report" task
# 1. Generates real syslog data (failed logins)
# 2. Cleans up previous artifacts
# 3. Opens ELA to the Reports section

echo "=== Setting up Design Custom Column Report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/executive_report.csv
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Generate real log data (Failed Logins)
# We inject these into syslog so ELA picks them up
echo "Generating failed login events..."
for i in {1..10}; do
    # Generate realistic SSH failed attempts
    USER_ID="user$((RANDOM % 100))"
    IP="192.168.1.$((RANDOM % 255))"
    
    # Log to auth.log via logger
    logger -t sshd -p auth.info "Failed password for invalid user $USER_ID from $IP port 22 ssh2"
    
    # Also log to local syslog for redundancy
    logger -t login "FAILED LOGIN SESSION: $USER_ID on /dev/pts/1 from $IP"
    
    sleep 0.5
done
echo "Log generation complete."

# 4. Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer 120

# 5. Clean up DB (Remove report if it exists from previous run)
# We attempt to delete the report profile to ensure a clean slate
# Note: exact table names vary by version, so we proceed even if this fails
echo "Attempting to clean up old report profiles..."
ela_db_query "DELETE FROM ReportConfig WHERE REPORTNAME='Executive Failed Logons'" 2>/dev/null || true

# 6. Navigate Firefox to Reports section
ensure_firefox_on_ela "/event/index.do#/reports/reports-home"
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Instructions:"
echo "1. Go to Reports tab."
echo "2. Create a new Custom Report named 'Executive Failed Logons'."
echo "3. Select 'Failed Logons' (or Auth Failures)."
echo "4. Customize columns: Select ONLY User, Source, and Time."
echo "5. Save and Export as CSV to /home/ga/Documents/executive_report.csv"