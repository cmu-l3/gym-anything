#!/bin/bash
# Export script for deploy_swarm_experiment task
# Checks if the agent saved the swarm world and extracts robot controllers, positions, timestep.

echo "=== Exporting deploy_swarm_experiment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

OUTPUT_FILE="/home/ga/Desktop/swarm_ready.wbt"

FILE_EXISTS="false"
FILE_SIZE=0
BASIC_TIMESTEP="not_found"
NUM_VALID_CONTROLLERS=0
NUM_DISTINCT_POSITIONS=0
CONTROLLERS_LIST="[]"
POSITIONS_LIST="[]"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(get_file_size "$OUTPUT_FILE")
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

    # Extract basicTimeStep
    BASIC_TIMESTEP=$(grep -oP 'basicTimeStep \K\d+' "$OUTPUT_FILE" | head -1)

    # Extract robot controllers and positions using Python
    python3 -c "
import re, json, math

with open('$OUTPUT_FILE') as f:
    content = f.read()

# Extract all controller values
controllers = re.findall(r'controller\s+\"([^\"]+)\"', content)

# Count valid controllers (not soccer_player_broken, not <none>, not void)
broken = {'soccer_player_broken', '<none>', 'void', ''}
valid_count = sum(1 for c in controllers if c not in broken)

# Extract all robot translations
# Look for 'translation X Y Z' patterns after robot DEF lines
translations = []
lines = content.split('\n')
for i, line in enumerate(lines):
    if re.search(r'(DEF BLUE_PLAYER|DEF YELLOW_PLAYER)', line):
        # Look ahead for translation
        for j in range(i+1, min(i+10, len(lines))):
            m = re.match(r'\s+translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', lines[j])
            if m:
                translations.append((float(m.group(1)), float(m.group(2)), float(m.group(3))))
                break

# Count distinct non-overlapping positions (distance > 0.15m between any pair)
distinct = 0
for i in range(len(translations)):
    for j in range(i+1, len(translations)):
        dx = translations[i][0] - translations[j][0]
        dy = translations[i][1] - translations[j][1]
        dz = translations[i][2] - translations[j][2]
        dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist > 0.15:
            distinct += 1

print(f'NUM_VALID={valid_count}')
print(f'NUM_DISTINCT={distinct}')
print(f'CONTROLLERS={json.dumps(controllers[:8])}')
print(f'POSITIONS={json.dumps([(round(t[0],3),round(t[1],3),round(t[2],3)) for t in translations[:8]])}')
" > /tmp/swarm_analysis.txt 2>/dev/null

    NUM_VALID_CONTROLLERS=$(grep "NUM_VALID=" /tmp/swarm_analysis.txt | cut -d'=' -f2)
    NUM_DISTINCT_POSITIONS=$(grep "NUM_DISTINCT=" /tmp/swarm_analysis.txt | cut -d'=' -f2)
    CONTROLLERS_LIST=$(grep "CONTROLLERS=" /tmp/swarm_analysis.txt | sed 's/CONTROLLERS=//')
    POSITIONS_LIST=$(grep "POSITIONS=" /tmp/swarm_analysis.txt | sed 's/POSITIONS=//')

    echo "  basicTimeStep: $BASIC_TIMESTEP"
    echo "  Valid controllers count: $NUM_VALID_CONTROLLERS"
    echo "  Distinct non-overlapping position pairs: $NUM_DISTINCT_POSITIONS"
    echo "  Controllers: $CONTROLLERS_LIST"
    echo "  Positions: $POSITIONS_LIST"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Write result JSON
cat > /tmp/deploy_swarm_experiment_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE",
    "basic_timestep": "${BASIC_TIMESTEP:-not_found}",
    "num_valid_controllers": ${NUM_VALID_CONTROLLERS:-0},
    "num_distinct_positions": ${NUM_DISTINCT_POSITIONS:-0},
    "controllers": ${CONTROLLERS_LIST:-[]},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/deploy_swarm_experiment_result.json"
cat /tmp/deploy_swarm_experiment_result.json

echo "=== Export Complete ==="
