#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up ols_forecast_intervals task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Gretl instances
kill_gretl

# Ensure output directory exists and is clean
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown -R ga:ga /home/ga/Documents/gretl_output

# Ensure dataset is available
restore_dataset "food.gdt"

# Compute ground truth dynamically to ensure version compatibility
# We run a headless gretl script to generate the exact numbers
echo "Computing ground truth values..."
cat > /tmp/compute_ground_truth.inp << 'EOF'
open /home/ga/Documents/gretl_data/food.gdt
ols food_exp const income
scalar b0 = $coeff(const)
scalar b1 = $coeff(income)
dataset addobs 3
series income[41] = 15
series income[42] = 20
series income[43] = 25
smpl 1 40
ols food_exp const income
smpl 41 43
fcast --out-of-sample
scalar f15 = $fcast[41]
scalar f20 = $fcast[42]
scalar f25 = $fcast[43]

outfile /tmp/ground_truth_values.json
  printf "{\n"
  printf "  \"b0\": %.6f,\n", b0
  printf "  \"b1\": %.6f,\n", b1
  printf "  \"f15\": %.6f,\n", f15
  printf "  \"f20\": %.6f,\n", f20
  printf "  \"f25\": %.6f\n", f25
  printf "}\n"
end outfile
EOF

# Run gretlcli (headless) as user ga
su - ga -c "gretlcli -b /tmp/compute_ground_truth.inp" > /tmp/gt_run.log 2>&1 || true

if [ -f /tmp/ground_truth_values.json ]; then
    # Move to a protected location that export_result.sh can access later
    mv /tmp/ground_truth_values.json /var/lib/gretl_ground_truth.json
    chmod 644 /var/lib/gretl_ground_truth.json
    echo "Ground truth computed successfully."
else
    echo "WARNING: Ground truth computation failed. Will rely on static metadata."
fi

# Launch Gretl with food.gdt for the user
launch_gretl "/home/ga/Documents/gretl_data/food.gdt" "/home/ga/gretl_forecast_task.log"

# Wait for window
wait_for_gretl 60 || true
sleep 5

# Dismiss any dialogs
for i in {1..3}; do
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus
maximize_gretl
focus_gretl
sleep 2

# Take initial screenshot
mkdir -p /tmp/task_evidence
take_screenshot /tmp/task_evidence/initial_state.png

echo "=== Setup complete ==="