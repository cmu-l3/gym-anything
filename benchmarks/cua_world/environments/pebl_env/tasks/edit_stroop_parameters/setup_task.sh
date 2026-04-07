#!/bin/bash
echo "=== Setting up edit_stroop_parameters task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Find the Stroop experiment script
STROOP_FILE=""
if [ -f /home/ga/pebl/battery/stroop-color/color-stroop.pbl ]; then
    STROOP_FILE="/home/ga/pebl/battery/stroop-color/color-stroop.pbl"
elif [ -f /opt/pebl/battery/stroop-color/color-stroop.pbl ]; then
    STROOP_FILE="/opt/pebl/battery/stroop-color/color-stroop.pbl"
fi

if [ -z "$STROOP_FILE" ]; then
    echo "ERROR: color-stroop.pbl not found"
    exit 1
fi

# Make a working copy that the user can edit
mkdir -p /home/ga/pebl/experiments
cp "$STROOP_FILE" /home/ga/pebl/experiments/color-stroop.pbl
chown ga:ga /home/ga/pebl/experiments/color-stroop.pbl
chmod 644 /home/ga/pebl/experiments/color-stroop.pbl

# Verify the parameters exist in the file
echo "Checking for custompractrials parameter..."
grep -n "custompractrials" /home/ga/pebl/experiments/color-stroop.pbl || echo "WARNING: custompractrials not found"
echo "Checking for customtrials parameter..."
grep -n "customtrials" /home/ga/pebl/experiments/color-stroop.pbl || echo "WARNING: customtrials not found"

# Get ga user's DBUS session address (needed for GUI apps launched via su)
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open the file in gedit text editor
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gedit /home/ga/pebl/experiments/color-stroop.pbl > /tmp/gedit.log 2>&1 &"

# Wait for gedit to appear
for i in $(seq 1 20); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "color-stroop" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "gedit window found: $WID"
        # Maximize the editor
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

if [ -z "$WID" ]; then
    echo "WARNING: gedit window not detected yet, may still be loading"
fi

echo "=== edit_stroop_parameters setup complete ==="
