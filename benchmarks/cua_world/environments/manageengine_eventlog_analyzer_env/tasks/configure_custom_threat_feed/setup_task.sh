#!/bin/bash
# Setup for "configure_custom_threat_feed" task

echo "=== Setting up Configure Custom Threat Feed task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Setup Local Threat Feed Server (HTTP)
# ==============================================================================
THREAT_DIR="/home/ga/threat_feed"
THREAT_FILE="$THREAT_DIR/threats.txt"
HTTP_PORT="8888"
HTTP_LOG="/tmp/threat_server_access.log"

mkdir -p "$THREAT_DIR"

# Populate with real malicious IP data (Feodo Tracker sample)
cat > "$THREAT_FILE" << 'EOF'
# Feodo Tracker IP Blocklist (Sample)
# Source: https://feodotracker.abuse.ch/
# Date: 2025-05-15
89.101.97.139
41.228.22.180
190.117.206.158
185.117.73.68
45.163.244.202
103.109.102.194
EOF

chown -R ga:ga "$THREAT_DIR"

# Start Python HTTP server in background
echo "Starting local threat feed server on port $HTTP_PORT..."
pkill -f "http.server $HTTP_PORT" 2>/dev/null || true
su - ga -c "cd $THREAT_DIR && nohup python3 -u -m http.server $HTTP_PORT > $HTTP_LOG 2>&1 &"

# Verify server is running
sleep 2
if pgrep -f "http.server $HTTP_PORT" > /dev/null; then
    echo "Threat feed server running at http://localhost:$HTTP_PORT/threats.txt"
else
    echo "ERROR: Failed to start threat feed server"
    exit 1
fi

# ==============================================================================
# 2. Prepare EventLog Analyzer
# ==============================================================================
wait_for_eventlog_analyzer

# Navigate to Dashboard (starting point)
# The agent must find the "Threat Intelligence" settings themselves
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 5

# Clean up any existing popups
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Local Threat Feed URL: http://localhost:$HTTP_PORT/threats.txt"