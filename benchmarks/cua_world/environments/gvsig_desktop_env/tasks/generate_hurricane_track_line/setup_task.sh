#!/bin/bash
set -e
echo "=== Setting up generate_hurricane_track_line task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/gvsig_data/exports
chown -R ga:ga /home/ga/Documents /home/ga/gvsig_data

# 2. Clean previous artifacts
rm -f /home/ga/gvsig_data/exports/katrina_track.*
rm -f /home/ga/Documents/katrina_waypoints.csv

# 3. Generate Real Hurricane Data (IBTrACS - Katrina 2005 snippet)
# We create it temporarily, then shuffle it to force the agent to use the 'SEQ' field.
cat > /tmp/katrina_raw.csv <<EOF
STORM_ID,SEQ,LAT,LON,WIND_KTS
KATRINA,1,23.2,-75.5,30
KATRINA,2,23.3,-75.7,30
KATRINA,3,23.4,-75.9,30
KATRINA,4,23.6,-76.0,30
KATRINA,5,24.0,-76.4,35
KATRINA,6,24.4,-76.6,35
KATRINA,7,24.5,-76.8,40
KATRINA,8,24.8,-77.0,40
KATRINA,9,25.2,-77.4,45
KATRINA,10,25.6,-77.9,50
KATRINA,11,26.0,-78.4,60
KATRINA,12,26.1,-79.0,70
KATRINA,13,26.2,-79.6,70
KATRINA,14,26.0,-80.1,65
KATRINA,15,25.9,-80.3,50
KATRINA,16,25.6,-80.8,40
KATRINA,17,25.4,-81.3,45
KATRINA,18,25.1,-82.0,50
KATRINA,19,24.9,-82.6,60
KATRINA,20,24.6,-83.3,65
KATRINA,21,24.4,-84.0,70
KATRINA,22,24.4,-84.6,75
KATRINA,23,24.5,-85.3,85
KATRINA,24,24.8,-85.9,95
KATRINA,25,25.1,-86.8,100
KATRINA,26,25.5,-87.7,115
KATRINA,27,26.3,-88.6,135
KATRINA,28,27.2,-89.2,150
KATRINA,29,28.2,-89.6,140
KATRINA,30,29.3,-89.7,110
KATRINA,31,30.2,-89.6,80
KATRINA,32,31.1,-89.6,50
KATRINA,33,32.2,-89.1,35
KATRINA,34,33.5,-88.5,30
KATRINA,35,34.9,-88.0,25
EOF

# 4. Create the User File (Shuffled Rows)
# Keep header, shuffle the rest
head -n 1 /tmp/katrina_raw.csv > /home/ga/Documents/katrina_waypoints.csv
tail -n +2 /tmp/katrina_raw.csv | shuf >> /home/ga/Documents/katrina_waypoints.csv

# Set ownership
chown ga:ga /home/ga/Documents/katrina_waypoints.csv
chmod 644 /home/ga/Documents/katrina_waypoints.csv

# 5. Launch gvSIG
kill_gvsig
launch_gvsig

# 6. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="