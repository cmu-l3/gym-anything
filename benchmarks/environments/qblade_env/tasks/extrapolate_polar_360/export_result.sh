#!/bin/bash
echo "=== Exporting extrapolate_polar_360 Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

AIRFOIL_DIR="/home/ga/Documents/airfoils"
OUTPUT_FILE="$AIRFOIL_DIR/naca6412_360polar.txt"
RESULT_FILE="/tmp/task_result.json"

# Analyze the output file
FILE_EXISTS="false"
FILE_LINES=0
HAS_DATA="false"
DATA_POINTS=0
HAS_NEGATIVE_AOA="false"
HAS_EXTREME_AOA="false"
MAX_AOA=0
MIN_AOA=0
HAS_6412_REF="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_LINES=$(wc -l < "$OUTPUT_FILE")

    # Count multi-column numeric data rows
    DATA_POINTS=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*[[:space:]]+-?[0-9]+\.[0-9]+' "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$DATA_POINTS" -gt 0 ]; then
        HAS_DATA="true"
    fi

    # Check for negative AoA
    if grep -qE '^[[:space:]]*-[0-9]+\.?[0-9]*[[:space:]]' "$OUTPUT_FILE" 2>/dev/null; then
        HAS_NEGATIVE_AOA="true"
    fi

    # Check for extreme AoA values (beyond +-90 degrees = evidence of 360 extrapolation)
    # Look for AoA values greater than 90 or less than -90
    if grep -qE '^[[:space:]]*-?(9[1-9]|[1-9][0-9]{2}|1[0-7][0-9])\.?[0-9]*[[:space:]]' "$OUTPUT_FILE" 2>/dev/null; then
        HAS_EXTREME_AOA="true"
    fi

    # Extract min and max AoA from first numeric column using Python for robustness
    python3 -c "
import sys
aoas = []
with open('$OUTPUT_FILE') as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) >= 2:
            try:
                aoa = float(parts[0])
                aoas.append(aoa)
            except ValueError:
                continue
if aoas:
    print(f'{min(aoas):.1f} {max(aoas):.1f}')
else:
    print('0.0 0.0')
" > /tmp/aoa_range.txt 2>/dev/null
    MIN_AOA=$(cut -d' ' -f1 /tmp/aoa_range.txt 2>/dev/null || echo "0")
    MAX_AOA=$(cut -d' ' -f2 /tmp/aoa_range.txt 2>/dev/null || echo "0")

    # Check for 6412 reference in file
    if grep -qi "6412\|NACA" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_6412_REF="true"
    fi
fi

# Check QBlade running state
QBLADE_RUNNING="false"
if is_qblade_running; then
    QBLADE_RUNNING="true"
fi

# Check for alternate output locations
ALT_FILES=""
for d in "/home/ga/Desktop" "/home/ga" "/tmp" "/home/ga/Documents"; do
    found=$(ls "$d"/*360*.txt "$d"/*extrap*.txt 2>/dev/null | tr '\n' ',')
    if [ -n "$found" ]; then
        ALT_FILES="${ALT_FILES}${found}"
    fi
done

cat > "$RESULT_FILE" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_lines": $FILE_LINES,
    "has_data": $HAS_DATA,
    "data_points": $DATA_POINTS,
    "has_negative_aoa": $HAS_NEGATIVE_AOA,
    "has_extreme_aoa": $HAS_EXTREME_AOA,
    "min_aoa": $MIN_AOA,
    "max_aoa": $MAX_AOA,
    "has_6412_ref": $HAS_6412_REF,
    "qblade_running": $QBLADE_RUNNING,
    "alternative_files": "$ALT_FILES",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
