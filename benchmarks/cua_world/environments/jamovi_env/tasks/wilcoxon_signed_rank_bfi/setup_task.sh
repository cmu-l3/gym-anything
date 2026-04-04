#!/bin/bash
set -e
echo "=== Setting up Wilcoxon Signed-Rank Test task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jamovi is not running initially (agent must start fresh or we launch empty)
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 3. Verify Data Existence
DATA_FILE="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: BFI25.csv not found. Attempting to restore from source..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        mv "/home/ga/Documents/Jamovi/BFI25.csv" "$DATA_FILE" 2>/dev/null || true
        chown ga:ga "$DATA_FILE"
    else
        echo "FATAL: Cannot restore BFI25.csv"
        exit 1
    fi
fi

# 4. Clean up previous run artifacts
rm -f /home/ga/Documents/Jamovi/WilcoxonSignedRank.omv
rm -f /home/ga/Documents/Jamovi/wilcoxon_results.txt

# 5. Compute Ground Truth (Hidden)
# We calculate the expected W, p-value, and Rank Biserial Correlation
mkdir -p /var/lib/jamovi_ground_truth
echo "Computing ground truth..."

python3 << 'PYEOF'
import csv
import sys
import os

# Install scipy if missing (needed for wilcoxon)
try:
    import scipy.stats
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "scipy"])
    import scipy.stats

bfi_path = "/home/ga/Documents/Jamovi/BFI25.csv"
gt_path = "/var/lib/jamovi_ground_truth/expected_values.txt"

e1_vals = []
e2_vals = []

try:
    with open(bfi_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                # Jamovi handles these as ordinal/continuous for the test
                e1 = float(row['E1'])
                e2 = float(row['E2'])
                e1_vals.append(e1)
                e2_vals.append(e2)
            except ValueError:
                continue

    if not e1_vals:
        print("Error: No data found")
        sys.exit(1)

    # Calculate Wilcoxon
    # Jamovi uses 'pratt' method for zeros by default? Or 'wilcox'? 
    # Standard Wilcoxon discards zeros. Scipy default is 'wilcox' (discard zeros).
    # Jamovi usually matches Scipy's default or R's wilcox.test
    
    # 1. W Statistic and p-value
    # Note: scipy returns the smaller of the two sums of ranks usually, or W statistic.
    # Jamovi reports W.
    stat, p_val = scipy.stats.wilcoxon(e1_vals, e2_vals)

    # 2. Rank Biserial Correlation
    # Formula: r = 4 * W / (N * (N + 1)) - 1  (Approx)
    # Or simple correlation of signed ranks
    # Jamovi uses: Matched-pairs rank biserial correlation
    # r = (Sum(R+) - Sum(R-)) / Total Sum of Ranks
    # Since Total Sum = N(N+1)/2
    # And W (in Jamovi) is usually Sum(R+)
    
    # Let's calculate manually to be sure about Rank Biserial
    diffs = [x - y for x, y in zip(e1_vals, e2_vals)]
    diffs = [d for d in diffs if d != 0] # Remove ties
    n = len(diffs)
    
    abs_diffs = [abs(d) for d in diffs]
    ranks = scipy.stats.rankdata(abs_diffs)
    
    w_pos = sum(r for d, r in zip(diffs, ranks) if d > 0)
    w_neg = sum(r for d, r in zip(diffs, ranks) if d < 0)
    
    # Check which one scipy returned
    # Scipy returns min(w_pos, w_neg)
    
    # Jamovi W is usually w_pos (Sum of positive ranks)
    jamovi_w = w_pos
    
    # Rank Biserial Correlation
    # r = (w_pos - w_neg) / (w_pos + w_neg)
    rank_biserial = (w_pos - w_neg) / (w_pos + w_neg)
    
    # p-value should match scipy
    
    with open(gt_path, 'w') as f:
        f.write(f"{jamovi_w}\n")
        f.write(f"{p_val}\n")
        f.write(f"{rank_biserial}\n")
        
    print(f"Calculated GT: W={jamovi_w}, p={p_val}, r={rank_biserial}")

except Exception as e:
    print(f"Failed to compute ground truth: {e}")
    sys.exit(1)
PYEOF

# 6. Launch Jamovi (Empty)
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="