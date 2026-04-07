#!/bin/bash
echo "=== Exporting synchronized_collision_setup results ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Stress Test"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if scenario directory exists
if [ ! -d "$SCENARIO_DIR" ]; then
    echo "Scenario directory not found."
    cat > /tmp/task_result.json << EOF
{
    "scenario_found": false,
    "files_found": [],
    "ownship": {},
    "otherships": []
}
EOF
    exit 0
fi

# Use Python to robustly parse the INI files and export to JSON
# This handles the indexed keys in othership.ini (e.g. Type(0)=...)
python3 -c "
import os
import re
import json
import math

scenario_dir = '$SCENARIO_DIR'
result = {
    'scenario_found': True,
    'files_found': [],
    'ownship': {},
    'otherships': []
}

# Check files
for f in ['environment.ini', 'ownship.ini', 'othership.ini']:
    if os.path.exists(os.path.join(scenario_dir, f)):
        result['files_found'].append(f)

# Parse Ownship
own_path = os.path.join(scenario_dir, 'ownship.ini')
if os.path.exists(own_path):
    try:
        with open(own_path, 'r') as f:
            content = f.read()
        
        # Simple regex for key=value
        def get_val(key, text):
            m = re.search(r'^' + key + r'=(.+)$', text, re.MULTILINE)
            return float(m.group(1).strip()) if m else None
            
        result['ownship'] = {
            'lat': get_val('InitialLat', content),
            'long': get_val('InitialLong', content),
            'speed': get_val('InitialSpeed', content),
            'heading': get_val('InitialBearing', content)
        }
    except Exception as e:
        print(f'Error parsing ownship: {e}')

# Parse Othership (indexed format)
other_path = os.path.join(scenario_dir, 'othership.ini')
if os.path.exists(other_path):
    try:
        with open(other_path, 'r') as f:
            lines = f.readlines()
            
        vessels = {}
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith('//') or line.startswith('#'):
                continue
                
            # Match Key(Index)=Value
            m = re.match(r'([a-zA-Z0-9]+)\(([0-9]+)\)=(.+)', line)
            if m:
                key, idx, val = m.groups()
                idx = int(idx)
                if idx not in vessels:
                    vessels[idx] = {}
                
                # Remove quotes if present
                val = val.strip().strip('\"')
                
                vessels[idx][key] = val
        
        # Convert to list
        for idx in sorted(vessels.keys()):
            v = vessels[idx]
            # Extract standard fields
            try:
                v_data = {
                    'index': idx,
                    'type': v.get('Type', 'Unknown'),
                    'lat': float(v.get('InitLat', 0.0)),
                    'long': float(v.get('InitLong', 0.0)),
                    'speed': 0.0,
                    'heading': 0.0
                }
                
                # Speed/Heading are often in lists like Speed(0)=12.0 or part of leg data
                # But for simple scenarios, they might be single values if defined that way.
                # Bridge Command usually defines legs: Legs(0)=1, Bearing(0,1)=180, Speed(0,1)=12
                # We need to look for the FIRST leg speed/bearing
                
                # Look for Bearing(idx, 1) and Speed(idx, 1) in the raw lines if not parsed above
                # Actually, the regex above captures 'Bearing' with key 'Bearing' and value... wait.
                # The regex captures 'Bearing' as key. But Bearing(0,1) fails the regex `([a-zA-Z0-9]+)\(([0-9]+)\)=`
                # It needs to handle comma: `([a-zA-Z0-9]+)\(([0-9]+)(?:,\s*[0-9]+)?\)=`
                pass
            except:
                pass

        # Re-parse specifically for complex keys
        vessels_detailed = {}
        for line in lines:
            line = line.strip()
            # Match Key(VesselIdx, LegIdx)=Value OR Key(VesselIdx)=Value
            m = re.match(r'([a-zA-Z0-9]+)\(([0-9]+)(?:,\s*([0-9]+))?\)=(.+)', line)
            if m:
                key, v_idx, l_idx, val = m.groups()
                v_idx = int(v_idx)
                val = val.strip().strip('\"')
                
                if v_idx not in vessels_detailed:
                    vessels_detailed[v_idx] = {'legs': {}}
                
                if l_idx:
                    # It's a leg property
                    l_idx = int(l_idx)
                    if l_idx not in vessels_detailed[v_idx]['legs']:
                         vessels_detailed[v_idx]['legs'][l_idx] = {}
                    vessels_detailed[v_idx]['legs'][l_idx][key] = val
                else:
                    # It's a vessel property
                    vessels_detailed[v_idx][key] = val

        # Flatten for export
        export_list = []
        for idx in sorted(vessels_detailed.keys()):
            v = vessels_detailed[idx]
            
            # Get first leg (1) for initial motion
            leg1 = v['legs'].get(1, {})
            
            try:
                item = {
                    'index': idx,
                    'type': v.get('Type', ''),
                    'lat': float(v.get('InitLat', 0)),
                    'long': float(v.get('InitLong', 0)),
                    'speed': float(leg1.get('Speed', 0)),
                    'heading': float(leg1.get('Bearing', 0))
                }
                export_list.append(item)
            except Exception as e:
                # If partial data, append what we have
                export_list.append({'index': idx, 'error': str(e)})
                
        result['otherships'] = export_list

    except Exception as e:
        print(f'Error parsing othership: {e}')
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json