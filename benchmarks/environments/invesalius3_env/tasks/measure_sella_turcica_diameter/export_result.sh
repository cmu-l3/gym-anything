#!/bin/bash
echo "=== Exporting measure_sella_turcica_diameter result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/sella_measurement.inv3"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Extract measurement data using Python
# The .inv3 file is a tar.gz archive containing measurements.plist
python3 << PYEOF
import tarfile
import plistlib
import os
import json
import time

output_path = "$OUTPUT_FILE"
task_start = int("$TASK_START")
result = {
    "file_exists": False,
    "file_created_during_task": False,
    "valid_inv3": False,
    "measurement_count": 0,
    "valid_measurements": [],     # Measurements within 5-25mm range
    "all_measurements": [],       # All measurements found
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    
    # Check modification time
    mtime = int(os.path.getmtime(output_path))
    if mtime > task_start:
        result["file_created_during_task"] = True
        
    try:
        # Open the tar archive
        with tarfile.open(output_path, "r:gz") as tar:
            result["valid_inv3"] = True
            
            # Look for measurements.plist
            try:
                f = tar.extractfile("measurements.plist")
                if f:
                    # Parse plist
                    pl = plistlib.load(f)
                    
                    # InVesalius stores measurements as a dict where values have a "value" key
                    # Format: { "0": {"value": 12.5, ...}, "1": ... }
                    for key, data in pl.items():
                        if isinstance(data, dict) and "value" in data:
                            val = float(data["value"])
                            result["all_measurements"].append(val)
                            
                            # Valid sella turcica range check (5mm - 25mm)
                            if 5.0 <= val <= 25.0:
                                result["valid_measurements"].append(val)
                                
                    result["measurement_count"] = len(result["all_measurements"])
            except KeyError:
                # measurements.plist might not exist if no measurements were made
                pass
                
    except Exception as e:
        result["error"] = str(e)
        result["valid_inv3"] = False

# Save result to JSON
with open("/tmp/sella_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Move result to accessible location if needed (though we use copy_from_env)
chmod 644 /tmp/sella_result.json 2>/dev/null || true

echo "=== Export Complete ==="