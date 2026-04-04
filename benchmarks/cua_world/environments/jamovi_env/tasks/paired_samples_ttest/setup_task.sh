#!/bin/bash
set -e

echo "=== Setting up Paired Samples T-Test Task ==="

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/Jamovi/SleepWide.csv
rm -f /home/ga/Documents/Jamovi/SleepPairedTest.omv
rm -f /home/ga/Documents/Jamovi/paired_ttest_results.txt
rm -f /tmp/task_result.json

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Prepare the Wide Format Dataset
# The original Sleep.csv is long format (extra, group, ID). We need to pivot it.
# We'll use a small python script to do this robustly.

cat << 'EOF' > /tmp/reshape_sleep.py
import csv
import os

input_path = "/home/ga/Documents/Jamovi/Sleep.csv"
output_path = "/home/ga/Documents/Jamovi/SleepWide.csv"

# Check if input exists (should be there from env setup)
if not os.path.exists(input_path):
    print(f"Error: {input_path} not found.")
    exit(1)

data = {}
try:
    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        # Expected cols: extra, group, ID (implicit or explicit)
        # The standard R dataset has rows 1-10 as group 1, 11-20 as group 2.
        # We will assume row order implies ID 1-10 for group 1 and 1-10 for group 2.
        rows = list(reader)
        
        # Split by group
        group1 = [r for r in rows if r['group'].strip() == '1']
        group2 = [r for r in rows if r['group'].strip() == '2']
        
        # Ensure we have pairs
        min_len = min(len(group1), len(group2))
        
        with open(output_path, 'w', newline='') as out:
            writer = csv.writer(out)
            writer.writerow(['Patient', 'Drug1', 'Drug2'])
            for i in range(min_len):
                writer.writerow([i+1, group1[i]['extra'], group2[i]['extra']])
                
    print(f"Created {output_path} with {min_len} rows.")
    os.chmod(output_path, 0o666)
except Exception as e:
    print(f"Failed to reshape data: {e}")
    exit(1)
EOF

# Run the reshape script
python3 /tmp/reshape_sleep.py

# 4. Launch Jamovi (Clean State - No Data Loaded)
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    # Launch empty Jamovi
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize Window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Fallback if title isn't active
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="