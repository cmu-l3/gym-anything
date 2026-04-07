#!/bin/bash
set -e
echo "=== Setting up panoramic_visual_system_setup task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the template exists (Bridge Command install location)
TEMPLATE_PATH="/opt/bridgecommand/bc5.ini"
if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "ERROR: Template config not found at $TEMPLATE_PATH"
    # Fallback: create a dummy template if BC isn't fully installed in this env yet
    echo "Creating dummy template..."
    cat > "$TEMPLATE_PATH" << EOF
[Graphics]
view_angle=90
look_rotation=0
look_pitch=0
screen_width=800
screen_height=600
fullscreen=0
graphics_driver=OpenGL

[Network]
network_slave=0
server_ip=127.0.0.1
port=10110

[Joystick]
use_joystick=0
EOF
fi

# Create the deployment directory to ensure agent can write immediately
# (The task asks the agent to create files IN this directory, so existence helps)
mkdir -p "/home/ga/Documents/config_deployment"
chown -R ga:ga "/home/ga/Documents/config_deployment"

# Clean up any previous attempts
rm -f "/home/ga/Documents/config_deployment/visual_left.ini"
rm -f "/home/ga/Documents/config_deployment/visual_center.ini"
rm -f "/home/ga/Documents/config_deployment/visual_right.ini"

# Ensure we are in a clean state (desktop focused)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Template config available at: $TEMPLATE_PATH"
echo "Target directory: /home/ga/Documents/config_deployment/"