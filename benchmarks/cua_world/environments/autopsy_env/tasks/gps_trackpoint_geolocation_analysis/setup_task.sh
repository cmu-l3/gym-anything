#!/bin/bash
# Setup script for gps_trackpoint_geolocation_analysis task

echo "=== Setting up gps_trackpoint_geolocation_analysis task ==="
source /workspace/scripts/task_utils.sh

# 1. Clean up stale artifacts and old cases
rm -f /tmp/gps_trackpoint_result.json /tmp/gps_trackpoint_gt.json /tmp/gps_trackpoint_start_time 2>/dev/null || true
for d in /home/ga/Cases/SAR_GPS_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# 2. Synthesize FAT32 GPS Logger Disk Image dynamically
IMAGE="/home/ga/evidence/gps_logger.dd"
echo "Generating GPS Logger image at $IMAGE..."
mkdir -p /tmp/gps_gen

cat > /tmp/gps_gen/track.gpx << 'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" creator="Garmin" version="1.1">
  <trk>
    <name>SAR_Track</name>
    <trkseg>
      <trkpt lat="44.428000" lon="-110.588500"><time>2024-05-12T14:30:00Z</time></trkpt>
      <trkpt lat="44.428500" lon="-110.589000"><time>2024-05-12T14:45:00Z</time></trkpt>
      <trkpt lat="44.429200" lon="-110.590100"><time>2024-05-12T15:02:00Z</time></trkpt>
      <trkpt lat="44.430100" lon="-110.591500"><time>2024-05-12T15:30:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>
EOF

# Create a 10MB FAT32 image file
dd if=/dev/zero of="$IMAGE" bs=1M count=10 2>/dev/null
mkfs.vfat -F 32 -n "GPSLOGGER" "$IMAGE" >/dev/null
# Use mtools to copy the GPX file into the virtual filesystem
mcopy -i "$IMAGE" /tmp/gps_gen/track.gpx ::/track.gpx
chown ga:ga "$IMAGE"
rm -rf /tmp/gps_gen

# 3. Establish Ground Truth for Verification
cat > /tmp/gps_trackpoint_gt.json << 'EOF'
{
  "total_trackpoints": 4,
  "latest_timestamp": "2024-05-12T15:30:00Z",
  "last_known_latitude": 44.430100,
  "last_known_longitude": -110.591500
}
EOF

# 4. Record task start time (anti-gaming timestamp verification)
date +%s > /tmp/gps_trackpoint_start_time

# 5. Relaunch Autopsy and prep initial state
kill_autopsy
sleep 2
echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to launch GUI..."
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected."
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "WARNING: Autopsy Welcome screen did not appear in allotted time."
fi

# Dismiss popups 
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Autopsy window
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="