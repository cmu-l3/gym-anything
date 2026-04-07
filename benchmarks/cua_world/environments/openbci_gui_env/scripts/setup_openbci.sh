#!/bin/bash
set -e

echo "=== Setting up OpenBCI GUI ==="

# Wait for desktop environment to be fully ready
sleep 8

export DISPLAY=:1
export XAUTHORITY=/run/user/1000/gdm/Xauthority

# ============================================================
# Create user directories for OpenBCI GUI data
# ============================================================
echo "Creating OpenBCI GUI data directories..."
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"

# Copy real EEG playback data to the recordings folder.
# Check /opt/openbci_data/ first (set by install), then fall back to /workspace/data/.
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"

# Eyes open baseline file (prefer the v5-compatible pre-built file)
EYES_OPEN_SRC=""
for candidate in \
    "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" \
    "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" \
    "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"; do
    if [ -f "$candidate" ] && [ "$(wc -c < "$candidate")" -gt 10000 ]; then
        EYES_OPEN_SRC="$candidate"
        break
    fi
done

if [ -n "$EYES_OPEN_SRC" ]; then
    echo "Copying EEG playback file (eyes open) from $EYES_OPEN_SRC..."
    cp "$EYES_OPEN_SRC" "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
    chown ga:ga "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
    echo "Copied: OpenBCI-EEG-S001-EyesOpen.txt"
else
    echo "WARNING: No EEG eyes-open recording found. Playback tasks may not work."
fi

# Motor imagery file
MOTOR_SRC=""
for candidate in \
    "/opt/openbci_data/OpenBCI-EEG-S001-MotorImagery.txt" \
    "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt"; do
    if [ -f "$candidate" ] && [ "$(wc -c < "$candidate")" -gt 10000 ]; then
        MOTOR_SRC="$candidate"
        break
    fi
done

if [ -n "$MOTOR_SRC" ]; then
    cp "$MOTOR_SRC" "${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"
    chown ga:ga "${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"
    echo "Copied: OpenBCI-EEG-S001-MotorImagery.txt"
fi

# Set ownership
chown -R ga:ga /home/ga/Documents/

# ============================================================
# Read the executable path set during installation
# ============================================================
OPENBCI_EXEC=$(cat /opt/openbci_exec_path.txt 2>/dev/null || echo "")
OPENBCI_BASE_DIR=$(cat /opt/openbci_base_dir.txt 2>/dev/null || echo "")

if [ -z "$OPENBCI_EXEC" ] || [ ! -f "$OPENBCI_EXEC" ]; then
    echo "ERROR: OpenBCI GUI executable not found. Check install log."
    exit 1
fi

echo "OpenBCI GUI executable: $OPENBCI_EXEC"
echo "OpenBCI base dir: $OPENBCI_BASE_DIR"

# Create launch script for ga user
cat > /home/ga/launch_openbci.sh << LAUNCHEOF
#!/bin/bash
export DISPLAY=\${DISPLAY:-:1}
export XAUTHORITY=/run/user/1000/gdm/Xauthority

# Kill any existing instance
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

# Launch OpenBCI GUI from its base directory (required for Processing apps)
cd "$OPENBCI_BASE_DIR"
exec "$OPENBCI_EXEC" "\$@"
LAUNCHEOF
chown ga:ga /home/ga/launch_openbci.sh
chmod +x /home/ga/launch_openbci.sh

# Create desktop shortcut
cat > /home/ga/Desktop/OpenBCI_GUI.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OpenBCI GUI
Comment=EEG/Biosignal Visualization and Analysis
Exec=/home/ga/launch_openbci.sh
Icon=applications-science
StartupNotify=true
Terminal=false
Categories=Science;Education;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OpenBCI_GUI.desktop
chmod +x /home/ga/Desktop/OpenBCI_GUI.desktop
# Mark desktop file as trusted (GNOME requirement)
su - ga -c "dbus-launch gio set /home/ga/Desktop/OpenBCI_GUI.desktop metadata::trusted true" 2>/dev/null || true

