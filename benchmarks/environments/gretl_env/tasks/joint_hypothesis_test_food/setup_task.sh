#!/bin/bash
set -e
echo "=== Setting up Joint Hypothesis Test task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl setup with food.gdt
setup_gretl_task "food.gdt" "joint_test"

# 2. Generate Ground Truth (Hidden from agent)
# We use gretlcli to run the exact same test and save the output to a protected location.
# This ensures verification is dynamic and robust to dataset versions.
echo "Generating ground truth..."
mkdir -p /var/lib/gretl
cat > /tmp/gen_truth.inp << 'EOF'
open /opt/gretl_data/poe5/food.gdt
ols food_exp const income --quiet
restrict
    b[const] = 80
    b[income] = 10
end restrict --quiet
EOF

# Run gretlcli non-interactively
gretlcli -b /tmp/gen_truth.inp > /var/lib/gretl/ground_truth_test.txt 2>/dev/null || true

# Secure the ground truth
chmod 600 /var/lib/gretl/ground_truth_test.txt
chown root:root /var/lib/gretl/ground_truth_test.txt

# 3. Clean previous user outputs
rm -f /home/ga/Documents/gretl_output/joint_test_results.txt

echo "=== Task setup complete ==="