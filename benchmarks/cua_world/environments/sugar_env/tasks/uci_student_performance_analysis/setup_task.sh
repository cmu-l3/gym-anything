#!/bin/bash
echo "=== Setting up uci_student_performance_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous runs
rm -rf /home/ga/Documents/student_data
rm -f /home/ga/Documents/grade_analysis.py
rm -f /home/ga/Documents/school_comparison.txt
rm -f /home/ga/Documents/student.zip

# Download the real UCI student performance dataset
wget -q -O /home/ga/Documents/student.zip "https://archive.ics.uci.edu/static/public/320/student+performance.zip"

# Create a fallback just in case the URL is down so the task doesn't completely break
if [ ! -s /home/ga/Documents/student.zip ]; then
    echo "WARNING: Failed to download dataset. Creating fallback..."
    mkdir -p /tmp/fallback_student
    cat > /tmp/fallback_student/student-por.csv << 'EOF'
school;sex;age;address;famsize;Pstatus;Medu;Fedu;Mjob;Fjob;reason;guardian;traveltime;studytime;failures;schoolsup;famsup;paid;activities;nursery;higher;internet;romantic;famrel;freetime;goout;Dalc;Walc;health;absences;G1;G2;G3
GP;F;18;U;GT3;A;4;4;at_home;teacher;course;mother;2;2;0;yes;no;no;no;yes;yes;no;no;4;3;4;1;1;3;4;0;11;11
GP;F;17;U;GT3;T;1;1;at_home;other;course;father;1;2;0;no;yes;no;no;no;yes;yes;no;5;3;3;1;1;3;2;9;11;11
MS;M;18;R;LE3;T;1;1;other;other;course;mother;2;1;0;no;no;no;no;no;yes;yes;no;4;3;3;2;2;5;0;11;11;10
MS;M;17;U;GT3;T;4;3;other;other;course;mother;1;2;0;no;no;no;no;yes;yes;yes;no;5;4;5;1;2;5;0;10;11;11
EOF
    cd /tmp/fallback_student && zip /home/ga/Documents/student.zip student-por.csv
    rm -rf /tmp/fallback_student
fi
chown ga:ga /home/ga/Documents/student.zip

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/uci_student_performance_start_ts
chmod 666 /tmp/uci_student_performance_start_ts

# Close any open activity first to return to the home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Take initial state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/student_perf_task_start.png" 2>/dev/null || true

echo "=== setup complete ==="