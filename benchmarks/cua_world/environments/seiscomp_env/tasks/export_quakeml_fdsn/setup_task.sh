#!/bin/bash
echo "=== Setting up export_quakeml_fdsn task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure SeisComP & Database are running ───────────────────────────────
ensure_scmaster_running

# ─── 2. Prepare the environment ──────────────────────────────────────────────
# Ensure the exports directory exists but is empty
mkdir -p /home/ga/exports
rm -f /home/ga/exports/noto_quakeml.xml
chown -R ga:ga /home/ga/exports

# ─── 3. Fetch Ground Truth from Database ─────────────────────────────────────
# We dynamically get the exact ground truth values from the DB to prevent gaming
# and ensure the verifier accurately checks against the specific environment state.
echo "Fetching ground truth values from SeisComP DB..."
DB_QUERY="
SELECT o.latitude_value, o.longitude_value, m.magnitude_value
FROM Event e
JOIN Origin o ON e.preferredOriginID = o.publicID
JOIN Magnitude m ON e.preferredMagnitudeID = m.publicID
LIMIT 1;
"

GT_VALUES=$(mysql -u sysop -psysop seiscomp -N -e "$DB_QUERY" 2>/dev/null)

if [ -n "$GT_VALUES" ]; then
    GT_LAT=$(echo "$GT_VALUES" | awk '{print $1}')
    GT_LON=$(echo "$GT_VALUES" | awk '{print $2}')
    GT_MAG=$(echo "$GT_VALUES" | awk '{print $3}')
    
    echo "Ground Truth - Lat: $GT_LAT, Lon: $GT_LON, Mag: $GT_MAG"
    
    # Save ground truth for the export script (hidden from agent)
    cat > /tmp/ground_truth.json << EOF
{
    "lat": $GT_LAT,
    "lon": $GT_LON,
    "mag": $GT_MAG
}
EOF
else
    echo "WARNING: Ground truth data not found in database! Assuming default Noto params."
    cat > /tmp/ground_truth.json << EOF
{
    "lat": 37.23,
    "lon": 136.99,
    "mag": 7.5
}
EOF
fi

chmod 600 /tmp/ground_truth.json

# ─── 4. Setup Agent GUI (Terminal) ───────────────────────────────────────────
# Kill any existing terminals
pkill -f "gnome-terminal" 2>/dev/null || true
sleep 1

# Launch a terminal for the agent to work in
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
sleep 3

# Focus and maximize terminal
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="