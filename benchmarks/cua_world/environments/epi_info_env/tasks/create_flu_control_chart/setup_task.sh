#!/bin/bash
set -e
echo "=== Setting up task: create_flu_control_chart@1 ==="

# Define paths (using Git Bash / Cygwin style paths for Windows environment)
DOCS_DIR="/c/Users/Docker/Documents"
DATA_FILE="$DOCS_DIR/flu_data_2019_2020.csv"
GROUND_TRUTH="$DOCS_DIR/ground_truth_metrics.json"

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"

# 1. Create the data file (Real CDC ILINet Data patterns for 2019-20)
echo "Creating data file at $DATA_FILE..."
cat <<EOF > "$DATA_FILE"
Year,Week,Total_ILI
2019,40,25000
2019,41,26500
2019,42,28000
2019,43,29500
2019,44,31000
2019,45,33000
2019,46,36000
2019,47,38000
2019,48,45000
2019,49,42000
2019,50,44000
2019,51,55000
2019,52,68000
2020,1,75000
2020,2,82000
2020,3,88000
2020,4,95000
2020,5,105000
2020,6,110000
2020,7,108000
2020,8,95000
2020,9,85000
2020,10,70000
2020,11,60000
2020,12,50000
2020,13,40000
2020,14,30000
2020,15,25000
EOF

# 2. Calculate Ground Truth for Verification
# We use a small python script to calculate exact Mean/SD to ensure verifier matches data
echo "Calculating ground truth..."
python3 -c '
import statistics
import json

# Baseline data: Weeks 40-50 of 2019
baseline_data = [
    25000, 26500, 28000, 29500, 31000, 33000, 36000, 38000, 45000, 42000, 44000
]

# Calculate statistics
mean_val = statistics.mean(baseline_data)
sd_val = statistics.stdev(baseline_data)
threshold = mean_val + (2 * sd_val)

# Full dataset for identifying alerts
full_data_2019 = {51: 55000, 52: 68000}
full_data_2020 = {1: 75000, 2: 82000, 3: 88000, 4: 95000, 5: 105000, 6: 110000, 
                  7: 108000, 8: 95000, 9: 85000, 10: 70000, 11: 60000, 12: 50000, 
                  13: 40000, 14: 30000, 15: 25000}

alerts = []

# Check 2019 remaining weeks
for wk, val in full_data_2019.items():
    if val > threshold:
        alerts.append(wk)

# Check 2020 weeks
for wk, val in full_data_2020.items():
    if val > threshold:
        alerts.append(wk)

result = {
    "mean": mean_val,
    "sd": sd_val,
    "threshold": threshold,
    "alert_weeks": sorted(alerts)
}

with open("ground_truth_metrics.json", "w") as f:
    json.dump(result, f)

print(f"Ground Truth - Threshold: {threshold:.2f}, Alerts: {alerts}")
'
mv ground_truth_metrics.json "$GROUND_TRUTH"

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Start Epi Info 7 if not running
if ! pgrep -f "EpiInfo" > /dev/null; then
    echo "Starting Epi Info 7..."
    # Adjust path if needed for specific environment installation
    "/c/Program Files (x86)/Epi Info 7/EpiInfo.exe" &
    sleep 10
fi

# 5. Ensure window is maximized and focused
# Using wmctrl if available in the environment (common in these research envs)
if command -v wmctrl &> /dev/null; then
    DISPLAY=:1 wmctrl -r "Epi Info 7" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Epi Info 7" 2>/dev/null || true
fi

# 6. Capture initial screenshot
echo "Capturing initial state..."
sleep 2
scrot /tmp/task_initial.png 2>/dev/null || import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="