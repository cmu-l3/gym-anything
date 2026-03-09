#!/bin/bash
# Setup script for regenerate_api_keys task

source /workspace/scripts/task_utils.sh

echo "=== Setting up regenerate_api_keys task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Emoncms is healthy
wait_for_emoncms

# 3. capture CURRENT (soon to be OLD) keys directly from DB
OLD_WRITE_KEY=$(get_apikey_write)
OLD_READ_KEY=$(get_apikey_read)

if [ -z "$OLD_WRITE_KEY" ] || [ -z "$OLD_READ_KEY" ]; then
    echo "ERROR: Could not retrieve current API keys from database"
    exit 1
fi

echo "Captured current keys:"
echo "  Write: $OLD_WRITE_KEY"
echo "  Read:  $OLD_READ_KEY"

# 4. Save old keys to reference file for agent and verifier
cat > /tmp/old_apikeys.txt << EOF
WRITE_KEY=${OLD_WRITE_KEY}
READ_KEY=${OLD_READ_KEY}
EOF
chmod 644 /tmp/old_apikeys.txt
# Make a copy in user home as well for easy access, though /tmp is readable
cp /tmp/old_apikeys.txt /home/ga/old_apikeys_reference.txt
chown ga:ga /home/ga/old_apikeys_reference.txt

# 5. Clean up any previous run artifacts
rm -f /home/ga/new_apikeys.txt

# 6. Launch Firefox to Dashboard (User must navigate to Account)
# We use the helper to ensure login and maximization
launch_firefox_to "http://localhost/user/login" 10
# Note: launch_firefox_to handles login automatically

# 7. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="