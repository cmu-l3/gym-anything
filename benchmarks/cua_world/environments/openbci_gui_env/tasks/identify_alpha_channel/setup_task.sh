#!/bin/bash
set -e
echo "=== Setting up identify_alpha_channel task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Ensure clean state
pkill -f "OpenBCI_GUI" 2>/dev/null || true
rm -f /home/ga/Documents/alpha_channel_result.txt

# ============================================================
# 1. Prepare Data
# ============================================================
EEG_FILE="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"
BACKUP_SOURCE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
DATA_SOURCE="/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"

# Ensure the recording file exists
if [ ! -f "$EEG_FILE" ]; then
    echo "Copying EEG recording..."
    mkdir -p "$(dirname "$EEG_FILE")"
    if [ -f "$DATA_SOURCE" ]; then
        cp "$DATA_SOURCE" "$EEG_FILE"
    elif [ -f "$BACKUP_SOURCE" ]; then
        cp "$BACKUP_SOURCE" "$EEG_FILE"
    else
        echo "ERROR: Source EEG data not found."
        # Create a dummy file if absolutely necessary to prevent immediate crash, 
        # but task will likely fail verification of ground truth.
        touch "$EEG_FILE"
    fi
    chown ga:ga "$EEG_FILE"
fi

# ============================================================
# 2. Compute Ground Truth (Hidden from Agent)
# ============================================================
# We use Python to calculate which channel actually has the max Alpha power.
# This ensures verification is robust even if data changes.

echo "Computing ground truth..."
cat > /tmp/compute_alpha.py << 'PYEOF'
import numpy as np
import sys
from scipy.signal import welch

file_path = "/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"

try:
    # Read OpenBCI txt format (skip header comments %, comma separated)
    # OpenBCI format usually has ID, Ch1...Ch8, Aux1...Aux3
    data = np.loadtxt(file_path, comments='%', delimiter=',', usecols=range(1, 9))
    
    # Filter valid data
    if data.shape[0] < 250: # Need at least 1 sec
        print("Error: Not enough data")
        sys.exit(1)

    # Calculate PSD using Welch's method
    # Fs = 250Hz for OpenBCI Cyton
    fs = 250
    freqs, psd = welch(data, fs=fs, axis=0, nperseg=250*2)

    # Alpha band: 8-12 Hz
    alpha_idx = np.logical_and(freqs >= 8, freqs <= 12)
    
    # Mean power in alpha band for each channel
    alpha_power = np.mean(psd[alpha_idx, :], axis=0)
    
    # Identify strongest channel (1-based index)
    strongest_ch = np.argmax(alpha_power) + 1
    
    # Get top 3 for partial credit/tolerance
    top_3 = np.argsort(alpha_power)[::-1][:3] + 1
    
    print(f"Strongest: {strongest_ch}")
    print(f"Top3: {list(top_3)}")
    
    with open("/tmp/ground_truth_alpha.txt", "w") as f:
        f.write(str(strongest_ch))
        
    with open("/tmp/ground_truth_top3.txt", "w") as f:
        for ch in top_3:
            f.write(f"{ch}\n")

except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

python3 /tmp/compute_alpha.py > /tmp/ground_truth_log.txt 2>&1 || echo "Ground truth computation failed"

echo "Ground truth computed: $(cat /tmp/ground_truth_alpha.txt 2>/dev/null)"

# ============================================================
# 3. Launch GUI
# ============================================================
echo "Launching OpenBCI GUI..."
# Launch via the wrapper that handles display and permissions
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci.log 2>&1 &"

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI"; then
        echo "OpenBCI window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="