#!/bin/bash
set -e

echo "=== Setting up ESA SNAP configuration ==="

# Wait for desktop to be ready
sleep 5

setup_user_snap() {
    local username=$1
    local home_dir=$2

    echo "Setting up SNAP for user: $username"

    # Create SNAP user directory structure
    sudo -u "$username" mkdir -p "$home_dir/.snap/etc"
    sudo -u "$username" mkdir -p "$home_dir/.snap/auxdata"
    sudo -u "$username" mkdir -p "$home_dir/.snap/var/cache"

    # Create working directories
    sudo -u "$username" mkdir -p "$home_dir/snap_data"
    sudo -u "$username" mkdir -p "$home_dir/snap_projects"
    sudo -u "$username" mkdir -p "$home_dir/snap_exports"

    # Configure SNAP to disable update checks and tips on startup
    cat > "$home_dir/.snap/etc/snap.properties" << 'EOF'
# SNAP Configuration
snap.versionCheck.interval=NEVER
snap.home=/opt/snap
snap.userdir=${HOME}/.snap
snap.tilecache.size=1024
snap.jai.tileCacheSize=1024
EOF
    chown "$username:$username" "$home_dir/.snap/etc/snap.properties"

    # Configure SNAP Desktop preferences to suppress first-run dialogs
    mkdir -p "$home_dir/.snap/system/config/Preferences/org/esa/snap"
    cat > "$home_dir/.snap/system/config/Preferences/org/esa/snap/rcp.properties" << 'EOF'
# Suppress startup dialogs
showReleaseNotes=false
tips.showOnStartup=false
EOF
    chown -R "$username:$username" "$home_dir/.snap/system"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/SNAP.desktop" << 'EOF'
[Desktop Entry]
Name=SNAP Desktop
Comment=ESA Sentinel Application Platform
Exec=/opt/snap/bin/snap
Icon=/opt/snap/snap.png
Type=Application
Categories=Science;Education;Geography;
Terminal=false
StartupNotify=true
EOF
    chown "$username:$username" "$home_dir/Desktop/SNAP.desktop"
    chmod +x "$home_dir/Desktop/SNAP.desktop"

    # Create launch helper script
    cat > "$home_dir/launch_snap.sh" << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
export _JAVA_AWT_WM_NONREPARENTING=1
/opt/snap/bin/snap --nosplash &
LAUNCHEOF
    chown "$username:$username" "$home_dir/launch_snap.sh"
    chmod +x "$home_dir/launch_snap.sh"

    echo "SNAP setup complete for $username"
}

# Setup for main user
if id "ga" &>/dev/null; then
    setup_user_snap "ga" "/home/ga"
fi

# Warm-up launch of SNAP to trigger first-run initialization
# This ensures the NetBeans cache and modules are pre-initialized
echo "=== Performing SNAP warm-up launch ==="
su - ga -c "DISPLAY=:1 _JAVA_AWT_WM_NONREPARENTING=1 /opt/snap/bin/snap --nosplash > /tmp/snap_warmup.log 2>&1 &"

# Wait for SNAP to fully start (Java app, takes a while)
echo "Waiting for SNAP to start..."
SNAP_TIMEOUT=90
ELAPSED=0
while [ $ELAPSED -lt $SNAP_TIMEOUT ]; do
    if pgrep -f "/opt/snap/jre/bin/java" > /dev/null 2>&1 || pgrep -f "org.esa.snap" > /dev/null 2>&1; then
        echo "SNAP process detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for the SNAP window to appear
echo "Waiting for SNAP window..."
WINDOW_TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $WINDOW_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
        echo "SNAP window appeared after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Give it extra time for full initialization and dialogs
sleep 15

# Dismiss the "SNAP Update" dialog if it appears
# Check for plugin updates dialog: click "Remember my decision" then "No"
echo "Dismissing SNAP Update dialog if present..."
# Click "Remember my decision and don't ask again" checkbox (491,379 in 1280x720 -> 737,569 in 1920x1080)
DISPLAY=:1 xdotool mousemove 737 569 click 1 2>/dev/null || true
sleep 1
# Click "No" button (754,403 in 1280x720 -> 1131,605 in 1920x1080)
DISPLAY=:1 xdotool mousemove 1131 605 click 1 2>/dev/null || true
sleep 3

# Also try pressing Escape in case there are other dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Close SNAP gracefully after warm-up
echo "Closing SNAP warm-up instance..."
DISPLAY=:1 wmctrl -c "SNAP" 2>/dev/null || true
sleep 5

# Force kill if still running
pkill -f "/opt/snap/jre/bin/java" 2>/dev/null || true
pkill -f "org.esa.snap" 2>/dev/null || true
pkill -f "nbexec.*snap" 2>/dev/null || true
sleep 3

echo "=== SNAP setup complete ==="
