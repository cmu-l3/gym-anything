#!/bin/bash
set -e
echo "=== Setting up Mediation Analysis Task ==="

# 1. Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data
# Ensure the dataset exists in the user's documents
DATA_SRC="/opt/jasp_datasets/Exam Anxiety.csv"
DATA_DST="/home/ga/Documents/JASP/ExamAnxiety.csv" # No spaces in filename for safety

mkdir -p "$(dirname "$DATA_DST")"

if [ -f "$DATA_SRC" ]; then
    cp "$DATA_SRC" "$DATA_DST"
    chown ga:ga "$DATA_DST"
    echo "Dataset copied to $DATA_DST"
else
    echo "ERROR: Source dataset not found at $DATA_SRC"
    # Fallback to creating a dummy if real data is missing (should not happen in prod env)
    echo "Code,Revise,Exam,Anxiety,Gender" > "$DATA_DST"
    echo "1,10,50,80,Male" >> "$DATA_DST"
fi

# 3. Clean previous run artifacts
rm -f "/home/ga/Documents/JASP/MediationAnalysis.jasp"
rm -f "/home/ga/Documents/JASP/mediation_report.txt"

# 4. Launch JASP
# We use pkill to ensure a clean slate
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

echo "Launching JASP with dataset..."
# Launch via su to run as user 'ga'
# setsid ensures the process isn't killed when the shell exits
# The launcher script handles the --no-sandbox flags required for JASP
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATA_DST' > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP to initialize
# JASP is a heavy Java+Qt application, takes time to start
echo "Waiting for JASP window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Extra sleep to ensure UI is responsive
sleep 5

# 6. Maximize and Focus
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss startup dialogs (e.g., 'Welcome' or 'Update')
# Press Escape a couple of times to clear potential popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="