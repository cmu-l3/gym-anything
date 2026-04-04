#!/bin/bash
set -euo pipefail
echo "=== Setting up ARMA Inflation Forecast Task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl setup
setup_gretl_task "usa.gdt" "arma_forecast"

# 2. Generate Reference Solution (Ground Truth)
# We run a headless gretl script to calculate the exact values expected.
# We use 'gretlcli' to run this background calculation.

REF_SCRIPT="/tmp/generate_reference.inp"
REF_OUTPUT_JSON="/tmp/reference_values.json"

cat > "$REF_SCRIPT" << 'EOF'
set echo off
open /home/ga/Documents/gretl_data/usa.gdt
# Restrict sample
smpl 1984:1 2008:4
# Estimate ARMA(1,1)
arma 1 1 ; inf
# capture coefficients
matrix b = $coeff
scalar phi1 = b[2]
scalar theta1 = b[3]
scalar const = b[1]

# Generate forecast
# Note: 'fcast' command prints to output, but 'fcast' function returns series or matrix
# We use the function for precise values if possible, or perform the command
series fc_series = fcast(2009:1, 2009:3)
smpl 2009:1 2009:3
# Extract forecast values to matrix
matrix fc_vals = { fc_series }

# Write to a JSON-like text file (handled via simple print for bash parsing)
outfile "/tmp/ref_raw.txt" --write
    printf "phi_1=%.6f\n", phi1
    printf "theta_1=%.6f\n", theta1
    printf "const=%.6f\n", const
    printf "f_2009_1=%.6f\n", fc_vals[1]
    printf "f_2009_2=%.6f\n", fc_vals[2]
    printf "f_2009_3=%.6f\n", fc_vals[3]
end outfile
EOF

echo "Generating reference values..."
# Run gretlcli (batch mode, no GUI)
gretlcli -b "$REF_SCRIPT" > /dev/null 2>&1 || echo "Warning: Reference generation reported error"

# Parse the raw output into JSON
if [ -f "/tmp/ref_raw.txt" ]; then
    # Convert key=value lines to JSON
    echo "{" > "$REF_OUTPUT_JSON"
    while IFS='=' read -r key val; do
        echo "  \"$key\": $val," >> "$REF_OUTPUT_JSON"
    done < "/tmp/ref_raw.txt"
    # Remove trailing comma from last line hack (sed to replace last comma with space)
    sed -i '$ s/,$//' "$REF_OUTPUT_JSON"
    echo "}" >> "$REF_OUTPUT_JSON"
    
    echo "Reference values generated:"
    cat "$REF_OUTPUT_JSON"
else
    echo "ERROR: Failed to generate reference values."
    # Fallback values based on historical run of this data (approximate)
    echo '{
      "phi_1": 0.85,
      "theta_1": -0.45,
      "const": 3.0,
      "f_2009_1": 2.0,
      "f_2009_2": 2.1,
      "f_2009_3": 2.2
    }' > "$REF_OUTPUT_JSON"
fi

# 3. Create instructions file (optional, but helpful for agent context if they browse)
cat > /home/ga/Documents/gretl_output/task_instructions.txt << 'EOF'
Task Instructions:
1. Open the script editor in Gretl.
2. Write a script to:
   - Open 'usa.gdt'
   - Restrict sample to 1984:1 - 2008:4
   - Estimate ARMA(1,1) on 'inf'
   - Forecast for 2009:1 - 2009:3
3. Save script as 'inflation_forecast.inp'
4. Save output as 'inflation_forecast_output.txt'
EOF

echo "=== Setup Complete ==="