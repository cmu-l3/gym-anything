#!/bin/bash
echo "=== Exporting multi_reynolds_analysis Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

AIRFOIL_DIR="/home/ga/Documents/airfoils"
RESULT_FILE="/tmp/task_result.json"

# Analyze each polar file
check_polar_file() {
    local filepath="$1"

    local exists="false"
    local lines=0
    local has_data="false"
    local has_negative_aoa="false"
    local data_points=0

    if [ -f "$filepath" ]; then
        exists="true"
        lines=$(wc -l < "$filepath")

        # Count multi-column numeric data rows
        data_points=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*[[:space:]]+-?[0-9]+\.[0-9]+' "$filepath" 2>/dev/null || echo "0")
        if [ "$data_points" -gt 0 ]; then
            has_data="true"
        fi

        # Check for negative AoA
        if grep -qE '^[[:space:]]*-[0-9]+\.?[0-9]*[[:space:]]' "$filepath" 2>/dev/null; then
            has_negative_aoa="true"
        fi
    fi

    echo "{\"exists\": $exists, \"lines\": $lines, \"has_data\": $has_data, \"has_negative_aoa\": $has_negative_aoa, \"data_points\": $data_points}"
}

POLAR_200K=$(check_polar_file "$AIRFOIL_DIR/polar_re200k.txt")
POLAR_500K=$(check_polar_file "$AIRFOIL_DIR/polar_re500k.txt")
POLAR_1M=$(check_polar_file "$AIRFOIL_DIR/polar_re1m.txt")

# Count how many polar files exist
POLARS_FOUND=0
for f in "$AIRFOIL_DIR/polar_re200k.txt" "$AIRFOIL_DIR/polar_re500k.txt" "$AIRFOIL_DIR/polar_re1m.txt"; do
    [ -f "$f" ] && POLARS_FOUND=$((POLARS_FOUND + 1))
done

# Check QBlade running state
QBLADE_RUNNING="false"
if is_qblade_running; then
    QBLADE_RUNNING="true"
fi

# Baseline
INITIAL_POLAR_COUNT=$(cat /tmp/initial_polar_count 2>/dev/null || echo "0")

cat > "$RESULT_FILE" << EOF
{
    "polar_re200k": $POLAR_200K,
    "polar_re500k": $POLAR_500K,
    "polar_re1m": $POLAR_1M,
    "polars_found": $POLARS_FOUND,
    "initial_polar_count": $INITIAL_POLAR_COUNT,
    "qblade_running": $QBLADE_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
