#!/bin/bash
echo "=== Setting up generate_earthquake_kml task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
systemctl start mariadb || true
sleep 2

# Ensure scmaster is running
ensure_scmaster_running

# Verify event data exists in database
EVENT_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

if [ "$EVENT_COUNT" -eq "0" ]; then
    echo "ERROR: No events in database. Task cannot proceed."
    exit 1
fi

# Record ground truth from database for verification
ORIGIN_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT preferredOriginID FROM Event LIMIT 1" 2>/dev/null)

# Get origin details
GT_LAT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT o.latitude_value FROM Origin o JOIN PublicObject po ON o._oid = po._oid WHERE po.publicID = '$ORIGIN_ID'" 2>/dev/null | head -1)
GT_LON=$(mysql -u sysop -psysop seiscomp -N -e "SELECT o.longitude_value FROM Origin o JOIN PublicObject po ON o._oid = po._oid WHERE po.publicID = '$ORIGIN_ID'" 2>/dev/null | head -1)
GT_DEPTH=$(mysql -u sysop -psysop seiscomp -N -e "SELECT o.depth_value FROM Origin o JOIN PublicObject po ON o._oid = po._oid WHERE po.publicID = '$ORIGIN_ID'" 2>/dev/null | head -1)
GT_TIME=$(mysql -u sysop -psysop seiscomp -N -e "SELECT o.time_value FROM Origin o JOIN PublicObject po ON o._oid = po._oid WHERE po.publicID = '$ORIGIN_ID'" 2>/dev/null | head -1)

# Get magnitude details
MAG_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT preferredMagnitudeID FROM Event LIMIT 1" 2>/dev/null)
GT_MAG=$(mysql -u sysop -psysop seiscomp -N -e "SELECT m.magnitude_value FROM Magnitude m JOIN PublicObject po ON m._oid = po._oid WHERE po.publicID = '$MAG_ID'" 2>/dev/null | head -1)

# Store ground truth as JSON for the export script
cat > /tmp/ground_truth.json << EOF
{
    "lat": ${GT_LAT:-0},
    "lon": ${GT_LON:-0},
    "depth": ${GT_DEPTH:-0},
    "mag": ${GT_MAG:-0},
    "time": "${GT_TIME}"
}
EOF

echo "Ground truth recorded: lat=$GT_LAT, lon=$GT_LON, depth=$GT_DEPTH, mag=$GT_MAG"

# Remove any previous output to ensure clean state
rm -f /home/ga/earthquake_catalog.kml

# Open a terminal for the agent since this is a CLI/scripting task
su - ga -c "DISPLAY=:1 xfce4-terminal --maximize &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 gnome-terminal --maximize &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 xterm -maximized &" 2>/dev/null || true

sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="