#!/bin/bash
set -e
echo "=== Setting up harden_security_preferences task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure VeraCrypt is not running (clean slate)
pkill -f veracrypt 2>/dev/null || true
sleep 2

# Reset VeraCrypt configuration to defaults by removing existing config
# Check both possible config locations
for config_dir in "/home/ga/.config/VeraCrypt" "/home/ga/.VeraCrypt" "/root/.config/VeraCrypt" "/root/.VeraCrypt"; do
    if [ -d "$config_dir" ]; then
        echo "Removing existing config at $config_dir"
        rm -f "$config_dir/Configuration.xml" 2>/dev/null || true
    fi
done

# Remove any previous compliance report
rm -f /home/ga/Documents/security_compliance_report.txt 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Dismount any mounted volumes (cleanup)
if which veracrypt >/dev/null 2>&1; then
    veracrypt --text --dismount --non-interactive 2>/dev/null || true
fi
sleep 1

# Launch VeraCrypt GUI fresh (this creates default config in memory/disk)
echo "Starting VeraCrypt..."
su - ga -c "DISPLAY=:1 veracrypt &"

# Wait for VeraCrypt window
echo "Waiting for VeraCrypt window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "VeraCrypt"; then
        echo "VeraCrypt window detected"
        break
    fi
    sleep 1
done

# Maximize and focus (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "VeraCrypt" 2>/dev/null || true

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="