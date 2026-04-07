#!/bin/bash
# setup_task.sh - Pre-task hook for configure_site_permissions
# Resets Edge profile and creates the requirements document

set -e

echo "=== Setting up configure_site_permissions task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Kill any running Edge instances to ensure clean start
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Reset Edge Profile to default (Clean Slate)
# We want to ensure no permissions are already set
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
PREFS_FILE="$PROFILE_DIR/Preferences"

if [ -f "$PREFS_FILE" ]; then
    echo "Resetting Edge Preferences..."
    # We keep the file but remove content_settings to ensure a clean state for verification
    # Using python to surgically remove content_settings.exceptions if they exist
    python3 -c "
import json
import os

try:
    with open('$PREFS_FILE', 'r') as f:
        data = json.load(f)
    
    # Clear content settings exceptions
    if 'profile' in data and 'content_settings' in data['profile']:
        data['profile']['content_settings']['exceptions'] = {}
        
    with open('$PREFS_FILE', 'w') as f:
        json.dump(data, f)
    print('Preferences cleaned.')
except Exception as e:
    print(f'Error cleaning preferences: {e}')
"
fi

# 3. Create Requirements Document on Desktop
echo "Creating requirements document..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/lab_permission_requirements.txt << 'EOF'
LABORATORY CONFIGURATION REQUIREMENTS - SEMESTER 1
==================================================

Please configure the browser permissions for the shared student computers.
Navigate to Edge Settings > Cookies and site permissions to apply these rules.

NOTIFICATIONS
-------------
- youtube.com: BLOCK (Prevent distraction)
- facebook.com: BLOCK (Prevent distraction)
- teams.microsoft.com: ALLOW (Required for remote lectures)

CAMERA
------
- zoom.us: ALLOW (Required for virtual sessions)

LOCATION
--------
- maps.google.com: ALLOW (Required for Geography 101)

REPORTING
---------
After configuration, please create a summary file at:
/home/ga/Desktop/permission_config_report.txt
listing the changes you made.
EOF
chown ga:ga /home/ga/Desktop/lab_permission_requirements.txt

# 4. Remove any previous report file
rm -f /home/ga/Desktop/permission_config_report.txt

# 5. Launch Microsoft Edge
echo "Launching Microsoft Edge..."
# Use flags to prevent first-run wizards that might block automation
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --start-maximized \
    --password-store=basic \
    about:blank > /dev/null 2>&1 &"

# 6. Wait for Edge to load
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window found."
        break
    fi
    sleep 1
done

# Ensure window is focused
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="