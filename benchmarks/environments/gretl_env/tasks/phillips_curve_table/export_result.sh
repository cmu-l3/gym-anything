#!/bin/bash
echo "=== Exporting Phillips Curve Table Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Generate Ground Truth using gretlcli
# We run a script to calculate the exact coefficients we expect
# so the verifier doesn't need hardcoded values.
echo "Generating ground truth data..."
cat > /tmp/gen_truth.inp << 'EOF'
open /home/ga/Documents/gretl_data/usa.gdt
series gdp_growth = 100 * diff(log(gdp))

# Estimate Model 3 (Dynamic Phillips) to get reference coefficients
ols inf const inf(-1) gdp_growth gdp_growth(-1) --quiet

# Extract coefficients
scalar b_const = $coeff(const)
scalar b_inf_lag = $coeff(inf_1)
scalar b_growth = $coeff(gdp_growth)
scalar b_growth_lag = $coeff(gdp_growth_1)

# Write to JSON
outfile /tmp/ground_truth.json
print "{"
printf "  \"model3_const\": %.4f,\n", b_const
printf "  \"model3_inf_lag\": %.4f,\n", b_inf_lag
printf "  \"model3_gdp_growth\": %.4f,\n", b_growth
printf "  \"model3_gdp_growth_lag\": %.4f\n", b_growth_lag
print "}"
outfile --close
EOF

# Run the ground truth generation
gretlcli -b /tmp/gen_truth.inp > /dev/null 2>&1 || echo "Warning: Failed to generate ground truth"

# 3. Gather Agent Output info
OUTPUT_PATH="/home/ga/Documents/gretl_output/phillips_table.tex"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check if Gretl is still running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# We embed the ground truth content directly into the result json for easier parsing in verifier
GROUND_TRUTH_CONTENT=$(cat /tmp/ground_truth.json 2>/dev/null || echo "{}")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "ground_truth": $GROUND_TRUTH_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="