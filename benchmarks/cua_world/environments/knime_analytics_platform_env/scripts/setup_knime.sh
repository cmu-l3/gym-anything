#!/bin/bash
# set -euo pipefail

echo "=== Setting up KNIME Analytics Platform ==="

KNIME_DIR="/opt/knime"
KNIME_WORKSPACE="/home/ga/knime-workspace"

# -------------------------------------------------------
# Setup KNIME configuration for ga user
# -------------------------------------------------------
setup_user_knime() {
    local username=$1
    local home_dir=$2

    echo "Setting up KNIME for user: $username"

    # Create workspace directory
    sudo -u $username mkdir -p "$KNIME_WORKSPACE"

    # Create Documents/data directory if not exists
    sudo -u $username mkdir -p "$home_dir/Documents/data"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # -------------------------------------------------------
    # Pre-configure KNIME preferences to suppress dialogs
    # -------------------------------------------------------

    # Create Eclipse configuration area for KNIME
    local knime_config_dir="$home_dir/.knime"
    sudo -u $username mkdir -p "$knime_config_dir"

    # Create KNIME preferences to suppress workspace chooser dialog
    # and telemetry dialog
    sudo -u $username mkdir -p "$home_dir/.eclipse"

    # Write KNIME preferences to disable first-run dialogs
    cat > "$knime_config_dir/knime-preferences.epf" << 'PREFEOF'
# KNIME Preferences
file_export_version=3.0
/instance/org.knime.workbench.core/knime.workspace.chooser.show=false
/instance/org.knime.core/knime.data.bigtable.enabled=true
/instance/org.eclipse.ui/showIntro=false
PREFEOF
    chown $username:$username "$knime_config_dir/knime-preferences.epf"

    # -------------------------------------------------------
    # Create desktop shortcut
    # -------------------------------------------------------
    cat > "$home_dir/Desktop/KNIME.desktop" << DESKTOPEOF
[Desktop Entry]
Name=KNIME Analytics Platform
Comment=Visual Data Analytics Platform
Exec=$KNIME_DIR/knime -data $KNIME_WORKSPACE
Icon=$KNIME_DIR/icon.xpm
StartupNotify=true
Terminal=false
Categories=Development;Science;DataVisualization;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/KNIME.desktop"
    chmod +x "$home_dir/Desktop/KNIME.desktop"
    echo "  - Created desktop shortcut"

    # -------------------------------------------------------
    # Create launch script
    # -------------------------------------------------------
    cat > "$home_dir/launch_knime.sh" << LAUNCHEOF
#!/bin/bash
# Launch KNIME Analytics Platform
export DISPLAY=\${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch KNIME with workspace pre-set (skips workspace chooser dialog)
$KNIME_DIR/knime -data $KNIME_WORKSPACE "\$@" > /tmp/knime_\$USER.log 2>&1 &

echo "KNIME Analytics Platform started"
echo "Log file: /tmp/knime_\$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_knime.sh"
    chmod +x "$home_dir/launch_knime.sh"
    echo "  - Created launch script"

    echo "  - KNIME setup complete for $username"
}

# -------------------------------------------------------
# Wait for desktop to be ready
# -------------------------------------------------------
echo "Waiting for desktop to be ready..."
sleep 5

# Setup for ga user
if id "ga" &>/dev/null; then
    setup_user_knime "ga" "/home/ga"
fi

# -------------------------------------------------------
# Ensure data files are in place
# -------------------------------------------------------
if [ -d /workspace/data ]; then
    # Copy mounted data to user directory if install script didn't download them
    for f in /workspace/data/*.csv; do
        if [ -f "$f" ]; then
            fname=$(basename "$f")
            if [ ! -f "/home/ga/Documents/data/$fname" ]; then
                cp "$f" "/home/ga/Documents/data/$fname"
                chown ga:ga "/home/ga/Documents/data/$fname"
                echo "Copied $fname from mounted data"
            fi
        fi
    done
fi

# -------------------------------------------------------
# Warm-up launch: start KNIME once to initialize workspace
# and dismiss any first-run dialogs, then close
# -------------------------------------------------------
echo "=== Warm-up launch of KNIME ==="

# Launch KNIME with workspace specified (skips workspace chooser)
# XAUTHORITY must be set explicitly for X11 access from root/su context
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority nohup $KNIME_DIR/knime -data $KNIME_WORKSPACE > /tmp/knime_warmup.log 2>&1 &"

# Wait for KNIME window to appear (it's a Java app, may take time)
KNIME_READY=false
for i in $(seq 1 120); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "KNIME"; then
        echo "KNIME window detected after ${i}s"
        KNIME_READY=true
        break
    fi
    sleep 1
done

if [ "$KNIME_READY" = true ]; then
    # Give KNIME a few more seconds to fully initialize
    sleep 5

    # Dismiss any dialogs that may appear:
    # 1. "Help Improve KNIME" telemetry dialog - press Escape or click "No"
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # 2. Close any welcome/intro tabs
    DISPLAY=:1 xdotool key ctrl+w 2>/dev/null || true
    sleep 1

    echo "KNIME warm-up launch successful, shutting down..."
else
    echo "WARNING: KNIME window did not appear during warm-up (may still be loading)"
    sleep 10
fi

# Kill KNIME after warm-up (must kill all related processes)
pkill -u ga -f "knime" 2>/dev/null || true
pkill -u ga -f "eclipse" 2>/dev/null || true
pkill -u ga -f "equochro" 2>/dev/null || true
sleep 3
# Force kill if still running
pkill -9 -u ga -f "knime" 2>/dev/null || true
pkill -9 -u ga -f "eclipse" 2>/dev/null || true
pkill -9 -u ga -f "java.*knime" 2>/dev/null || true
pkill -9 -u ga -f "equochro" 2>/dev/null || true
sleep 2

# CRITICAL: Remove workspace lock file so KNIME can relaunch
rm -f "$KNIME_WORKSPACE/.metadata/.lock"
rm -f "$KNIME_WORKSPACE/.metadata/.plugins/org.eclipse.core.resources/.snap"

echo "KNIME warm-up complete"

echo "=== KNIME Analytics Platform setup complete ==="
echo "KNIME is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '$KNIME_DIR/knime -data $KNIME_WORKSPACE' from terminal"
echo "  - Run '~/launch_knime.sh' for quick launch"
