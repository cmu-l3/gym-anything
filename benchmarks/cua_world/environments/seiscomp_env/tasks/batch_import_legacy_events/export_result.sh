#!/bin/bash
echo "=== Exporting batch_import_legacy_events result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export database contents specific to this task
echo "Querying SeisComP database for imported legacy records..."
mysql -u sysop -psysop seiscomp -B -N -e "SELECT time_value, latitude_value, longitude_value, depth_value FROM Origin WHERE creationInfo_agencyID='LEGACY_IMPORT';" > /tmp/legacy_origins.tsv 2>/dev/null || true
mysql -u sysop -psysop seiscomp -B -N -e "SELECT magnitude_value, type FROM Magnitude WHERE creationInfo_agencyID='LEGACY_IMPORT';" > /tmp/legacy_mags.tsv 2>/dev/null || true
mysql -u sysop -psysop seiscomp -B -N -e "SELECT _oid FROM Event WHERE creationInfo_agencyID='LEGACY_IMPORT';" > /tmp/legacy_events.tsv 2>/dev/null || true

# Process verification using Python to package safely into JSON
python3 << 'PYEOF'
import json
import os

task_start_time = 0
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start_time = int(f.read().strip())
except:
    pass

def get_file_info(path):
    if os.path.exists(path):
        mtime = os.path.getmtime(path)
        return {
            "exists": True,
            "size": os.path.getsize(path),
            "created_during_task": mtime >= task_start_time
        }
    return {"exists": False, "size": 0, "created_during_task": False}

result = {
    "script_file": get_file_info("/home/ga/Documents/csv_to_scml.py"),
    "scml_file": get_file_info("/home/ga/Documents/legacy_events.scml"),
    "origins": [],
    "magnitudes": [],
    "events_count": 0
}

# Parse Origins
try:
    if os.path.exists("/tmp/legacy_origins.tsv"):
        with open("/tmp/legacy_origins.tsv", "r") as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 4:
                    result["origins"].append({
                        "time": parts[0],
                        "lat": float(parts[1]),
                        "lon": float(parts[2]),
                        "depth": float(parts[3])
                    })
except Exception as e:
    result["origins_error"] = str(e)

# Parse Magnitudes
try:
    if os.path.exists("/tmp/legacy_mags.tsv"):
        with open("/tmp/legacy_mags.tsv", "r") as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 2:
                    result["magnitudes"].append({
                        "mag": float(parts[0]),
                        "type": parts[1]
                    })
except Exception as e:
    result["mags_error"] = str(e)

# Parse Events Count
try:
    if os.path.exists("/tmp/legacy_events.tsv"):
        with open("/tmp/legacy_events.tsv", "r") as f:
            result["events_count"] = len([l for l in f.read().splitlines() if l.strip()])
except Exception as e:
    pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="