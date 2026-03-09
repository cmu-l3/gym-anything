#!/bin/bash
# setup_task.sh - Pre-task hook for secure_dev_browser_config
set -e

echo "=== Setting up secure_dev_browser_config task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Kill any existing Firefox instances to ensure clean start
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# 3. Ensure Documents directory exists for the report
sudo -u ga mkdir -p /home/ga/Documents

# 4. Remove any existing report file to prevent false positives
rm -f /home/ga/Documents/browser_security_config.json

# 5. Locate Firefox Profile
# We need to ensure we know where the profile is, though usually it's default.profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -f "$candidate/prefs.js" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

if [ -z "$PROFILE_DIR" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "prefs.js" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

if [ -n "$PROFILE_DIR" ]; then
    echo "Found Firefox profile at: $PROFILE_DIR"
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
    
    # Optional: Reset specific prefs to ensure they aren't already set correctly (clean slate)
    # This prevents 'accidental' passing if the base image already has these set.
    # appending user_pref lines to user.js would enforce them on startup, but we want to allow user to change them.
    # So we simply don't modify them here, assuming standard Firefox defaults are insecure.
    # Standard defaults:
    # network.dns.disablePrefetch -> false
    # network.prefetch-next -> true
    # geo.enabled -> true
    # etc.
    :
else
    echo "WARNING: Could not locate Firefox profile directory."
fi

# 6. Launch Firefox
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote about:blank > /tmp/firefox.log 2>&1 &"

# 7. Wait for window
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# 8. Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="