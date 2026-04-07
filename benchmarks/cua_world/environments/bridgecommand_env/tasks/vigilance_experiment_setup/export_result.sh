#!/bin/bash
echo "=== Exporting Vigilance Experiment Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/Exp) Vigilance Study 4H"
BRIEFING_FILE="/home/ga/Documents/experiment_briefing.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence
SCENARIO_EXISTS="false"
ENV_INI_EXISTS="false"
OWNSHIP_INI_EXISTS="false"
OTHERSHIP_INI_EXISTS="false"
BRIEFING_EXISTS="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_INI_EXISTS="true"
fi

if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
fi

# Extract values for verification
# We use python to robustly parse the INI files (which might be malformed)
python3 -c "
import configparser
import json
import os
import re

def parse_bc_ini(filepath):
    # Bridge Command INI files are not always standard python configparser compatible
    # They often lack sections or use unique key=value formatting
    # We'll use a simple manual parser
    data = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith(';'):
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip().strip('\"') # Remove quotes if present
                    data[key] = val
    except Exception as e:
        pass
    return data

result = {
    'files': {
        'scenario_dir': '$SCENARIO_EXISTS',
        'environment_ini': '$ENV_INI_EXISTS',
        'ownship_ini': '$OWNSHIP_INI_EXISTS',
        'othership_ini': '$OTHERSHIP_INI_EXISTS',
        'briefing': '$BRIEFING_EXISTS'
    },
    'environment': parse_bc_ini('$SCENARIO_DIR/environment.ini'),
    'ownship': parse_bc_ini('$SCENARIO_DIR/ownship.ini'),
    'othership': parse_bc_ini('$SCENARIO_DIR/othership.ini')
}

# Add timestamp
result['timestamp'] = '$(date -Iseconds)'

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json