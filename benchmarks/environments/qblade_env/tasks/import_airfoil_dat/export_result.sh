#!/bin/bash
echo "=== Exporting import_airfoil_dat result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if airfoil was imported (look in QBlade log for import activity)
AIRFOIL_IMPORTED="false"
if [ -f /tmp/qblade_task.log ]; then
    if grep -qi "naca.2412\|2412\|import" /tmp/qblade_task.log 2>/dev/null; then
        AIRFOIL_IMPORTED="true"
    fi
fi
# Also check if QBlade is running (suggests user interacted with it)
QBLADE_RUNNING=$(is_qblade_running)
if [ "$QBLADE_RUNNING" -gt 0 ]; then
    AIRFOIL_IMPORTED="true"
fi

# Check polar output file
POLAR_FILE="/home/ga/Documents/airfoils/naca2412_polar.txt"
POLAR_EXISTS="false"
POLAR_LINES=0
HAS_POLAR_DATA="false"
HAS_NEGATIVE_AOA="false"

if [ -f "$POLAR_FILE" ]; then
    POLAR_EXISTS="true"
    POLAR_LINES=$(wc -l < "$POLAR_FILE")

    # Check for aerodynamic polar data: lines with 3+ numeric columns
    # (typical: alpha, CL, CD, CDp, CM, etc.)
    DATA_LINES=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*[[:space:]]+-?[0-9]+\.[0-9]+[[:space:]]+-?[0-9]+\.[0-9]+' "$POLAR_FILE" 2>/dev/null || echo "0")
    if [ "$DATA_LINES" -gt 3 ]; then
        HAS_POLAR_DATA="true"
        POLAR_LINES=$DATA_LINES
    fi

    # Check for negative angle of attack values (task requires -5 to 15)
    if grep -qE '^[[:space:]]*-[0-9]' "$POLAR_FILE" 2>/dev/null; then
        HAS_NEGATIVE_AOA="true"
    fi
fi

RESULT_JSON=$(cat << EOF
{
    "airfoil_imported": $AIRFOIL_IMPORTED,
    "polar_file_exists": $POLAR_EXISTS,
    "polar_file_path": "$POLAR_FILE",
    "polar_lines": $POLAR_LINES,
    "has_polar_data": $HAS_POLAR_DATA,
    "has_negative_aoa": $HAS_NEGATIVE_AOA,
    "qblade_running": $([ "$QBLADE_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$RESULT_JSON"

echo "=== Export complete ==="
