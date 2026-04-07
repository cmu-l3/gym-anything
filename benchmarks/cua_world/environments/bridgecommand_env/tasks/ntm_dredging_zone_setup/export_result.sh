#!/bin/bash
echo "=== Exporting NTM Dredging Zone Setup Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/NTM 42 Implementation"
ENV_INI="$SCENARIO_DIR/environment.ini"
OWNSHIP_INI="$SCENARIO_DIR/ownship.ini"
OTHERSHIP_INI="$SCENARIO_DIR/othership.ini"

# Capture final screenshot of the desktop/files
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if files exist
SCENARIO_EXISTS="false"
if [ -d "$SCENARIO_DIR" ] && [ -f "$OTHERSHIP_INI" ]; then
    SCENARIO_EXISTS="true"
fi

# Extract data using Python to handle INI parsing robustly
# We parse the 'othership.ini' to get a structured list of objects
python3 -c "
import json
import os
import configparser

result = {
    'scenario_exists': False,
    'objects': [],
    'environment_setting': None,
    'file_timestamps': {}
}

othership_path = '$OTHERSHIP_INI'
env_path = '$ENV_INI'

if os.path.exists(othership_path):
    result['scenario_exists'] = True
    try:
        # Bridge Command INI files are sometimes flat key=value lists without sections
        # or use indexed keys like Type(0)=...
        # We'll parse manually since standard ConfigParser expects sections
        
        with open(othership_path, 'r') as f:
            lines = f.readlines()
            
        objects = {}
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith('//') or line.startswith('#'):
                continue
                
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip().strip('\"')
                
                # Parse indexed keys like InitialLat(1)
                if '(' in key and ')' in key:
                    param_name = key.split('(')[0]
                    index = key.split('(')[1].split(')')[0]
                    
                    if index not in objects:
                        objects[index] = {}
                    
                    objects[index][param_name] = value

        # Convert to list
        for idx, data in objects.items():
            result['objects'].append(data)
            
    except Exception as e:
        result['error'] = str(e)

if os.path.exists(env_path):
    try:
        with open(env_path, 'r') as f:
            content = f.read()
            # extract setting
            for line in content.splitlines():
                if line.lower().startswith('setting='):
                    result['environment_setting'] = line.split('=', 1)[1].strip()
    except:
        pass

# Check timestamps
for f in ['$OTHERSHIP_INI', '$ENV_INI', '$OWNSHIP_INI']:
    if os.path.exists(f):
        result['file_timestamps'][os.path.basename(f)] = os.path.getmtime(f)

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Copy to location accessible by verification host (via copy_from_env)
# The standard output is /tmp/task_result.json

echo "Export complete. Result preview:"
head -n 20 /tmp/task_result.json