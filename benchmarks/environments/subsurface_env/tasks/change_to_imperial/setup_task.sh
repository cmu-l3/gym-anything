#!/bin/bash
set -e
echo "=== Setting up change_to_imperial task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored."

# Ensure metric units are configured at start (reset the preferences)
mkdir -p /home/ga/.config/Subsurface
cat > /home/ga/.config/Subsurface/Subsurface.conf << 'CONF_EOF'
[General]
CloudEnabled=false
AutoCloudStorage=false
CheckForUpdates=false
DefaultFilename=/home/ga/Documents/dives.ssrf

[Units]
pressure=0
temperature=0
length=0
volume=0
weight=0
time=0
CONF_EOF
chown -R ga:ga /home/ga/.config/Subsurface

xhost +local: 2>/dev/null || true

echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 2
done
sleep 5

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Change units from metric to imperial"
echo "============================================================"
echo ""
echo "Subsurface is open in metric mode (meters, bar, Celsius, kg)."
echo ""
echo "Please:"
echo "1. Open Preferences via the File or Edit menu"
echo "   (on Linux: File > Preferences or Edit > Preferences)."
echo "2. Find the Units section."
echo "3. Change to Imperial units:"
echo "   - Depth: feet"
echo "   - Pressure: psi"
echo "   - Temperature: Fahrenheit"
echo "   - Weight: lbs"
echo "4. Click OK/Apply to save the preferences."
echo "============================================================"
