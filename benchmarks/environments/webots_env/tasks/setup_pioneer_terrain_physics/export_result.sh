#!/bin/bash
# Export script for setup_pioneer_terrain_physics task
# Checks if the agent saved the physics-configured world and extracts key values.

echo "=== Exporting setup_pioneer_terrain_physics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/pioneer_terrain.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
ROBOT_MASS="not_found"
HAS_CONTACT_PROPERTIES="false"
COULOMB_FRICTION="not_found"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Extract robot body mass (look for mass in PIONEER_ROBOT section)
    # We look for the first mass value associated with the robot body (not wheel density)
    ROBOT_MASS=$(python3 -c "
import re
with open('$OUTPUT_FILE') as f:
    content = f.read()

# Find PIONEER_ROBOT section and extract its body mass
pioneer_idx = content.find('PIONEER_ROBOT')
if pioneer_idx == -1:
    # Fall back to first mass value
    m = re.search(r'mass ([\d.]+)', content)
    print(m.group(1) if m else 'not_found')
else:
    # Find Physics block after PIONEER_ROBOT
    segment = content[pioneer_idx:pioneer_idx+2000]
    m = re.search(r'physics Physics \{[^}]*?mass ([\d.]+)', segment, re.DOTALL)
    if not m:
        m = re.search(r'mass ([\d.]+)', segment)
    print(m.group(1) if m else 'not_found')
" 2>/dev/null || echo "not_found")

    # Check for ContactProperties
    if grep -q "ContactProperties" "$OUTPUT_FILE"; then
        HAS_CONTACT_PROPERTIES="true"
        # Extract coulombFriction value
        COULOMB_FRICTION=$(grep -oP 'coulombFriction \K[\d.]+' "$OUTPUT_FILE" | head -1)
        [ -z "$COULOMB_FRICTION" ] && COULOMB_FRICTION="not_found"
    fi

    echo "  Robot mass: $ROBOT_MASS"
    echo "  Has ContactProperties: $HAS_CONTACT_PROPERTIES"
    echo "  Coulomb friction: $COULOMB_FRICTION"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/setup_pioneer_terrain_physics_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "robot_mass": "${ROBOT_MASS:-not_found}",
    "has_contact_properties": $HAS_CONTACT_PROPERTIES,
    "coulomb_friction": "${COULOMB_FRICTION:-not_found}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/setup_pioneer_terrain_physics_result.json"
cat /tmp/setup_pioneer_terrain_physics_result.json

echo "=== Export Complete ==="
