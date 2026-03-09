#!/bin/bash
set -e
echo "=== Setting up CFA Big Five SEM task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# DATASET PREPARATION
# The default 'Big Five Personality Traits.csv' in JASP's Regression folder 
# typically contains aggregated scores (5 cols). For CFA, we need item-level data.
# We will generate a realistic 25-item dataset if the file doesn't have items.
# ==============================================================================

DATA_FILE="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

# Ensure directory exists
mkdir -p /home/ga/Documents/JASP

# Python script to check/generate item data
python3 << 'EOF'
import pandas as pd
import numpy as np
import os

data_path = "/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
needs_generation = True

if os.path.exists(data_path):
    try:
        df = pd.read_csv(data_path)
        # Check if we have item-like columns (e.g., N1, N2... or A1, A2...)
        # We look for at least 15 columns to support a 5-factor CFA
        if df.shape[1] >= 15:
            print("Existing dataset has enough columns.")
            needs_generation = False
        else:
            print(f"Existing dataset only has {df.shape[1]} columns. Generating items...")
    except Exception as e:
        print(f"Error reading dataset: {e}")

if needs_generation:
    print("Generating synthetic item-level Big Five dataset...")
    np.random.seed(42)
    n_samples = 250
    
    # Define factors and items
    factors = ['Neuroticism', 'Extraversion', 'Openness', 'Agreeableness', 'Conscientiousness']
    prefixes = ['N', 'E', 'O', 'A', 'C']
    
    data = {}
    
    for factor, prefix in zip(factors, prefixes):
        # Generate latent factor score
        latent = np.random.normal(0, 1, n_samples)
        
        # Generate 5 items per factor with noise
        for i in range(1, 6):
            # Loading around 0.7
            loading = 0.7 + np.random.normal(0, 0.05)
            noise = np.random.normal(0, np.sqrt(1 - loading**2), n_samples)
            item_score = loading * latent + noise
            
            # Scale to 1-5 Likert range (approx)
            item_score = np.round(item_score * 0.8 + 3)
            item_score = np.clip(item_score, 1, 5)
            
            data[f"{prefix}{i}"] = item_score
            
    df_new = pd.DataFrame(data)
    df_new.to_csv(data_path, index=False)
    print(f"Created {data_path} with {df_new.shape[1]} items.")

EOF

# Ensure permissions
chown ga:ga "$DATA_FILE"
chmod 666 "$DATA_FILE"

# ==============================================================================
# JASP LAUNCH
# ==============================================================================

# Kill any existing JASP
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Launch JASP with the dataset
echo "Launching JASP with dataset..."
# Uses setsid so the process survives when su exits
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATA_FILE' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="