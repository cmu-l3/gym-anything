#!/bin/bash
echo "=== Exporting ground_station_hw_config result ==="

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_state.png 2>/dev/null || true

# Run a python script to safely gather all configuration state into a JSON file
cat << 'EOF' > /tmp/export_gpredict_config.py
import os
import json
import time

conf_dir = "/home/ga/.config/Gpredict"

result = {
    "export_timestamp": time.time(),
    "georgiatech_qth": None,
    "autotrack_mod": None,
    "hw_configs": {},
    "gpredict_cfg": None
}

# Walk through the GPredict config directory
for root, dirs, files in os.walk(conf_dir):
    # Skip large binary/TLE data caches
    if "satdata" in root:
        continue
        
    for f in files:
        if f.endswith('.png') or f.endswith('.jpg') or f.endswith('.swp'):
            continue
            
        path = os.path.join(root, f)
        
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as fh:
                content = fh.read()
                
                # Check for the specific files we asked the agent to create
                if f.lower() == "georgiatech.qth":
                    result["georgiatech_qth"] = content
                elif f.lower() == "autotrack.mod":
                    result["autotrack_mod"] = content
                elif f.lower() == "gpredict.cfg":
                    result["gpredict_cfg"] = content
                
                # Capture any files in radios/rotators directories or files that mention our interface names
                if "radios" in root or "rotators" in root or "hwconf" in root or \
                   "G5500_AzEl" in content or "IC9700" in content:
                    result["hw_configs"][path] = content
                    
        except Exception as e:
            pass

# Write out the aggregated configuration state
with open("/tmp/ground_station_hw_config_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Configuration state aggregated successfully.")
EOF

python3 /tmp/export_gpredict_config.py

# Ensure correct permissions
chmod 666 /tmp/ground_station_hw_config_result.json 2>/dev/null || true

echo "Result saved to /tmp/ground_station_hw_config_result.json"
echo "=== Export Complete ==="