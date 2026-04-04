#!/bin/bash
set -e
echo "=== Setting up disable_system_services task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the dummy 'debug-logger' service
SERVICE_NAME="debug-logger"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Creating legacy service at $SERVICE_FILE..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Legacy Debug Logger (Do Not Use)
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do echo "Debug heartbeat \$(date)" >> /tmp/debug-logger.log; sleep 10; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 2. Enable and start the service
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Verify it started
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Service $SERVICE_NAME started successfully."
else
    echo "ERROR: Failed to start $SERVICE_NAME"
    exit 1
fi

# 3. Ensure Virtualmin/Webmin is ready in Firefox
ensure_virtualmin_ready

# Navigate specifically to the System category (optional, but helpful starting point)
# We'll just leave it at the dashboard or navigate to System if we want to be nice.
# Let's start at the dashboard to require navigation.
navigate_to "https://localhost:10000/"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="