# ============================================================
# Warm-up launch: Start the GUI to initialize settings/prefs,
# then dismiss any first-run dialogs and kill it.
# This ensures subsequent task launches start cleanly.
# ============================================================
echo "Performing warm-up launch of OpenBCI GUI..."

# Launch OpenBCI GUI in background (setsid to prevent SIGHUP)
# NOTE: env vars MUST come BEFORE setsid, not inside setsid's argument list
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; \
    setsid bash /home/ga/launch_openbci.sh > /tmp/openbci_warmup.log 2>&1 &"

# Wait up to 45 seconds for the GUI window to appear
echo "Waiting for OpenBCI GUI window..."
GUI_STARTED=0
for i in $(seq 1 45); do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
       grep -i "openbci\|OpenBCI" > /dev/null 2>&1; then
        echo "OpenBCI GUI window detected after ${i}s"
        GUI_STARTED=1
        break
    fi
    sleep 1
done

if [ "$GUI_STARTED" -eq 1 ]; then
    echo "OpenBCI GUI started successfully"
    sleep 5  # Let any first-run dialogs appear

    # Dismiss any update/first-run dialogs by pressing Escape
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
    sleep 2

    # Kill the warm-up instance
    echo "Killing warm-up instance..."
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 3
    pkill -9 -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 2

    echo "Warm-up launch complete"
else
    echo "WARNING: OpenBCI GUI did not start within 45s during warm-up."
    echo "Warm-up log:"
    cat /tmp/openbci_warmup.log 2>/dev/null || true
    # Kill any partial processes
    pkill -9 -f "OpenBCI_GUI" 2>/dev/null || true
fi

# ============================================================
# Create shared utilities script for task setup scripts
# ============================================================
cat > /home/ga/openbci_task_utils.sh << 'UTILS_EOF'
#!/bin/bash
# Shared utilities for OpenBCI GUI task setup

OPENBCI_EXEC_PATH="$(cat /opt/openbci_exec_path.txt 2>/dev/null || echo '')"
OPENBCI_BASE_DIR_PATH="$(cat /opt/openbci_base_dir.txt 2>/dev/null || echo '')"

# Launch OpenBCI GUI and wait for window
launch_openbci() {
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 2

    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; \
        setsid bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"

    echo "Waiting for OpenBCI GUI window..."
    for i in $(seq 1 60); do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
           grep -i "openbci" > /dev/null 2>&1; then
            echo "OpenBCI GUI window appeared after ${i}s"
            return 0
        fi
        sleep 1
    done
    echo "WARNING: OpenBCI GUI window did not appear within 60s"
    return 1
}

# Wait for OpenBCI GUI window with polling
wait_for_openbci() {
    local timeout=${1:-30}
    for i in $(seq 1 $timeout); do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
           grep -i "openbci" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Click a coordinate on the OpenBCI GUI window
click_at() {
    local x=$1
    local y=$2
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove --sync $x $y click 1
    sleep 0.5
}

# Take a screenshot for verification
take_screenshot() {
    local path=${1:-/tmp/openbci_screenshot.png}
    # Use VNC-style screenshot for GNOME compositor (scrot fails with GNOME)
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool search --class "java" 2>/dev/null | tail -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xwd -id $WID -out /tmp/screen.xwd 2>/dev/null && \
            convert /tmp/screen.xwd "$path" 2>/dev/null || true
    fi
    # Fallback
    if [ ! -f "$path" ] || [ ! -s "$path" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || true
    fi
}
UTILS_EOF
chown ga:ga /home/ga/openbci_task_utils.sh
chmod +x /home/ga/openbci_task_utils.sh

# ============================================================
# Verify installation
# ============================================================
echo ""
echo "=== Setup Summary ==="
echo "OpenBCI GUI executable: $OPENBCI_EXEC"
echo "EEG Recordings:"
ls -la /home/ga/Documents/OpenBCI_GUI/Recordings/ 2>/dev/null || echo "(none)"
echo ""
echo "=== OpenBCI GUI setup complete ==="
