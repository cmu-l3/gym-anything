#!/bin/bash
set -e
echo "=== Setting up configure_proxy_settings task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ============================================================
# Clean existing proxy settings to ensure a fresh start
# ============================================================
echo "Cleaning existing proxy configuration..."

# 1. Clean JStock specific config files
if [ -d /home/ga/.jstock ]; then
    # aggressively find and wipe proxy settings in XML/properties files
    find /home/ga/.jstock -type f \( -name "*.xml" -o -name "*.properties" -o -name "*.conf" \) -print0 | xargs -0 -I {} sed -i '/proxy/d' "{}" 2>/dev/null || true
fi

# 2. Clean Java User Preferences (common storage for Java apps)
# These are often XML files in ~/.java/.userPrefs
if [ -d /home/ga/.java/.userPrefs ]; then
    find /home/ga/.java/.userPrefs -type f -name "prefs.xml" -print0 | xargs -0 -I {} sed -i '/proxy/d' "{}" 2>/dev/null || true
fi

# Snapshot initial config state (checksums) for anti-gaming comparison
echo "Snapshotting config state..."
rm -f /tmp/initial_config_checksums.txt
if [ -d /home/ga/.jstock ]; then
    find /home/ga/.jstock -type f -exec md5sum {} \; >> /tmp/initial_config_checksums.txt 2>/dev/null || true
fi
if [ -d /home/ga/.java ]; then
    find /home/ga/.java -type f -exec md5sum {} \; >> /tmp/initial_config_checksums.txt 2>/dev/null || true
fi

# ============================================================
# Launch JStock
# ============================================================
# Kill any existing instances
pkill -f "jstock" 2>/dev/null || true
sleep 2

echo "Starting JStock..."
# Use setsid to detach process
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock window
echo "Waiting for JStock window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done
sleep 5

# ============================================================
# Handle Initial Dialogs & State
# ============================================================
# Dismiss "JStock News" dialog if it appears (Enter usually works for "OK")
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
# Press Escape just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="