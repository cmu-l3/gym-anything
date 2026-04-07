#!/bin/bash
echo "=== Exporting TSS Buoy Deployment Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Experimental TSS"
OTHERSHIP_FILE="$SCENARIO_DIR/othership.ini"
ENV_FILE="$SCENARIO_DIR/environment.ini"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if scenario directory was created
SCENARIO_EXISTS="false"
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
fi

# Parse othership.ini for buoy data
# We use python to parse the INI structure reliably
BUOY_DATA="[]"
if [ -f "$OTHERSHIP_FILE" ]; then
    BUOY_DATA=$(python3 -c "
import sys, re, json

file_path = '$OTHERSHIP_FILE'
buoys = []

try:
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Simple parser for the indexed INI format used by Bridge Command
    # Format: Key(Index)=Value
    
    # We need to group by index
    items = {}
    
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('//') or line.startswith('#'):
            continue
            
        match = re.match(r'([A-Za-z]+)\(([0-9]+)\)=(.*)', line)
        if match:
            key, idx, val = match.groups()
            idx = int(idx)
            if idx not in items:
                items[idx] = {}
            items[idx][key] = val.strip().strip('\"')

    # Convert dictionary to list
    for idx in sorted(items.keys()):
        item = items[idx]
        # Extract specific fields
        buoy = {
            'index': idx,
            'lat': float(item.get('InitLat', -999)),
            'long': float(item.get('InitLong', -999)),
            'type': item.get('Type', 'unknown'),
            'speed': item.get('Speed', '0').split(',')[0] # Handle Speed(1)=0 or Speed(1)=0,0
        }
        
        # Parse speed as float
        try:
             buoy['speed'] = float(buoy['speed'])
        except:
             buoy['speed'] = -1.0
             
        buoys.append(buoy)

    print(json.dumps(buoys))
except Exception as e:
    print(json.dumps([])) # Return empty on error
")
fi

# Check if environment.ini exists
ENV_EXISTS="false"
if [ -f "$ENV_FILE" ]; then
    ENV_EXISTS="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scenario_exists": $SCENARIO_EXISTS,
    "environment_exists": $ENV_EXISTS,
    "buoy_data": $BUOY_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="