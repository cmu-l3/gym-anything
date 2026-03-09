#!/bin/bash
echo "=== Exporting dbscan_cluster_world_cities result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Check File System State
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/clustered_cities.geojson"
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
ANALYSIS_JSON="{}"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Python analysis of the GeoJSON content
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import collections

try:
    with open("/home/ga/GIS_Data/exports/clustered_cities.geojson", "r") as f:
        data = json.load(f)

    # Basic validity checks
    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    
    if feature_count == 0:
        print(json.dumps({"valid": True, "feature_count": 0}))
        sys.exit(0)

    # Inspect attributes of first feature to find cluster fields
    sample_props = features[0].get("properties", {})
    keys = list(sample_props.keys())
    
    # Look for cluster-related fields (case-insensitive)
    cluster_field = None
    for k in keys:
        if "cluster" in k.lower() or "dbscan" in k.lower() or k.lower() == "cid":
            cluster_field = k
            break
            
    # Check original attributes (NAME is standard in Natural Earth)
    has_name = any(k.upper() == "NAME" for k in keys)

    # Analyze clusters if field found
    cluster_counts = collections.defaultdict(int)
    unique_clusters = set()
    has_noise = False
    
    if cluster_field:
        for feat in features:
            val = feat.get("properties", {}).get(cluster_field)
            if val is not None:
                # QGIS usually marks noise as NULL, -1, or 0 depending on version/plugin
                # We count distinct values
                unique_clusters.add(val)
                cluster_counts[val] += 1
                
                # Check for noise candidates (often -1 or null)
                if val == -1 or val is None:
                    has_noise = True

    # Check for likely noise if strict -1 check failed
    # If we have many small clusters or a '0' cluster that is different from others
    if not has_noise and len(unique_clusters) > 0:
        # Heuristic: if there's a cluster ID '0' or '-1' it's likely noise
        if -1 in unique_clusters or 0 in unique_clusters:
            has_noise = True

    result = {
        "valid": True,
        "feature_count": feature_count,
        "has_cluster_field": bool(cluster_field),
        "cluster_field_name": cluster_field,
        "distinct_cluster_count": len(unique_clusters),
        "has_noise": has_noise,
        "has_original_attributes": has_name,
        "attribute_keys": keys[:5] # Log first few keys for debugging
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# 4. Check App State
APP_RUNNING="false"
if is_qgis_running; then
    APP_RUNNING="true"
    # Graceful close attempts
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 5. Export Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START_TIME,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_path": "$EXPECTED_FILE",
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure readable
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="