#!/bin/bash
set -e
echo "=== Exporting verification results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Run Python script to analyze the output file
python3 << 'PYEOF'
import json
import os
import sys
import glob

result = {
    "file_exists": False,
    "is_valid_geojson": False,
    "feature_count": 0,
    "has_count_field": False,
    "count_field_name": None,
    "count_values_summary": {
        "total": 0,
        "positive_count_features": 0,
        "max": 0
    },
    "has_polygon_geometry": False,
    "polygon_count": 0,
    "file_size_bytes": 0,
    "file_created_after_task_start": False,
    "actual_file_path": None,
    "error": None
}

# Define export directory and potential filenames
export_dir = "/home/ga/GIS_Data/exports"
primary_filename = "countries_with_place_count.geojson"
primary_path = os.path.join(export_dir, primary_filename)

actual_file = None

# Check primary path
if os.path.exists(primary_path):
    actual_file = primary_path
else:
    # Check alternative filenames in the directory
    candidates = [
        "countries_place_count.geojson",
        "count_points.geojson",
        "output.geojson"
    ]
    for cand in candidates:
        cand_path = os.path.join(export_dir, cand)
        if os.path.exists(cand_path):
            actual_file = cand_path
            break
            
    # As a last resort, check for any recently created GeoJSON
    if actual_file is None:
        try:
            with open("/tmp/task_start_time.txt") as f:
                task_start = int(f.read().strip())
        except:
            task_start = 0
            
        json_files = glob.glob(os.path.join(export_dir, "*.geojson"))
        # Sort by modification time, newest first
        json_files.sort(key=os.path.getmtime, reverse=True)
        
        for fpath in json_files:
            if os.path.getmtime(fpath) > task_start:
                actual_file = fpath
                break

if actual_file and os.path.exists(actual_file):
    result["file_exists"] = True
    result["actual_file_path"] = actual_file
    result["file_size_bytes"] = os.path.getsize(actual_file)

    # Check creation/modification time
    try:
        with open("/tmp/task_start_time.txt") as f:
            task_start = int(f.read().strip())
        file_mtime = os.path.getmtime(actual_file)
        if file_mtime > task_start:
            result["file_created_after_task_start"] = True
    except Exception as e:
        print(f"Warning checking timestamp: {e}")

    # Analyze GeoJSON content
    try:
        with open(actual_file, 'r') as f:
            data = json.load(f)

        if data.get("type") == "FeatureCollection" and "features" in data:
            result["is_valid_geojson"] = True
            features = data["features"]
            result["feature_count"] = len(features)

            # Look for count field
            # Common names for the count field
            count_field_candidates = [
                "NUMPOINTS", "numpoints", "Numpoints", "NumPoints",
                "PNTCNT", "pntcnt", "point_count", "POINT_COUNT",
                "count", "COUNT"
            ]
            
            # Scan features to identify fields and geometry
            found_field_name = None
            count_values = []
            polygon_count = 0
            
            for feat in features:
                geom = feat.get("geometry", {})
                props = feat.get("properties", {})
                
                # Check geometry type
                if geom and geom.get("type") in ["Polygon", "MultiPolygon"]:
                    polygon_count += 1
                
                # Identify count field (only need to do this once)
                if not found_field_name:
                    for cand in count_field_candidates:
                        if cand in props:
                            found_field_name = cand
                            break
                    # Fallback partial match if exact match fail
                    if not found_field_name:
                        for key in props.keys():
                            if "count" in key.lower() or "num" in key.lower():
                                # Check if value is integer-like
                                val = props[key]
                                if isinstance(val, (int, float)):
                                    found_field_name = key
                                    break
            
            result["polygon_count"] = polygon_count
            if polygon_count > 0:
                result["has_polygon_geometry"] = True

            if found_field_name:
                result["has_count_field"] = True
                result["count_field_name"] = found_field_name
                
                # Collect stats
                positive_counts = 0
                max_val = 0
                total_sum = 0
                
                for feat in features:
                    val = feat.get("properties", {}).get(found_field_name, 0)
                    try:
                        val = int(val) if val is not None else 0
                    except (ValueError, TypeError):
                        val = 0
                    
                    total_sum += val
                    if val > 0:
                        positive_counts += 1
                    if val > max_val:
                        max_val = val
                        
                result["count_values_summary"]["total"] = total_sum
                result["count_values_summary"]["positive_count_features"] = positive_counts
                result["count_values_summary"]["max"] = max_val

    except json.JSONDecodeError as e:
        result["error"] = f"Invalid JSON: {str(e)}"
    except Exception as e:
        result["error"] = f"Error parsing file: {str(e)}"
else:
    result["error"] = "Output file not found"

# Write result to temp file
with open("/tmp/task_result.json", 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="