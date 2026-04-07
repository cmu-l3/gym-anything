#!/bin/bash
echo "=== Setting up run_flanker_task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Ensure PEBL battery directory is accessible
BATTERY_DIR=""
if [ -d /home/ga/pebl/battery ]; then
    BATTERY_DIR="/home/ga/pebl/battery"
elif [ -d /opt/pebl/battery ]; then
    # Copy battery to writable location (PEBL needs write access for data output)
    mkdir -p /home/ga/pebl
    cp -r /opt/pebl/battery /home/ga/pebl/battery
    chown -R ga:ga /home/ga/pebl/battery
    BATTERY_DIR="/home/ga/pebl/battery"
fi

# Verify flanker experiment exists
if [ ! -f "$BATTERY_DIR/flanker/flanker.pbl" ]; then
    echo "ERROR: flanker.pbl not found in $BATTERY_DIR/flanker/"
    exit 1
fi
echo "Flanker experiment found at: $BATTERY_DIR/flanker/flanker.pbl"

# Create data output directory with correct permissions
mkdir -p /home/ga/pebl/data
chown -R ga:ga /home/ga/pebl

# Remove any previous flanker data for subject 101 to avoid conflict dialogs
rm -rf /home/ga/pebl/battery/flanker/data/flanker-101* 2>/dev/null
rm -rf /home/ga/pebl/data/flanker-101* 2>/dev/null

# Get ga user's DBUS session address (needed for gnome-terminal)
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal window for the agent to use
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=100x30 -- bash -c 'echo Ready to run PEBL experiments.; echo; echo The PEBL interpreter is available as: run-pebl; echo PEBL battery directory: /home/ga/pebl/battery/; echo; echo Type run-pebl --help for usage information.; echo; bash' > /tmp/terminal.log 2>&1 &"

# Wait for terminal to appear
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Terminal window found: $WID"
        # Wait for window to be fully mapped before maximizing
        sleep 2
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowactivate "$WID" 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== run_flanker_task setup complete ==="
