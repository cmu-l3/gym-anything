#!/bin/bash
echo "=== Exporting create_sensor_network_layer result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

# Take final screenshot
take_screenshot /tmp/task_end.png

TARGET_FILE="/home/ga/GIS_Data/sensor_network.gpkg"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
ANALYSIS_JSON='{}'

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Inspect GeoPackage using Python and GDAL/OGR
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import sys
import json

try:
    from osgeo import ogr
    
    path = "/home/ga/GIS_Data/sensor_network.gpkg"
    conn = ogr.Open(path)
    
    if not conn:
        print(json.dumps({"valid_gpkg": False, "error": "Could not open file"}))
        sys.exit(0)
        
    # Check layers
    layer_count = conn.GetLayerCount()
    layers = []
    has_sensors_layer = False
    sensors_layer_idx = -1
    
    for i in range(layer_count):
        lyr = conn.GetLayerByIndex(i)
        name = lyr.GetName()
        layers.append(name)
        if name.lower() == 'sensors':
            has_sensors_layer = True
            sensors_layer_idx = i
            
    result = {
        "valid_gpkg": True,
        "layer_count": layer_count,
        "layers": layers,
        "has_sensors_layer": has_sensors_layer
    }
    
    if has_sensors_layer:
        lyr = conn.GetLayerByIndex(sensors_layer_idx)
        
        # Check Geometry
        geom_type = lyr.GetGeomType()
        # ogr.wkbPoint is 1
        is_point = (geom_type == 1)
        result["geometry_type_code"] = geom_type
        result["is_point"] = is_point
        
        # Check CRS
        srs = lyr.GetSpatialRef()
        if srs:
            auth_code = srs.GetAuthorityCode(None)
            auth_name = srs.GetAuthorityName(None)
            result["crs"] = f"{auth_name}:{auth_code}"
            result["is_4326"] = (str(auth_code) == "4326")
        else:
            result["crs"] = "Unknown"
            result["is_4326"] = False
            
        # Check Schema
        defn = lyr.GetLayerDefn()
        field_count = defn.GetFieldCount()
        fields = {}
        for i in range(field_count):
            field_defn = defn.GetFieldDefn(i)
            f_name = field_defn.GetName()
            f_type = field_defn.GetTypeName() # String, Integer, etc.
            fields[f_name] = f_type
            
        result["fields"] = fields
        result["has_model_id"] = "model_id" in fields
        result["has_install_year"] = "install_year" in fields
        
        # Check Data
        feature_count = lyr.GetFeatureCount()
        result["feature_count"] = feature_count
        
        first_feat_values = {}
        if feature_count > 0:
            feat = lyr.GetNextFeature()
            if feat:
                # Safe retrieval of attributes
                if "model_id" in fields:
                    first_feat_values["model_id"] = feat.GetField("model_id")
                if "install_year" in fields:
                    first_feat_values["install_year"] = feat.GetField("install_year")
                    
        result["first_feature_values"] = first_feat_values

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid_gpkg": False, "error": str(e)}))
PYEOF
    )
fi

# Close QGIS cleanly
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Save result to JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_FILE",
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="