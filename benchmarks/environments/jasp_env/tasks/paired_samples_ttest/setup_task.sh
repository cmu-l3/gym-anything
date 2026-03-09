#!/bin/bash
set -e
echo "=== Setting up Paired Samples T-Test task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Create wide-format Sleep dataset ---
echo "Reshaping Sleep.csv to wide format..."

SLEEP_CSV="/home/ga/Documents/JASP/Sleep.csv"
WIDE_CSV="/home/ga/Documents/JASP/SleepWide.csv"

# Ensure source exists (should be there from env setup)
if [ ! -f "$SLEEP_CSV" ]; then
    # Fallback copy if missing
    cp "/opt/jasp_datasets/Sleep.csv" "$SLEEP_CSV" 2>/dev/null || true
fi

# Python script to convert long to wide
python3 << 'PYEOF'
import csv
import os

input_path = "/home/ga/Documents/JASP/Sleep.csv"
output_path = "/home/ga/Documents/JASP/SleepWide.csv"

if not os.path.exists(input_path):
    print(f"Error: {input_path} not found")
    exit(1)

# Read the long-format Sleep.csv
rows = []
with open(input_path, "r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

if not rows:
    print("Error: No data in source file")
    exit(1)

# Detect columns
headers = list(rows[0].keys())
extra_col = next((h for h in headers if h.lower().strip() in ["extra", "extra_sleep"]), headers[0])
group_col = next((h for h in headers if h.lower().strip() in ["group", "drug"]), headers[1])
id_col = next((h for h in headers if h.lower().strip() in ["id", "patient"]), headers[2])

print(f"Mapping: ID={id_col}, Group={group_col}, Value={extra_col}")

# Transform data
data = {}
for row in rows:
    pid = row[id_col].strip()
    grp = row[group_col].strip()
    val = row[extra_col].strip()
    
    if pid not in data:
        data[pid] = {}
    data[pid][grp] = val

# Write wide format
groups = sorted(list(set(g for pid in data for g in data[pid])))
if len(groups) < 2:
    # Handle case where groups might be "1" and "2"
    groups = ["1", "2"]

with open(output_path, "w", newline="") as f:
    writer = csv.writer(f)
    # Header: ID, Drug1, Drug2
    writer.writerow(["ID", "Drug1", "Drug2"])
    
    # Sort by ID
    for pid in sorted(data.keys(), key=lambda x: int(x) if x.isdigit() else x):
        # Map group 1 to Drug1, group 2 to Drug2
        # Assuming groups are '1' and '2' as in original Student dataset
        val1 = data[pid].get(groups[0], "")
        val2 = data[pid].get(groups[1], "")
        writer.writerow([pid, val1, val2])

print(f"Converted {len(data)} records to wide format at {output_path}")
PYEOF

chown ga:ga "$WIDE_CSV"
chmod 644 "$WIDE_CSV"

# --- Clean up previous results ---
rm -f /home/ga/Documents/JASP/SleepPairedTTest.jasp

# --- Launch JASP (Empty) ---
echo "Starting JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP without arguments to start empty
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_task.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "JASP"; then
        echo "JASP window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss welcome/update dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="