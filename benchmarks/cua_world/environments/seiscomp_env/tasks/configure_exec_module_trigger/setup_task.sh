#!/bin/bash
echo "=== Setting up configure_exec_module_trigger task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Provide a completely clean state for the exec module
echo "--- Resetting exec module state ---"
su - ga -c "seiscomp stop exec >/dev/null 2>&1" || true
su - ga -c "seiscomp disable exec >/dev/null 2>&1" || true

# Remove any existing exec configurations (user and global level)
rm -f /home/ga/.seiscomp/exec.cfg 2>/dev/null
rm -f /home/ga/seiscomp/etc/exec.cfg 2>/dev/null
sed -i '/^subscriptions/d' /home/ga/seiscomp/etc/global.cfg 2>/dev/null || true

# Remove target files to ensure agent must create them
rm -rf /home/ga/scripts 2>/dev/null
rm -f /home/ga/origin_audit.log 2>/dev/null

# Recreate an empty scripts directory
mkdir -p /home/ga/scripts
chown ga:ga /home/ga/scripts

# 2. Ensure main SeisComP infrastructure is running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# 3. Open a terminal for the user (since script creation is required)
echo "--- Preparing Desktop Environment ---"
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 2
fi

# Focus terminal
focus_and_maximize "Terminal"

# Give UI time to settle
sleep 2

# Take initial screenshot to prove clean state
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="