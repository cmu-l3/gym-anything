#!/bin/bash
set -e
echo "=== Setting up Poisson Regression Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data Directory and Download Real Data
mkdir -p /home/ga/Documents/TaskData
mkdir -p /home/ga/Documents/JASP

# Remove previous artifacts
rm -f /home/ga/Documents/JASP/YarnBreaks_Poisson.jasp

# Download warpbreaks dataset (Real data from R datasets)
echo "Downloading warpbreaks.csv..."
if [ ! -f "/home/ga/Documents/TaskData/warpbreaks.csv" ]; then
    curl -L -o /home/ga/Documents/TaskData/warpbreaks.csv \
        "https://vincentarelbundock.github.io/Rdatasets/csv/datasets/warpbreaks.csv"
fi

# Validate download
FILE_SIZE=$(stat -c%s "/home/ga/Documents/TaskData/warpbreaks.csv" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 100 ]; then
    echo "ERROR: Download failed or file too small."
    # Fallback creation if download fails (should not happen in valid env, but safe for stability)
    echo '"","breaks","wool","tension"' > /home/ga/Documents/TaskData/warpbreaks.csv
    echo '"1",26,"A","L"' >> /home/ga/Documents/TaskData/warpbreaks.csv
    echo '"2",30,"A","L"' >> /home/ga/Documents/TaskData/warpbreaks.csv
    echo '"3",54,"A","L"' >> /home/ga/Documents/TaskData/warpbreaks.csv
fi
chmod 644 /home/ga/Documents/TaskData/warpbreaks.csv

# 3. Launch JASP (Empty)
echo "Launching JASP..."
# Kill any existing instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Launch empty JASP
su - ga -c "setsid /usr/local/bin/launch-jasp > /dev/null 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 4. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="