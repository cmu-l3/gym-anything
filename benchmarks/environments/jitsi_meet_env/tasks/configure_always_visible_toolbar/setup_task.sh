#!/bin/bash
set -e

echo "=== Setting up Configure Always-Visible Toolbar task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming and container restart verification)
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_iso.txt

# 1. Reset configuration to default (clean state)
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-interface_config.js"
mkdir -p "$(dirname "$CONFIG_FILE")"

# Write a default empty/commented config or just generic overrides
cat > "$CONFIG_FILE" << EOF
// Custom interface configuration overrides
// Add your settings here
var interfaceConfig = {
    // TOOLBAR_ALWAYS_VISIBLE: false
};
EOF
chown ga:ga "$CONFIG_FILE"

# 2. Ensure Jitsi is running
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 60; then
    echo "Starting Jitsi..."
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120
fi

# 3. Start Firefox at the landing page
echo "Starting Firefox..."
restart_firefox "http://localhost:8080" 8
maximize_firefox
focus_firefox

# 4. Create Documents directory for evidence
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
# Remove old evidence if present
rm -f /home/ga/Documents/persistent_toolbar.png

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="