#!/bin/bash
set -e

echo "=== Setting up Sugar Learning Platform ==="

# Sugar runs as the GDM session (configured in install script).
# After install, GDM needs to restart to pick up the new session.
# The pre_start hook already set AccountsService and GDM config.

# Restart GDM to switch from GNOME to Sugar session
echo "Restarting GDM to launch Sugar session..."
systemctl restart accounts-daemon
sleep 2
systemctl restart gdm3
sleep 15

# Wait for Sugar to be ready
wait_for_sugar() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "jarabe.main" > /dev/null 2>&1; then
            echo "Sugar shell (jarabe) is running"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Sugar may not have started (timeout after ${timeout}s)"
    return 0
}

wait_for_sugar

# Give Sugar additional time to fully render the home view
sleep 5

echo "=== Sugar Learning Platform setup complete ==="
echo "Sugar desktop session is running on DISPLAY :1"
