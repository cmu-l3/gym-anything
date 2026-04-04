#!/bin/bash
echo "=== Exporting airfoil_polar_comparison Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

AIRFOIL_DIR="/home/ga/Documents/airfoils"
RESULT_FILE="/tmp/task_result.json"

# Check each polar file independently
check_polar_file() {
    local filepath="$1"
    local label="$2"

    local exists="false"
    local lines=0
    local has_data="false"
    local has_negative_aoa="false"
    local data_points=0

    if [ -f "$filepath" ]; then
        exists="true"
        lines=$(wc -l < "$filepath")

        # Check for multi-column numeric data (typical polar format: alpha Cl Cd ...)
        data_points=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*[[:space:]]+-?[0-9]+\.[0-9]+' "$filepath" 2>/dev/null || echo "0")
        if [ "$data_points" -gt 0 ]; then
            has_data="true"
        fi

        # Check for negative angle of attack values (first column negative)
        if grep -qE '^[[:space:]]*-[0-9]+\.?[0-9]*[[:space:]]' "$filepath" 2>/dev/null; then
            has_negative_aoa="true"
        fi
    fi

    echo "{\"exists\": $exists, \"lines\": $lines, \"has_data\": $has_data, \"has_negative_aoa\": $has_negative_aoa, \"data_points\": $data_points}"
}

POLAR_0015=$(check_polar_file "$AIRFOIL_DIR/polar_naca0015.txt" "naca0015")
POLAR_2412=$(check_polar_file "$AIRFOIL_DIR/polar_naca2412.txt" "naca2412")
POLAR_4412=$(check_polar_file "$AIRFOIL_DIR/polar_naca4412.txt" "naca4412")

# Check QBlade running state
QBLADE_RUNNING="false"
if is_qblade_running; then
    QBLADE_RUNNING="true"
fi

# Get baseline
INITIAL_POLAR_COUNT=$(cat /tmp/initial_polar_count 2>/dev/null || echo "0")
CURRENT_POLAR_COUNT=$(ls "$AIRFOIL_DIR"/polar_*.txt 2>/dev/null | wc -l)

# Also check for alternate export locations
ALT_FILES=""
for d in "/home/ga/Desktop" "/home/ga" "/tmp" "/home/ga/Documents"; do
    found=$(ls "$d"/polar_naca*.txt 2>/dev/null | tr '\n' ',')
    if [ -n "$found" ]; then
        ALT_FILES="${ALT_FILES}${found}"
    fi
done

cat > "$RESULT_FILE" << EOF
{
    "polar_naca0015": $POLAR_0015,
    "polar_naca2412": $POLAR_2412,
    "polar_naca4412": $POLAR_4412,
    "initial_polar_count": $INITIAL_POLAR_COUNT,
    "current_polar_count": $CURRENT_POLAR_COUNT,
    "qblade_running": $QBLADE_RUNNING,
    "alternative_files": "$ALT_FILES",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
