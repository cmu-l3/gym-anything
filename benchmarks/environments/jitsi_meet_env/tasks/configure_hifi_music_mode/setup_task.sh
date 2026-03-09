#!/bin/bash
set -e

echo "=== Setting up Configure HiFi Music Mode task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is running
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable. Attempting to start..."
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120
fi

# Reset configuration to a clean state (remove any previous attempts)
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
mkdir -p "$(dirname "$CONFIG_FILE")"

# Create a basic default config without the target settings
cat > "$CONFIG_FILE" << 'EOF'
// Jitsi Meet configuration overrides
var config = {};

// config.defaultSubject = "Default Meeting";

EOF
chown ga:ga "$CONFIG_FILE"

# Restart the web container to ensure we start with clean config
echo "Restarting web container to apply clean config..."
cd /home/ga/jitsi
docker compose restart web
sleep 5

# Start Firefox at the landing page
restart_firefox "http://localhost:8080" 15
maximize_firefox
focus_firefox

# Open the Browser Console (ctrl+shift+k) to hint at the verification step? 
# No, let the agent do it.

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="