#!/bin/bash
# Setup for "import_log_file" task

echo "=== Setting up Import Log File task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# 2. Prepare the log file
LOG_SAMPLE="/home/ga/log_samples/auth.log"
mkdir -p /home/ga/log_samples

# Ensure we have a valid auth.log with content
if [ ! -f "$LOG_SAMPLE" ] || [ ! -s "$LOG_SAMPLE" ]; then
    echo "Creating sample auth.log..."
    # If system auth.log is available, copy it
    if [ -f /var/log/auth.log ]; then
        cp /var/log/auth.log "$LOG_SAMPLE"
    else
        # Fallback: Generate fake auth logs if system log missing
        cat > "$LOG_SAMPLE" << EOF
Mar 10 08:00:01 ubuntu-server CRON[1234]: pam_unix(cron:session): session opened for user root by (uid=0)
Mar 10 08:00:01 ubuntu-server CRON[1234]: pam_unix(cron:session): session closed for user root
Mar 10 08:15:01 ubuntu-server sshd[2345]: Accepted password for user admin from 192.168.1.50 port 55555 ssh2
Mar 10 08:15:01 ubuntu-server sshd[2345]: pam_unix(sshd:session): session opened for user admin by (uid=0)
Mar 10 08:17:22 ubuntu-server sudo:    admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; COMMAND=/usr/bin/apt update
Mar 10 08:17:22 ubuntu-server sudo: pam_unix(sudo:session): session opened for user root by admin(uid=1000)
EOF
    fi
fi

# Ensure permissions are correct for the user
chown ga:ga "$LOG_SAMPLE"
chmod 644 "$LOG_SAMPLE"

# 3. Record initial database state
# We count rows that look like they came from our log file (e.g., containing 'pam_unix')
# This serves as a baseline to detect if import happened.
echo "Recording initial event count..."
# Note: Table names in ELA depend on version, but typical queries work on views or raw tables.
# We'll use a broad query or check specific keywords if tables are standard.
# Since we don't know the exact schema, we'll try a few common ones or rely on VLM if DB fails.
# However, for robustness, we'll try to count total events in the system.
INITIAL_EVENT_COUNT=$(ela_db_query "SELECT count(*) FROM Component_Event_Log" 2>/dev/null || echo "0")
if [ "$INITIAL_EVENT_COUNT" = "0" ]; then
    # Fallback table name
    INITIAL_EVENT_COUNT=$(ela_db_query "SELECT count(*) FROM EventLog" 2>/dev/null || echo "0")
fi
echo "$INITIAL_EVENT_COUNT" > /tmp/initial_event_count.txt
echo "Initial event count: $INITIAL_EVENT_COUNT"

# 4. Open Firefox to the Dashboard
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Take initial screenshot
take_screenshot /tmp/import_log_file_start.png

echo "=== Task Setup Complete ==="
echo "Log file prepared at: $LOG_SAMPLE"