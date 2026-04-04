#!/bin/bash
set -e
echo "=== Setting up Biomechanics Gait Viz Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback utilities if task_utils missing
if ! type launch_geogebra &>/dev/null; then
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra.log 2>&1 &"; }
    wait_for_window() { sleep 10; }
    maximize_geogebra() { true; }
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Prepare Directories
mkdir -p /home/ga/Documents/GeoGebra/data
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 2. Generate Real Gait Data CSV (Simplified Winter Data)
# Format: Index, HipAngle(deg), KneeAngle(deg)
# Angles approximate normal walking cycle
cat > /home/ga/Documents/GeoGebra/data/gait_kinematics.csv << EOF
Index,HipAngle,KneeAngle
1,30.0,0.0
2,29.3,1.5
3,28.5,4.0
4,27.0,8.0
5,25.0,14.0
6,22.0,18.5
7,18.0,15.0
8,14.0,10.0
9,10.0,5.0
10,6.0,2.0
11,2.0,0.5
12,-1.0,0.0
13,-4.0,0.0
14,-7.0,0.0
15,-9.0,0.0
16,-10.5,0.0
17,-11.0,0.0
18,-11.0,0.0
19,-10.0,2.0
20,-8.0,8.0
21,-5.0,15.0
22,-1.0,25.0
23,5.0,35.0
24,12.0,45.0
25,18.0,55.0
26,24.0,60.0
27,28.0,62.0
28,31.0,60.0
29,33.0,55.0
30,34.0,48.0
31,34.0,40.0
32,33.5,32.0
33,32.5,24.0
34,31.5,16.0
35,30.5,10.0
36,30.0,5.0
37,29.8,2.0
38,30.0,0.0
39,30.2,0.0
40,30.5,0.0
41,30.8,0.0
42,31.0,0.0
43,31.0,0.0
44,31.0,0.0
45,30.8,0.0
46,30.5,0.0
47,30.2,0.0
48,30.0,0.0
49,30.0,0.0
50,30.0,0.0
51,30.0,0.0
EOF
chown ga:ga /home/ga/Documents/GeoGebra/data/gait_kinematics.csv

# 3. Clean previous artifacts
rm -f /home/ga/Documents/GeoGebra/projects/gait_viz.ggb

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for load
wait_for_window "GeoGebra" 30
sleep 5

# Maximize
maximize_geogebra
sleep 2

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="