#!/bin/bash
set -euo pipefail

echo "=== Setting up survival_weibull_analysis task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup Data
# kennan.gdt is a standard dataset. Try to find it in system paths if not in Documents
KENNAN_SRC=""
if [ -f "/usr/share/gretl/data/misc/kennan.gdt" ]; then
    KENNAN_SRC="/usr/share/gretl/data/misc/kennan.gdt"
elif [ -f "/usr/share/gretl/data/kennan.gdt" ]; then
    KENNAN_SRC="/usr/share/gretl/data/kennan.gdt"
fi

mkdir -p /home/ga/Documents/gretl_data
if [ -n "$KENNAN_SRC" ]; then
    cp "$KENNAN_SRC" /home/ga/Documents/gretl_data/kennan.gdt
    echo "Copied kennan.gdt from system."
else
    # Fallback: Create it if missing (unlikely in standard install, but safe)
    # Using a small subset of real values if we had to, but better to fail if env is broken
    echo "WARNING: kennan.gdt not found in system paths. Attempting download..."
    wget -q -O /home/ga/Documents/gretl_data/kennan.gdt "https://sourceforge.net/projects/gretl/files/datafiles/misc/kennan.gdt/download" || true
fi

chown -R ga:ga /home/ga/Documents/gretl_data

# 2. Generate Ground Truth (Hidden)
# We use gretlcli to run the analysis and save the true values
echo "Generating ground truth..."
cat > /tmp/gen_truth.inp << 'EOF'
open /home/ga/Documents/gretl_data/kennan.gdt
duration duration const prod --weibull
scalar b_prod = $coeff(prod)
scalar s = $sigma
string shape = "Constant"
if s < 1
    shape = "Increasing"
elif s > 1
    shape = "Decreasing"
endif

outfile "/tmp/ground_truth.json"
    printf "{\"prod_coeff\": %.6f, \"sigma\": %.6f, \"hazard_shape\": \"%s\"}", b_prod, s, shape
end outfile
EOF

# Run gretlcli as ga user
su - ga -c "gretlcli -b /tmp/gen_truth.inp" >/dev/null 2>&1 || echo "Warning: Ground truth generation failed"

# 3. Clean Output Directory
rm -rf /home/ga/Documents/gretl_output
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# 4. Launch Gretl
# We launch with the dataset loaded to help the user start
setup_gretl_task "kennan.gdt" "weibull_task"

echo "=== Task setup complete ==="