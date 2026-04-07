#!/bin/bash
set -e
echo "=== Setting up import_csv_column_mapping task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Kill any existing Subsurface instances for clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data (8 dives)
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"

# Create the target legacy CSV file to be imported
cat > /home/ga/Documents/legacy_log.csv << 'EOF'
2023-05-10,09:00,Blue Hole,35.5,45,26,Saw a manta ray
2023-05-11,10:30,Coral Garden,18.2,60,28,Lots of nudibranchs
2023-05-12,14:00,Shark Point,28.0,50,25,Strong current
EOF
chown ga:ga /home/ga/Documents/legacy_log.csv
chmod 644 /home/ga/Documents/legacy_log.csv
echo "Legacy CSV file created at /home/ga/Documents/legacy_log.csv"

# Remove any previous task output
rm -f /home/ga/Documents/dives.ssrf.bak 2>/dev/null || true

# Record initial state for anti-gaming
SSRF_INITIAL_MTIME=$(stat -c%Y /home/ga/Documents/dives.ssrf)
echo "$SSRF_INITIAL_MTIME" > /tmp/ssrf_initial_mtime.txt

# Ensure X server access
xhost +local: 2>/dev/null || true

# Launch Subsurface with the sample data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for Subsurface window to appear
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected"
        break
    fi
    sleep 2
done

# Additional wait for full UI initialization
sleep 5

# Dismiss any residual dialogs with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="