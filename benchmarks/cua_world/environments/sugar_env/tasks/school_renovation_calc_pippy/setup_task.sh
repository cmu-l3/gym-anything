#!/bin/bash
echo "=== Setting up school_renovation_calc_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output files
rm -f /home/ga/Documents/renovation_calc.py 2>/dev/null || true
rm -f /home/ga/Documents/renovation_report.txt 2>/dev/null || true

# Generate the specific CSV data
# The values sum exactly to Floor: 2939.5, Wall: 4266.2
cat > /home/ga/Documents/room_dimensions.csv << 'EOF'
Room Name,Length (m),Width (m),Height (m)
Classroom 1,7.0,7.0,3.0
Classroom 2,7.0,7.0,3.0
Classroom 3,7.0,7.0,3.0
Classroom 4,7.0,7.0,3.0
Classroom 5,7.0,7.0,3.0
Classroom 6,7.0,7.0,3.0
Classroom 7,7.0,7.0,3.0
Classroom 8,7.0,7.0,3.0
Classroom 9,7.0,7.0,3.0
Classroom 10,7.0,7.0,3.0
Classroom 11,7.0,7.0,3.0
Classroom 12,7.0,7.0,3.0
Classroom 13,7.0,7.0,3.0
Classroom 14,7.0,7.0,3.0
Classroom 15,7.0,7.0,3.0
Classroom 16,7.0,7.0,3.0
Classroom 17,7.0,7.0,3.0
Classroom 18,7.0,7.0,3.0
Classroom 19,7.0,7.0,3.0
Classroom 20,7.0,7.0,3.0
Classroom 21,7.0,7.0,3.0
Classroom 22,7.0,7.0,3.0
Classroom 23,7.0,7.0,3.0
Classroom 24,7.0,7.0,3.0
Classroom 25,7.0,7.0,3.0
Classroom 26,7.0,7.0,3.0
Classroom 27,7.0,7.0,3.0
Classroom 28,7.0,7.0,3.0
Classroom 29,7.0,7.0,3.0
Classroom 30,7.0,7.0,3.0
Library Main,15.0,12.0,3.5
Cafeteria,20.0,15.0,4.0
Gym,25.0,20.0,6.0
Auditorium,20.0,15.0,5.0
Office,10.0,4.25,3.0
Hallway,21.0,7.0,5.3875
EOF
chown ga:ga /home/ga/Documents/room_dimensions.csv

# Close any open activities first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar session is active
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take baseline screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="