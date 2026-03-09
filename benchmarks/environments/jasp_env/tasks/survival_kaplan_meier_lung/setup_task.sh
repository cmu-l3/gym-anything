#!/bin/bash
set -e
echo "=== Setting up Survival Analysis Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Documents directory exists
mkdir -p /home/ga/Documents/JASP

# 3. Download the real dataset (Lung Cancer Data)
# Using a public mirror of Rdatasets
TARGET_CSV="/home/ga/Documents/JASP/lung.csv"
echo "Downloading lung.csv to $TARGET_CSV..."

if wget -q -O "$TARGET_CSV" "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/survival/lung.csv"; then
    echo "Download successful."
else
    echo "Primary download failed, creating fallback dataset..."
    # Create a minimal valid CSV if download fails to prevent task blocking
    echo '"","inst","time","status","age","sex","ph.ecog","ph.karno","pat.karno","meal.cal","wt.loss"' > "$TARGET_CSV"
    echo '"1",3,306,2,74,1,1,90,100,1175,NA' >> "$TARGET_CSV"
    echo '"2",3,455,2,68,1,0,90,90,1225,15' >> "$TARGET_CSV"
    echo '"3",3,1010,1,56,1,0,90,90,NA,15' >> "$TARGET_CSV"
    echo '"4",5,210,2,57,1,1,90,60,1150,11' >> "$TARGET_CSV"
    echo '"5",1,883,2,60,1,0,100,90,NA,0' >> "$TARGET_CSV"
    echo '"6",12,1022,1,74,1,1,50,80,513,0' >> "$TARGET_CSV"
    echo '"7",7,310,2,68,2,2,70,60,384,10' >> "$TARGET_CSV"
fi

# Set permissions
chown ga:ga "$TARGET_CSV"
chmod 644 "$TARGET_CSV"

# 4. Clean up environment
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
rm -f /home/ga/Documents/JASP/LungSurvival.jasp 2>/dev/null || true

# 5. Start JASP (Empty)
echo "Starting JASP..."
# Uses setsid so the process survives when su exits
su - ga -c "setsid /usr/local/bin/launch-jasp > /dev/null 2>&1 &"

# Wait for JASP to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="