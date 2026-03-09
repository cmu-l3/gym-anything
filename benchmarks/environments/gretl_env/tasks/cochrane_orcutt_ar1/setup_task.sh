#!/bin/bash
echo "=== Setting up Cochrane-Orcutt AR(1) Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
DATASET="usa.gdt"
OUTPUT_DIR="/home/ga/Documents/gretl_output"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Setup Gretl with usa.gdt
# This kills existing instances, restores the dataset, and launches Gretl
setup_gretl_task "$DATASET" "cochrane_orcutt"

# Additional instruction file for the agent (optional context)
cat > /home/ga/Documents/gretl_output/README.txt << EOF
Task Instructions:
1. Create a GDP growth rate variable from 'gdp'.
2. Run OLS: gdp_growth = const + inflation.
3. Check Durbin-Watson statistic.
4. Run AR(1) correction (Cochrane-Orcutt).
5. Save your script to 'cochrane_orcutt.inp'.
6. Save results (DW, rho, coefficients) to 'cochrane_orcutt_results.txt'.
EOF
chown ga:ga /home/ga/Documents/gretl_output/README.txt

echo "=== Setup Complete ==="
echo "Gretl launched with $DATASET"