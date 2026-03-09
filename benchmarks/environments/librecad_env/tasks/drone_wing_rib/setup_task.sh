#!/bin/bash
set -e
echo "=== Setting up Drone Wing Rib task ==="

# 1. Create the coordinate data file (NACA 0012 scaled to 200mm chord)
mkdir -p /home/ga/Documents/LibreCAD

cat > /home/ga/Documents/LibreCAD/naca0012_200mm.txt << 'EOF'
0.0,0.0
2.5,4.7
5.0,6.6
10.0,9.2
20.0,12.3
40.0,15.7
60.0,17.4
80.0,18.0
100.0,17.6
120.0,16.4
140.0,14.4
160.0,11.7
180.0,8.1
190.0,5.8
200.0,0.0
190.0,-5.8
180.0,-8.1
160.0,-11.7
140.0,-14.4
120.0,-16.4
100.0,-17.6
80.0,-18.0
60.0,-17.4
40.0,-15.7
20.0,-12.3
10.0,-9.2
5.0,-6.6
2.5,-4.7
0.0,0.0
EOF

chown ga:ga /home/ga/Documents/LibreCAD/naca0012_200mm.txt
chmod 644 /home/ga/Documents/LibreCAD/naca0012_200mm.txt

# 2. Cleanup previous runs
pkill -f librecad 2>/dev/null || true
rm -f /home/ga/Documents/LibreCAD/wing_rib.dxf

# 3. Start LibreCAD with a blank state
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"

# 4. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD detected."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="