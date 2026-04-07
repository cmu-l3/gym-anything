#!/bin/bash
set -e
echo "=== Setting up software_dependency_audit task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OpenICE source exists (it should, but safety first)
if [ ! -d "/opt/openice/mdpnp" ]; then
    echo "Restoring OpenICE repository..."
    mkdir -p /opt/openice
    cd /opt/openice
    git clone --depth 1 https://github.com/mdpnp/mdpnp.git
    chown -R ga:ga /opt/openice/mdpnp
fi

# Clean up any previous report
rm -f /home/ga/Desktop/openice_dependency_audit.txt 2>/dev/null || true

# Ensure OpenICE application is running (as part of the context/distraction)
ensure_openice_running

# Maximize the window to set the scene
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open a terminal for the agent (since they need to inspect code)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 2
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Repo location: /opt/openice/mdpnp"
echo "Target report: /home/ga/Desktop/openice_dependency_audit.txt"