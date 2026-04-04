#!/bin/bash
# Export script for debug_multifault_simulation task
# Checks if the agent saved the fixed world and extracts values to verify corrections.

echo "=== Exporting debug_multifault_simulation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/fixed_simulation.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
BASIC_TIMESTEP="not_found"
GRAVITY_VALUE="not_found"
FIRST_ROBOT_MASS="not_found"
ALL_MASSES_POSITIVE="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Extract basicTimeStep
    BASIC_TIMESTEP=$(grep -oP 'basicTimeStep \K\d+' "$OUTPUT_FILE" | head -1)

    # Extract gravity
    GRAVITY_VALUE=$(grep -oP 'gravity \K[\d.]+' "$OUTPUT_FILE" | head -1)

    # Extract first robot mass and check all masses
    python3 << 'PYEOF'
import re

with open('/home/ga/Desktop/fixed_simulation.wbt') as f:
    content = f.read()

# Find all mass values in Physics blocks
masses = re.findall(r'mass\s+([\d.]+)', content)
if masses:
    print(f"FIRST_MASS={masses[0]}")
    all_positive = all(float(m) > 0.1 for m in masses)
    print(f"ALL_POSITIVE={'true' if all_positive else 'false'}")
    print(f"ALL_MASSES={','.join(masses)}")
else:
    print("FIRST_MASS=not_found")
    print("ALL_POSITIVE=false")
    print("ALL_MASSES=")
PYEOF
    # Parse Python output
    FIRST_ROBOT_MASS=$(grep "FIRST_MASS=" /tmp/mass_output.txt 2>/dev/null | cut -d'=' -f2 || echo "not_found")
    ALL_MASSES_POSITIVE=$(grep "ALL_POSITIVE=" /tmp/mass_output.txt 2>/dev/null | cut -d'=' -f2 || echo "false")

    # Re-run with output captured
    python3 -c "
import re

with open('$OUTPUT_FILE') as f:
    content = f.read()

masses = re.findall(r'mass\s+([\d.]+)', content)
if masses:
    all_positive = all(float(m) > 0.1 for m in masses)
    print(masses[0])  # first mass
    print('true' if all_positive else 'false')  # all positive
else:
    print('not_found')
    print('false')
" > /tmp/mass_check_output.txt 2>/dev/null

    FIRST_ROBOT_MASS=$(head -1 /tmp/mass_check_output.txt)
    ALL_MASSES_POSITIVE=$(tail -1 /tmp/mass_check_output.txt)

    echo "  basicTimeStep: $BASIC_TIMESTEP"
    echo "  gravity: $GRAVITY_VALUE"
    echo "  First robot mass: $FIRST_ROBOT_MASS"
    echo "  All masses positive: $ALL_MASSES_POSITIVE"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/debug_multifault_simulation_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "basic_timestep": "${BASIC_TIMESTEP:-not_found}",
    "gravity_value": "${GRAVITY_VALUE:-not_found}",
    "first_robot_mass": "${FIRST_ROBOT_MASS:-not_found}",
    "all_masses_positive": ${ALL_MASSES_POSITIVE:-false},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/debug_multifault_simulation_result.json"
cat /tmp/debug_multifault_simulation_result.json

echo "=== Export Complete ==="
