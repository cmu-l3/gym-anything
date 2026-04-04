#!/bin/bash
echo "=== Exporting land_cover_stats_calculation result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_FILE="/home/ga/GIS_Data/exports/zone_composition.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Analyze Output File using Python
# We use Python to parse the GeoJSON and validate logic
ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import os
import time

filepath = "/home/ga/GIS_Data/exports/zone_composition.geojson"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "file_exists": False,
    "valid_geojson": False,
    "feature_count": 0,
    "fields": [],
    "has_hist_1": False,
    "has_pct_water": False,
    "data": [],
    "is_new_file": False
}

if os.path.exists(filepath):
    result["file_exists"] = True
    
    # Check modification time
    mtime = os.path.getmtime(filepath)
    if mtime > task_start:
        result["is_new_file"] = True
        
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        if data.get("type") == "FeatureCollection":
            result["valid_geojson"] = True
            features = data.get("features", [])
            result["feature_count"] = len(features)
            
            # Extract fields and values
            if len(features) > 0:
                props = features[0].get("properties", {})
                result["fields"] = list(props.keys())
                
                # Check for specific fields (case-insensitive check handled in verifier usually, but let's normalize)
                # QGIS Zonal Histogram usually adds HIST_1, HIST_2 etc, or just 1, 2 depending on settings.
                # We look for "1" or "HIST_1" or similar.
                keys = [k for k in props.keys()]
                
                # Check for Histogram Class 1 (Water)
                # It might be "HIST_1", "1", "Class 1", etc.
                result["has_hist_1"] = any(k == "HIST_1" or k == "1" for k in keys)
                
                # Check for pct_water
                result["has_pct_water"] = "pct_water" in keys
                
                # Extract data for verification
                for feat in features:
                    p = feat.get("properties", {})
                    name = p.get("name", "Unknown")
                    
                    # Try to find class counts
                    c1 = p.get("HIST_1", p.get("1", 0))
                    c2 = p.get("HIST_2", p.get("2", 0))
                    c3 = p.get("HIST_3", p.get("3", 0))
                    
                    # Ensure numeric
                    try: c1 = float(c1)
                    except: c1 = 0
                    try: c2 = float(c2)
                    except: c2 = 0
                    try: c3 = float(c3)
                    except: c3 = 0
                    
                    pct = p.get("pct_water", -1)
                    try: pct = float(pct)
                    except: pct = -1
                    
                    result["data"].append({
                        "name": name,
                        "c1": c1,
                        "c2": c2,
                        "c3": c3,
                        "pct_water": pct
                    })

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Cleanup
if pgrep -f "qgis" > /dev/null; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 5. Save Result JSON
cat > /tmp/task_result.json << EOF
$ANALYSIS_JSON
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="