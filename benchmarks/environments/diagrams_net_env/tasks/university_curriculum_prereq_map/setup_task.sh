#!/bin/bash
set -e
echo "=== Setting up University Curriculum Prerequisite Map Task ==="

# 1. Prepare Data
echo "Generating curriculum data..."
cat > /home/ga/Desktop/curriculum_data.csv << 'EOF'
Year,Semester,Code,Name,Prerequisites,Type
1,Fall,CS101,Intro to Programming,,Core
1,Fall,MATH101,Calculus I,,Math
1,Fall,ENG101,Technical Writing,,GenEd
1,Spring,CS102,Data Structures & Algo,CS101,Core
1,Spring,MATH102,Calculus II,MATH101,Math
1,Spring,PHYS101,Physics for Engineers,,GenEd
2,Fall,CS201,Computer Architecture,CS102,Core
2,Fall,MATH201,Linear Algebra,MATH102,Math
2,Fall,CS205,Discrete Mathematics,MATH101,Math
2,Spring,CS202,Operating Systems,CS201,Core
2,Spring,STAT205,Probability & Stats,MATH102,Math
3,Fall,CS300,Artificial Intelligence,CS102;STAT205,AI
3,Fall,CS305,Database Systems,CS102,Core
3,Spring,CS310,Machine Learning,CS300;MATH201,AI
3,Spring,CS315,Computer Vision,CS300;MATH201,AI
3,Spring,CS320,Software Engineering,CS305,Core
4,Fall,CS401,Robotics Kinematics,CS310;PHYS101,AI
4,Fall,CS405,Neural Networks,CS310,AI
4,Fall,ETHICS400,Ethics in AI,,GenEd
4,Spring,CS490,Senior Capstone Project,CS401;CS405,Core
EOF

chown ga:ga /home/ga/Desktop/curriculum_data.csv
chmod 644 /home/ga/Desktop/curriculum_data.csv

# 2. Clean previous outputs
rm -f /home/ga/Diagrams/ai_curriculum_map.drawio 2>/dev/null || true
rm -f /home/ga/Diagrams/ai_curriculum_map.pdf 2>/dev/null || true
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# 3. Record Timestamp
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io
echo "Launching draw.io..."
pkill -f drawio 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio_launch.log 2>&1 &"

# 5. Handle Update Dialog & Window
echo "Waiting for draw.io to initialize..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Aggressively dismiss "Update Available" or "Open File" dialogs
# Press Escape multiple times to clear blocking dialogs
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done

# Focus and Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 6. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="