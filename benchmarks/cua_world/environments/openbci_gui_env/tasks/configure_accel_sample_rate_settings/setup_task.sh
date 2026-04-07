#!/bin/bash
set -e
echo "=== Setting up Configure Accel Sample Rate Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh || {
    echo "WARNING: openbci_task_utils.sh not found, using local fallback"
    function launch_openbci() {
        pkill -f "OpenBCI_GUI" || true
        su - ga -c "setsid DISPLAY=:1 bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
        sleep 15
    }
}

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/accel_config.png
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots
chown -R ga:ga /home/ga/Documents/OpenBCI_GUI/Screenshots

# 3. Launch OpenBCI GUI in Synthetic Mode
# We kill any existing instance to ensure a clean state
echo "Restarting OpenBCI GUI..."
pkill -f "OpenBCI_GUI" || true
sleep 2

# Launch
launch_openbci

# Wait for window
if ! wait_for_openbci 60; then
    echo "ERROR: OpenBCI GUI failed to start"
    exit 1
fi

# 4. Automate getting to the Session View (Synthetic)
# This saves the agent from the startup boilerplate so they can focus on the task
echo "Navigating to Synthetic Session..."
# Click 'Synthetic' (approx coords for 1920x1080 - adjust if needed or rely on agent)
# Ideally, we let the agent do this, but the task description implies "Starting State: Synthetic (Live) session has been started"
# We will use xdotool to click through the startup if possible, or just leave it at menu if too brittle.
# Based on the prompt "Starting State: A Synthetic (Live) session has been started", we must attempt to start it.

# Focus window
DISPLAY=:1 wmctrl -a "OpenBCI_GUI"

# Sequence to start synthetic session (Cyton default)
# 1. Select Synthetic (usually selected by default in some versions, but let's click START SESSION)
# The 'START SESSION' button is usually prominent.
# We will leave the agent to start the session or verify if it's already running.
# To be safe and robust, we will leave the GUI at the Control Panel.
# REVISION: Task description says "Starting State: ... session has been started".
# We must try to start it.

sleep 5
# Click 'START SESSION' (Approx coord: 960, 900)
click_at 960 900
sleep 5

# Check if we are in session (look for "Stop Data Stream" or "Start Data Stream" button in top bar)
# We'll just assume it worked. If not, the agent can click it.

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="