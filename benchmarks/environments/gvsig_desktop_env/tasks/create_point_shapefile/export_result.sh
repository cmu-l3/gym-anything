#!/bin/bash
echo "=== Exporting create_point_shapefile results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Define paths
EXPORTS_DIR="/home/ga/gvsig_data/exports"
SHP_PATH="$EXPORTS_DIR/survey_sites.shp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze the output using Python (pyshp) inside the container
# This generates a detailed JSON report about the shapefile content
python3 << EOF > /tmp/shapefile_analysis.json
import json
import os
import time
import sys

result = {
    "file_exists": False,
    "extensions_exist": [],
    "file_created_during_task": False,
    "geometry_type": "Unknown",
    "field_names": [],
    "record_count": 0,
    "records_match": False,
    "valid_geometry": False,
    "records": [],
    "error": None
}

shp_path = "$SHP_PATH"
task_start = $TASK_START

try:
    # Check file existence
    base_path = os.path.splitext(shp_path)[0]
    extensions = []
    for ext in ['.shp', '.shx', '.dbf', '.prj']:
        if os.path.exists(base_path + ext):
            extensions.append(ext)
    
    result["extensions_exist"] = extensions
    
    if '.shp' in extensions and '.shx' in extensions and '.dbf' in extensions:
        result["file_exists"] = True
        
        # Check timestamp
        mtime = os.path.getmtime(shp_path)
        if mtime > task_start:
            result["file_created_during_task"] = True
            
        # Parse Shapefile
        try:
            import shapefile
            sf = shapefile.Reader(shp_path)
            
            # Geometry Type (1=Point, 11=PointZ, 21=PointM)
            result["geometry_type_code"] = sf.shapeType
            if sf.shapeType in [1, 11, 21]:
                result["geometry_type"] = "Point"
            elif sf.shapeType in [3, 13, 23]:
                result["geometry_type"] = "PolyLine"
            elif sf.shapeType in [5, 15, 25]:
                result["geometry_type"] = "Polygon"
                
            # Schema
            # fields[0] is DeletionFlag, skip it
            fields = [f[0] for f in sf.fields[1:]]
            result["field_names"] = fields
            
            # Records
            records = sf.records()
            result["record_count"] = len(records)
            
            # Extract data for verification (normalize keys to lowercase)
            extracted_data = []
            for r in records:
                # Convert record to dict mapping field names to values
                rec_dict = {}
                # Handle different pyshp versions (some return objects, some lists)
                r_dict = r.as_dict() if hasattr(r, 'as_dict') else dict(zip(fields, r))
                
                # Normalize
                clean_dict = {}
                for k, v in r_dict.items():
                    clean_dict[k.lower()] = v
                extracted_data.append(clean_dict)
            
            result["records"] = extracted_data
            
            # Check Geometry Validity
            shapes = sf.shapes()
            valid_geom = True
            for s in shapes:
                # Check for null points or (0,0) if that's unlikely valid
                if not s.points or (len(s.points) > 0 and s.points[0] == [0,0]):
                    # (0,0) is technically valid but unlikely for "anywhere on map" unless intentional
                    # We'll just check if points exist
                    pass
                if len(s.points) == 0:
                    valid_geom = False
            result["valid_geometry"] = valid_geom
            
        except ImportError:
            result["error"] = "pyshp not installed"
        except Exception as e:
            result["error"] = str(e)
            
except Exception as outer_e:
    result["error"] = str(outer_e)

print(json.dumps(result))
EOF

# 4. Final Result Packaging
# Combine the python analysis with standard shell checks
mv /tmp/shapefile_analysis.json /tmp/task_result.json

# Add screenshot path to result
# We use jq if available, or python to append
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}
data['screenshot_path'] = '/tmp/task_final.png'
data['app_running'] = $(pgrep -f "gvSIG" > /dev/null && echo "True" || echo "False")
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json