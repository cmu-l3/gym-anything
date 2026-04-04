#!/bin/bash
set -e
echo "=== Setting up Gauge R&R Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure JASP documents directory exists
mkdir -p /home/ga/Documents/JASP

# Generate the Measurement Data CSV (Simulating a Gauge Study)
# 5 Parts, 3 Operators, 2 Replicates
# Format: Part, Operator, Measurement
cat > /home/ga/Documents/JASP/MeasurementData.csv << 'EOF'
Part,Operator,Measurement
1,A,10.1
1,A,10.2
1,B,10.0
1,B,10.1
1,C,10.2
1,C,10.1
2,A,11.2
2,A,11.1
2,B,11.0
2,B,11.1
2,C,11.1
2,C,11.2
3,A,12.0
3,A,12.1
3,B,11.9
3,B,12.0
3,C,12.1
3,C,12.0
4,A,13.2
4,A,13.1
4,B,13.0
4,B,13.1
4,C,13.1
4,C,13.2
5,A,14.1
5,A,14.0
5,B,14.0
5,B,13.9
5,C,14.1
5,C,14.0
EOF

# Set permissions
chown -R ga:ga /home/ga/Documents/JASP
chmod 644 /home/ga/Documents/JASP/MeasurementData.csv

# Remove any previous result file
rm -f /home/ga/Documents/JASP/GaugeStudy.jasp

# Launch JASP
# We use the launcher script created in the environment setup
# Setsid ensures it survives su exit
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp &"
    
    # Wait for window
    for i in {1..50}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window found."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="