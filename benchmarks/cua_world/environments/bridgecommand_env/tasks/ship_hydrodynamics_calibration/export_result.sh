#!/bin/bash
echo "=== Exporting Ship Hydrodynamics Calibration Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INI_FILE="/opt/bridgecommand/Models/Ship/MV_Gladiator/dynamics.ini"
CERT_FILE="/home/ga/Documents/calibration_certificate.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if certificate exists and was created during task
CERT_EXISTS="false"
if [ -f "$CERT_FILE" ]; then
    CERT_MTIME=$(stat -c %Y "$CERT_FILE" 2>/dev/null || echo "0")
    if [ "$CERT_MTIME" -gt "$TASK_START" ]; then
        CERT_EXISTS="true"
    fi
fi

# Check if INI file was modified
INI_MODIFIED="false"
if [ -f "$INI_FILE" ]; then
    INI_MTIME=$(stat -c %Y "$INI_FILE" 2>/dev/null || echo "0")
    if [ "$INI_MTIME" -gt "$TASK_START" ]; then
        INI_MODIFIED="true"
    fi
fi

# Parse the INI file using Python to extract values safely
# We embed a small python script to output JSON structure
python3 -c "
import configparser
import json
import sys

path = '$INI_FILE'
result = {
    'ini_exists': False,
    'values': {},
    'error': None
}

try:
    config = configparser.ConfigParser()
    # BC INI files sometimes lack headers or have loose syntax, but typically follow standard INI
    read_files = config.read(path)
    
    if read_files:
        result['ini_exists'] = True
        
        # Extract specific keys from likely sections
        vals = {}
        
        # Try [General]
        if 'General' in config:
            vals['Length'] = config['General'].get('Length', '0')
            vals['Beam'] = config['General'].get('Beam', '0')
            vals['Description'] = config['General'].get('Description', '')
            
        # Try [Dynamics]
        if 'Dynamics' in config:
            vals['RudderArea'] = config['Dynamics'].get('RudderArea', '0')
            vals['DragArea'] = config['Dynamics'].get('DragArea', '0')
            
        result['values'] = vals
    else:
        result['error'] = 'File could not be parsed as INI'

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
" > /tmp/ini_parse_result.json

# Combine into final result
cat > /tmp/final_combined_result.json << EOF
{
    "task_start": $TASK_START,
    "certificate_exists": $CERT_EXISTS,
    "ini_modified": $INI_MODIFIED,
    "ini_data": $(cat /tmp/ini_parse_result.json)
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/final_combined_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="