#!/bin/bash
set -e
echo "=== Setting up optimize_client_performance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define config path
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
CONFIG_FILE="$CONFIG_DIR/config.js"

# Ensure directory exists
mkdir -p "$CONFIG_DIR"

# Check if config file exists, if not, create a basic one from the container defaults
# or write a template that has the "unoptimized" values.
# We explicitly set the values to the "bad" state (CPU intensive) so the agent has to change them.

echo "Preparing config.js with unoptimized defaults..."
cat > "$CONFIG_FILE" << 'EOF'
var config = {
    // Connection
    hosts: {
        domain: 'localhost',
        muc: 'conference.localhost'
    },
    bosh: '//localhost/http-bind',
    websocket: 'wss://localhost/xmpp-websocket',

    // Audio/Video defaults (UNOPTIMIZED)
    // Audio levels show dots for active speakers - high CPU
    disableAudioLevels: false,

    // Detects if mic is noisy - high CPU
    enableNoisyMicDetection: true,

    // Start with video enabled
    startAudioOnly: false,

    // Other settings
    p2p: {
        enabled: true,
        useStunTurn: true
    },
    analytics: {
        disabled: true
    }
};
EOF

# Ensure permissions are correct for ga user
chown -R ga:ga "/home/ga/.jitsi-meet-cfg"

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
fi

# Ensure Jitsi is up (though we are just editing files, it's good context)
# We don't strictly need to wait for full health check for a file editing task, 
# but we'll do a quick check to ensure the env is sane.
if ! docker ps | grep -q jitsi-web; then
    echo "WARNING: Jitsi containers might not be fully running yet."
fi

# Maximize terminal
sleep 2
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Config file located at: $CONFIG_FILE"