#!/bin/bash
set -e
echo "=== Setting up regression_diagnostics_exam task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure JASP is clean (kill previous instances)
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# 3. Ensure the dataset exists in the Documents folder
# The environment install script places datasets in /opt/jasp_datasets and copies to /home/ga/Documents/JASP
# We verify it's there and has the correct name (Space-free names were handled in env setup, but we check specifically)
DATA_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATA_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p /home/ga/Documents/JASP

if [ ! -f "$DATA_DEST" ]; then
    echo "Copying dataset..."
    if [ -f "$DATA_SOURCE" ]; then
        cp "$DATA_SOURCE" "$DATA_DEST"
    else
        # Fallback if opt missing, though env should have it
        echo "WARNING: Source dataset not found in /opt, creating dummy for setup (this should not happen in valid env)"
        echo "Code,Revise,Exam,Anxiety,Gender" > "$DATA_DEST"
        echo "1,4,40,86.3,Male" >> "$DATA_DEST"
    fi
    chown ga:ga "$DATA_DEST"
fi

# Clean up any previous run outputs
rm -f /home/ga/Documents/JASP/RegressionDiagnostics.jasp
rm -f /home/ga/Documents/JASP/diagnostics_report.txt

# 4. Start JASP
# Use setsid to detach from the shell so it persists
echo "Starting JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp.log 2>&1 &"

# 5. Wait for window
echo "Waiting for JASP window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Pre-load the dataset? 
# Task description says "Load ... ExamAnxiety.csv" as step 1.
# To make it fair but not too easy, we leave JASP open on the Welcome screen 
# OR we can open the file. The task description implies the user does it.
# "Load '/home/ga/Documents/JASP/ExamAnxiety.csv'." -> Implies agent does it.
# So we just leave JASP open.

# 8. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="