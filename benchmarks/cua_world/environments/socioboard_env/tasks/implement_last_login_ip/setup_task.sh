#!/bin/bash
echo "=== Setting up implement_last_login_ip task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean database state: drop column if it somehow exists from a previous run
log "Ensuring clean database state..."
mysql -u root socioboard -e "ALTER TABLE user_details DROP COLUMN last_login_ip;" 2>/dev/null || true

# Backup the original model file just in case, and ensure clean state
MODEL_PATH="/opt/socioboard/socioboard-api/library/sequelize-cli/models/user_details.js"
if [ -f "$MODEL_PATH" ]; then
    # If it contains last_login_ip, someone messed with the base image. Let's warn.
    if grep -q "last_login_ip" "$MODEL_PATH"; then
        log "WARNING: last_login_ip already found in model file. Reverting..."
        sed -i '/last_login_ip/d' "$MODEL_PATH"
    fi
    # Make sure ga user owns the file so the agent can edit it easily
    chown ga:ga "$MODEL_PATH"
fi

# Ensure PM2 is running and microservices are started
log "Ensuring microservices are online..."
su - ga -c "pm2 start all 2>/dev/null" || true
sleep 3

# Take an initial screenshot of the desktop
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="