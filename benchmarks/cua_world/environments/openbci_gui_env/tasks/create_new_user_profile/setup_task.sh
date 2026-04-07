#!/bin/bash
echo "=== Setting up create_new_user_profile task ==="

# Source utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. CLEANUP: Remove any existing 'Subject_Alpha' profile to ensure fresh start
echo "Cleaning up previous user profiles..."
TARGET_USER="Subject_Alpha"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
USERS_DIR="$SETTINGS_DIR/Users"

# Remove directory if it exists
if [ -d "$USERS_DIR/$TARGET_USER" ]; then
    rm -rf "$USERS_DIR/$TARGET_USER"
    echo "Removed existing profile directory for $TARGET_USER"
fi

# Reset User_Settings.json to default if it contains Subject_Alpha
# This prevents the GUI from auto-loading the profile if it was last used
if [ -f "$SETTINGS_DIR/User_Settings.json" ]; then
    if grep -q "$TARGET_USER" "$SETTINGS_DIR/User_Settings.json"; then
        echo "Resetting User_Settings.json..."
        rm -f "$SETTINGS_DIR/User_Settings.json"
    fi
fi

# 2. LAUNCH: Start OpenBCI GUI at the Control Panel
echo "Launching OpenBCI GUI..."
# Use the shared utility or fallback to manual launch
if command -v launch_openbci >/dev/null; then
    launch_openbci
else
    # Fallback launch logic
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci" >/dev/null; then
            echo "Window appeared."
            break
        fi
        sleep 1
    done
fi

# Ensure window is focused
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# 3. EVIDENCE: Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Instructions: Create user 'Subject_Alpha', select Synthetic, and Start Session."