#!/bin/bash
set -e

echo "=== Setting up distribution_fitting_anxiety task ==="

# 1. Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists in Documents (standard location for agent)
DATA_SRC="/opt/jasp_datasets/Exam Anxiety.csv"
DATA_DST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p "$(dirname "$DATA_DST")"

if [ -f "$DATA_SRC" ]; then
    cp "$DATA_SRC" "$DATA_DST"
    chown ga:ga "$DATA_DST"
    chmod 644 "$DATA_DST"
    echo "Dataset prepared at $DATA_DST"
else
    echo "ERROR: Source dataset not found at $DATA_SRC"
    # Fallback to verify if it was copied during env setup with different name
    if [ -f "/home/ga/Documents/JASP/ExamAnxiety.csv" ]; then
        echo "Dataset already exists at destination."
    else
        exit 1
    fi
fi

# 3. Clean up previous run artifacts
rm -f "/home/ga/Documents/JASP/Anxiety_Distributions.jasp" 2>/dev/null || true

# 4. Start JASP (Empty, no data loaded as per task description)
echo "Starting JASP..."
# Kill any existing instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_task.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 5. Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="