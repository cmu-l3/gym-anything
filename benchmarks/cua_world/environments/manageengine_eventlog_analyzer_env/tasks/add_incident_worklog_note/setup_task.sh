#!/bin/bash
echo "=== Setting up Add Incident Worklog Note task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running and ready
wait_for_eventlog_analyzer 600

# 1. Inject the specific 'Emergency' log to trigger the alert
# We use 'logger' which sends to local syslog (UDP 514 usually, or local socket picked up by rsyslog -> ELA)
# ELA is configured in the env to listen on 514 or monitor local files.
echo "Injecting trigger log event..."
logger -p local0.emerg "CORE_DUMP_DETECTED_001: Critical system failure imminent at memory address 0xDEADBEEF"

# Also append directly to monitored file just in case UDP is flaky in container
if [ -f /var/log/syslog ]; then
    echo "$(date '+%b %d %H:%M:%S') localhost CORE_DUMP_DETECTED_001: Critical system failure imminent" >> /var/log/syslog
fi

# 2. Wait a moment for ELA to ingest and index the alert
echo "Waiting for alert ingestion..."
sleep 15

# 3. Open Firefox to the Alerts/Incidents page
# The specific URL for alerts might vary, usually /event/index.do#/alerts/list or similar
# We'll go to the main dashboard or alerts view
ensure_firefox_on_ela "/event/index.do#/alerts/list"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="