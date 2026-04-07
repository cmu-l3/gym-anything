#!/bin/bash
echo "=== Setting up compute_event_magnitudes task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP services are running
ensure_scmaster_running

# 1. Ensure Global Config points to SDS (Critical for scamp to find data)
if ! grep -q "recordstream" "$SEISCOMP_ROOT/etc/global.cfg" 2>/dev/null; then
    echo "recordstream = sdsarchive:///home/ga/seiscomp/var/lib/archive" >> "$SEISCOMP_ROOT/etc/global.cfg"
    echo "Added recordstream to global.cfg"
fi

# 2. Get the Event ID of the Noto earthquake
EVENT_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT publicID FROM Event LIMIT 1" 2>/dev/null)

if [ -z "$EVENT_ID" ]; then
    echo "ERROR: No event found in database! Setup failed."
    exit 1
fi

echo "Target Event ID: $EVENT_ID"
echo "$EVENT_ID" > /tmp/target_event_id.txt

# 3. Strip existing Magnitudes and Amplitudes to force recalculation by the agent
echo "Stripping existing magnitudes/amplitudes from database..."
mysql -u sysop -psysop seiscomp <<EOF
DELETE FROM Magnitude;
DELETE FROM StationMagnitude;
DELETE FROM Amplitude;
EOF

# 4. Record initial counts (should be 0)
AMP_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Amplitude" 2>/dev/null || echo "0")
MAG_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Magnitude" 2>/dev/null || echo "0")

cat > /tmp/initial_state.json << EOF
{
    "event_id": "$EVENT_ID",
    "initial_amp_count": $AMP_COUNT,
    "initial_mag_count": $MAG_COUNT,
    "task_start_time": $(date +%s)
}
EOF

# 5. Open a terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize" &
    sleep 3
fi

# Focus and maximize terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="