#!/bin/bash
echo "=== Setting up VAR Impulse Response task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl Setup
# Clean up previous runs, ensure output dir exists
setup_gretl_task "usa.gdt" "var_task"

# 2. Generate Ground Truth (Hidden from agent)
# We use gretlcli to calculate the exact expected IRF values
echo "Generating ground truth data..."
mkdir -p /var/lib/gretl/ground_truth
chmod 755 /var/lib/gretl/ground_truth

cat > /tmp/gen_ground_truth.inp << 'EOF'
open /home/ga/Documents/gretl_data/usa.gdt
# Transform data
l_gdp = log(gdp)
# Define list with specific ordering
list VAR_VARS = l_gdp inf F
# Estimate VAR(2)
var 2 VAR_VARS --quiet
# Generate IRF: 12 periods, shock to var 3 (F), response of var 1 (l_gdp)
# Note: Gretl CLI indices depend on list order. 1=l_gdp, 2=inf, 3=F
outfile "/var/lib/gretl/ground_truth/gt_irf.csv" --write
    irf 12 3 1
end outfile
EOF

# Execute ground truth generation
# We run as root so agent can't easily modify the destination, 
# but reading usa.gdt requires access rights
gretlcli -b /tmp/gen_ground_truth.inp > /tmp/gt_gen.log 2>&1

if [ -f "/var/lib/gretl/ground_truth/gt_irf.csv" ]; then
    echo "Ground truth generated successfully."
    chmod 644 /var/lib/gretl/ground_truth/gt_irf.csv
else
    echo "WARNING: Ground truth generation failed."
    cat /tmp/gt_gen.log
fi

# 3. User Instructions
echo ""
echo "============================================================"
echo "TASK: VAR Impulse Response Analysis"
echo "============================================================"
echo "1. Open 'usa.gdt'."
echo "2. Create variable 'l_gdp = log(gdp)'."
echo "3. Estimate VAR(2) with variables: l_gdp, inf, F (in that order)."
echo "4. Generate IRF: Response of l_gdp to shock in F (12 periods)."
echo "5. Save plot to: ~/Documents/gretl_output/irf_plot.png"
echo "6. Save data to: ~/Documents/gretl_output/irf_data.csv"
echo "============================================================"

# Take initial screenshot
take_screenshot /tmp/task_initial.png