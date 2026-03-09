#!/bin/bash
set -e
echo "=== Setting up missing_value_configuration_toothgrowth task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/Jamovi/ToothGrowth_Sentinels.csv
rm -f /home/ga/Documents/Jamovi/ToothGrowth_Cleaned.omv
rm -f /home/ga/Documents/Jamovi/corrected_mean.txt
rm -f /tmp/ground_truth_mean.txt

# Generate the dataset with sentinel values using Python
# We use the existing ToothGrowth.csv as base
cat << 'EOF' > /tmp/prepare_data.py
import pandas as pd
import numpy as np
import os

# Load original clean data
source_path = "/home/ga/Documents/Jamovi/ToothGrowth.csv"
if not os.path.exists(source_path):
    # Fallback if file missing (should be there from env setup)
    print("Downloading fallback dataset...")
    url = "https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/datasets/ToothGrowth.csv"
    df = pd.read_csv(url)
    # Rdatasets often have an index column, drop it if unnamed
    if "Unnamed: 0" in df.columns:
        df = df.drop(columns=["Unnamed: 0"])
else:
    df = pd.read_csv(source_path)

# Ensure 'len' is numeric
df['len'] = pd.to_numeric(df['len'], errors='coerce')

# Calculate ground truth mean (excluding what will become -99)
# We will corrupt specific indices to make it deterministic
indices_to_corrupt = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
# Ensure indices are within bounds
indices_to_corrupt = [i for i in indices_to_corrupt if i < len(df)]

# Calculate true mean of the subset that WON'T be corrupted
# (The task asks to treat -99 as missing, so the result should correspond 
# to the mean of the remaining valid rows)
valid_mask = ~df.index.isin(indices_to_corrupt)
true_mean = df.loc[valid_mask, 'len'].mean()

# Apply corruption
df.loc[indices_to_corrupt, 'len'] = -99

# Save prepared dataset
output_path = "/home/ga/Documents/Jamovi/ToothGrowth_Sentinels.csv"
df.to_csv(output_path, index=False)
print(f"Created {output_path} with {len(indices_to_corrupt)} sentinel values")

# Save ground truth for verification
with open("/tmp/ground_truth_mean.txt", "w") as f:
    f.write(f"{true_mean:.4f}")
print(f"Ground truth mean: {true_mean:.4f}")
EOF

# Execute the python script
python3 /tmp/prepare_data.py

# Ensure permissions
chown ga:ga /home/ga/Documents/Jamovi/ToothGrowth_Sentinels.csv
chown ga:ga /tmp/ground_truth_mean.txt

# Start Jamovi (empty state, agent must open file)
if ! pgrep -f "jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected"
            break
        fi
        sleep 1
    done
    
    # Maximize
    sleep 5
    DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="