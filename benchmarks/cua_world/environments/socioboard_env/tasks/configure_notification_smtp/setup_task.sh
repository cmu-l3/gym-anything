#!/bin/bash
echo "=== Setting up Configure Notification SMTP task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure the Socioboard notification service exists and has a dummy config
CONFIG_DIR="/opt/socioboard/socioboard-api/notification/config"
CONFIG_FILE="$CONFIG_DIR/development.json"

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Creating missing config directory..."
    mkdir -p "$CONFIG_DIR"
fi

# We use Python to inject dummy SMTP settings while preserving the rest of the config
# If the file doesn't exist or is invalid, we create a base one.
python3 << 'EOF'
import json
import os

config_path = "/opt/socioboard/socioboard-api/notification/config/development.json"
base_config = {
    "node_env": "development",
    "host": "localhost",
    "port": 3004,
    "mongo": {
        "db_name": "socioboard",
        "host": "localhost",
        "port": 27017
    }
}

try:
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            base_config = json.load(f)
except Exception:
    pass

# Inject dummy email settings
base_config["mailService"] = {
    "host": "smtp.mailtrap.io",
    "port": 2525,
    "secure": False,
    "auth": {
        "user": "dummy_user_123",
        "pass": "dummy_pass_123"
    },
    "senderEmail": "test@localhost",
    "senderName": "Test Alert"
}

with open(config_path, 'w') as f:
    json.dump(base_config, f, indent=4)
EOF

# Fix permissions so agent can edit it
chown ga:ga "$CONFIG_FILE" 2>/dev/null || true
chmod 644 "$CONFIG_FILE" 2>/dev/null || true

# Start or restart the notification service with pm2
echo "Starting notification microservice in pm2..."
sudo -u ga pm2 start /opt/socioboard/socioboard-api/notification/app.js --name notification 2>/dev/null || \
sudo -u ga pm2 restart notification 2>/dev/null || true

# Save the modification time of the newly prepped config file
stat -c %Y "$CONFIG_FILE" > /tmp/initial_config_mtime.txt

# Clean up any existing report
rm -f /home/ga/notification_smtp_report.txt

# Open Firefox to provide visual context (Socioboard dashboard)
ensure_firefox_running "http://localhost/"

# Take initial screenshot showing ready state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="