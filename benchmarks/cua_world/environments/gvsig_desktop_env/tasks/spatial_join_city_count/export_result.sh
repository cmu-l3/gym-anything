#!/bin/bash
echo "=== Exporting spatial_join_city_count result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_SHP="/home/ga/gvsig_data/exports/countries_city_count.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/countries_city_count.dbf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    OUTPUT_TIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    # Verify file was created during task
    if [ "$OUTPUT_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_TIME="0"
    CREATED_DURING_TASK="false"
fi

# Analyze the shapefile and DBF using Python (embedded script)
# This avoids external dependencies by using standard library struct
echo "Analyzing shapefile content..."
PYTHON_ANALYSIS=$(python3 << 'PYEOF'
import struct
import json
import os
import sys

output_shp = "/home/ga/gvsig_data/exports/countries_city_count.shp"
output_dbf = "/home/ga/gvsig_data/exports/countries_city_count.dbf"

result = {
    "valid_geometry": False,
    "geom_type": "unknown",
    "feature_count": 0,
    "fields": [],
    "has_count_field": False,
    "max_count_value": 0,
    "nonzero_counts": 0,
    "total_count": 0
}

try:
    if os.path.exists(output_shp):
        # Check Geometry Type in SHP header
        with open(output_shp, 'rb') as f:
            f.seek(32)
            shape_type = struct.unpack('<i', f.read(4))[0]
            # 5=Polygon, 15=PolygonZ, 25=PolygonM
            if shape_type in (5, 15, 25):
                result["geom_type"] = "polygon"
                result["valid_geometry"] = True
            elif shape_type in (1, 11, 21):
                result["geom_type"] = "point"
            elif shape_type in (3, 13, 23):
                result["geom_type"] = "polyline"
            else:
                result["geom_type"] = str(shape_type)

    if os.path.exists(output_dbf):
        # Parse DBF header
        with open(output_dbf, 'rb') as f:
            f.seek(4)
            num_records = struct.unpack('<I', f.read(4))[0]
            header_size = struct.unpack('<H', f.read(2))[0]
            record_size = struct.unpack('<H', f.read(2))[0]
            result["feature_count"] = num_records

            # Parse Fields
            f.seek(32)
            fields = []
            count_field_idx = -1
            count_field_offset = 0
            count_field_len = 0
            
            current_offset = 1 # Skip deletion flag
            
            while True:
                field_data = f.read(32)
                if len(field_data) < 32 or field_data[0] == 0x0D:
                    break
                
                name_bytes = field_data[0:11].split(b'\0')[0]
                name = name_bytes.decode('ascii', errors='ignore').strip().upper()
                field_type = chr(field_data[11])
                field_len = field_data[16]
                
                fields.append(name)
                
                # Identify count field (Spatial Join usually creates COUNT, SUM, CNT, etc.)
                if name in ['COUNT', 'CNT', 'SUM', 'JOIN_COUNT', 'NUM_POINTS', 'PNT_CNT']:
                    count_field_idx = len(fields) - 1
                    count_field_offset = current_offset
                    count_field_len = field_len
                
                current_offset += field_len
            
            result["fields"] = fields
            
            # If explicit count field not found, check if we have more fields than original
            # Original countries shapefile has specific fields. 
            # If we see a new numeric field at the end, it might be the count.
            original_fields = ['SCALERANK', 'LABELRANK', 'SOVEREIGNT', 'SOV_A3', 'ADM0_DIF', 
                               'LEVEL', 'TYPE', 'ADMIN', 'ADM0_A3', 'GEOU_DIF', 'GEOUNIT', 
                               'GU_A3', 'SU_DIF', 'SUBUNIT', 'SU_A3', 'BRK_DIFF', 'NAME', 
                               'NAME_LONG', 'BRK_A3', 'BRK_NAME', 'BRK_GROUP', 'ABBREV', 
                               'POSTAL', 'FORMAL_EN', 'FORMAL_FR', 'NOTE_ADM0', 'NOTE_BRK', 
                               'NAME_SORT', 'NAME_ALT', 'MAPCOLOR7', 'MAPCOLOR8', 'MAPCOLOR9', 
                               'MAPCOLOR13', 'POP_EST', 'GDP_MD_EST', 'POP_RANK', 'GDP_YEAR', 
                               'ISO_A2', 'ISO_A3', 'ISO_N3', 'UN_A3', 'WB_A2', 'WB_A3', 
                               'WOE_ID', 'WOE_ID_EH', 'WOE_NOTE', 'ADM0_A3_IS', 'ADM0_A3_US', 
                               'ADM0_A3_UN', 'ADM0_A3_WB', 'CONTINENT', 'REGION_UN', 'SUBREGION', 
                               'REGION_WB', 'NAME_LEN', 'LONG_LEN', 'ABBREV_LEN', 'TINY', 
                               'HOMEPART', 'ECONOMY', 'INCOME_GRP', 'WIKIPEDIA', 'FIPS_10_', 
                               'ISO_A3_EH', 'ISO_N3_EH', 'MIN_ZOOM', 'MIN_LABEL', 'MAX_LABEL', 
                               'NE_ID', 'WIKIDATAID']
            
            # If we didn't identify by name, try heuristics
            if count_field_idx == -1:
                # Look for any field NOT in original list that is Numeric ('N')
                # For this script we assumed 'field_type' variable but we didn't store it in list
                # Let's just trust the name check or 'Count' check above.
                # If fields count > ~95 (original has ~95), likely join worked
                if len(fields) > 95:
                    result["has_count_field"] = True
            else:
                result["has_count_field"] = True
                
                # If we found the specific field, let's scan values
                if num_records > 0:
                    counts = []
                    # Scan first 200 records
                    for i in range(min(num_records, 200)):
                        seek_pos = header_size + (i * record_size) + count_field_offset
                        f.seek(seek_pos)
                        val_bytes = f.read(count_field_len)
                        try:
                            val = float(val_bytes.decode('ascii').strip())
                            counts.append(val)
                        except:
                            pass
                    
                    if counts:
                        result["max_count_value"] = max(counts)
                        result["nonzero_counts"] = sum(1 for c in counts if c > 0)
                        result["total_count"] = sum(counts)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "analysis": $PYTHON_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (permission safe)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="