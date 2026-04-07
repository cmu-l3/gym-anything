#!/bin/bash
echo "=== Setting up data_spillage_remediation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if ! splunk_is_running; then
    echo "Starting Splunk..."
    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Create dummy data with leaked credentials and collateral data using recent timestamps
NOW=$(date +'%d/%b/%Y:%H:%M:%S %z')
PAST=$(date -d "1 hour ago" +'%d/%b/%Y:%H:%M:%S %z')

cat > /tmp/apache_leak.log << EOF
192.168.1.5 - - [$PAST] "POST /login HTTP/1.1" 200 432 "user=admin&password=SuperSecret123"
192.168.1.5 - - [$PAST] "GET /dashboard HTTP/1.1" 200 1024 "-"
10.0.0.22 - - [$NOW] "POST /login HTTP/1.1" 401 221 "user=test&password=WrongPassword!"
10.0.0.22 - - [$NOW] "GET /index.html HTTP/1.1" 200 2048 "-"
EOF

# Ingest dummy data
echo "Ingesting leaked data..."
/opt/splunk/bin/splunk add oneshot /tmp/apache_leak.log -index web_logs -sourcetype apache_leak -auth admin:SplunkAdmin1!
sleep 5

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="