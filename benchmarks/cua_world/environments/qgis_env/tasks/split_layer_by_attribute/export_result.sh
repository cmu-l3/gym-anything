#!/bin/bash
echo "=== Exporting split_layer_by_attribute result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_end.png

OUTPUT_DIR="/home/ga/GIS_Data/exports/countries_by_continent"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 2. Analyze Output Files
# We use Python to rigorously inspect the output directory content
ANALYSIS=$(python3 << 'PYEOF'
import os
import json
import glob
import sys

output_dir = "/home/ga/GIS_Data/exports/countries_by_continent"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

result = {
    "files_found": 0,
    "files_created_during_task": 0,
    "valid_geojson_count": 0,
    "total_features": 0,
    "continents_found": [],
    "split_correct": True,
    "details": []
}

try:
    geojson_files = glob.glob(os.path.join(output_dir, "*.geojson"))
    result["files_found"] = len(geojson_files)

    for fpath in geojson_files:
        file_stat = os.stat(fpath)
        is_new = file_stat.st_mtime > task_start
        if is_new:
            result["files_created_during_task"] += 1
        
        fname = os.path.basename(fpath)
        file_info = {
            "name": fname,
            "is_new": is_new,
            "valid": False,
            "feature_count": 0,
            "unique_continents": []
        }

        try:
            with open(fpath, 'r') as f:
                data = json.load(f)
                
            if data.get("type") == "FeatureCollection":
                file_info["valid"] = True
                result["valid_geojson_count"] += 1
                features = data.get("features", [])
                file_info["feature_count"] = len(features)
                result["total_features"] += len(features)
                
                # Check consistency of CONTINENT attribute
                continents = set()
                for feat in features:
                    props = feat.get("properties", {})
                    # Handle potential case variations or slightly different field names if agent renamed
                    # But task asks to split by 'CONTINENT', so we check that specific key
                    cont = props.get("CONTINENT")
                    if cont:
                        continents.add(cont)
                
                file_info["unique_continents"] = list(continents)
                
                if len(continents) == 1:
                    result["continents_found"].append(list(continents)[0])
                elif len(continents) > 1:
                    result["split_correct"] = False  # File contains mixed continents
        except Exception as e:
            file_info["error"] = str(e)
            
        result["details"].append(file_info)

    # Final logic checks
    if result["files_found"] == 0:
        result["split_correct"] = False
        
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
"$TASK_START")

# 3. Clean up
if is_qgis_running; then
    kill_qgis ga 2>/dev/null || true
fi

# 4. Save Result
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "analysis": $ANALYSIS
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved:"
cat /tmp/task_result.json
echo "=== Export Complete ==="