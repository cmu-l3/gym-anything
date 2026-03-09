#!/bin/bash
set -e
echo "=== Setting up Repeated Measures ANOVA task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data
# Download Bugs dataset if not already present
DATA_DIR="/home/ga/Documents/JASP"
mkdir -p "$DATA_DIR"
BUGS_CSV="$DATA_DIR/Bugs.csv"
GROUND_TRUTH_DIR="/var/lib/jasp"
mkdir -p "$GROUND_TRUTH_DIR"

# Official JASP data library URL
URL="https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/3.%20ANOVA/Bugs.csv"

if [ ! -f "$BUGS_CSV" ]; then
    echo "Downloading Bugs.csv..."
    wget -q -O "$BUGS_CSV" "$URL" || { echo "Failed to download data"; exit 1; }
fi
chown -R ga:ga "$DATA_DIR"
chmod 644 "$BUGS_CSV"

# 3. Compute Ground Truth (Hidden from Agent)
# We calculate the means of the 4 columns to verify the agent's report later.
echo "Computing ground truth..."
python3 << EOF
import pandas as pd
import json
import os

try:
    df = pd.read_csv('$BUGS_CSV')
    # Filter for valid numeric rows if necessary, though this dataset is clean
    means = {
        'LDLF': float(df['LDLF'].mean()),
        'LDHF': float(df['LDHF'].mean()),
        'HDLF': float(df['HDLF'].mean()),
        'HDHF': float(df['HDHF'].mean())
    }
    # Standard output for debugging setup
    print(f"Calculated Means: {means}")
    
    with open('$GROUND_TRUTH_DIR/bugs_ground_truth.json', 'w') as f:
        json.dump(means, f)
except Exception as e:
    print(f"Error computing ground truth: {e}")
EOF

# 4. Setup Application State
# Kill any running JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP with the dataset
echo "Launching JASP..."
# JASP requires specific flags in some container envs; using the wrapper from environment
# setsid ensures it doesn't die when the shell exits
su - ga -c "setsid /usr/local/bin/launch-jasp '$BUGS_CSV' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP started."
        break
    fi
    sleep 1
done

# Maximize JASP
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus JASP
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="