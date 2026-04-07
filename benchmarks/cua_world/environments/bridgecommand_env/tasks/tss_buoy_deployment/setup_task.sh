#!/bin/bash
set -e
echo "=== Setting up TSS Buoy Deployment Task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/Hydrography
mkdir -p /opt/bridgecommand/Scenarios

# Clean up any previous run
rm -rf "/opt/bridgecommand/Scenarios/z) Experimental TSS" 2>/dev/null || true

# Create the Surveyor's Memo with DMS coordinates
cat > /home/ga/Documents/Hydrography/TSS_Proposal_Memo.txt << 'EOF'
MEMORANDUM
FROM: Port Hydrographic Office
TO: Simulation Technical Team
DATE: 2026-03-08
SUBJECT: Coordinates for Experimental TSS Zone

Please visualize the following proposed traffic separation zone in the simulator.
The zone is defined by 6 buoys.

COORDINATES (WGS84):

1. Buoy 1 (NW Corner)
   Lat:  50° 48' 15.0" N
   Long: 001° 18' 30.0" W

2. Buoy 2 (NE Corner)
   Lat:  50° 48' 15.0" N
   Long: 001° 17' 00.0" W

3. Buoy 3 (SW Corner)
   Lat:  50° 47' 45.0" N
   Long: 001° 18' 30.0" W

4. Buoy 4 (SE Corner)
   Lat:  50° 47' 45.0" N
   Long: 001° 17' 00.0" W

5. Buoy 5 (West Gate)
   Lat:  50° 48' 00.0" N
   Long: 001° 18' 30.0" W

6. Buoy 6 (East Gate)
   Lat:  50° 48' 00.0" N
   Long: 001° 17' 00.0" W

Note: Bridge Command requires Decimal Degrees format.
Please ensure high precision during conversion.
EOF

chown -R ga:ga /home/ga/Documents/Hydrography

# Setup initial window state
# Open the file manager to the documents folder
su - ga -c "DISPLAY=:1 nautilus /home/ga/Documents/Hydrography &"
sleep 2

# Open the text file so it's immediately visible
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/Hydrography/TSS_Proposal_Memo.txt &"
sleep 2

# Maximize text editor if possible (gedit/mousepad)
DISPLAY=:1 wmctrl -r "Memo" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="