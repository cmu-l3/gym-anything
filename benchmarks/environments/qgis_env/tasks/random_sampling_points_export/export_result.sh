#!/bin/bash
echo "=== Exporting Random Sampling Points Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

GEOJSON_PATH="/home/ga/GIS_Data/exports/sampling_points.geojson"
CSV_PATH="/home/ga/GIS_Data/exports/sampling_coordinates.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Analyze results with Python
python3 << PYEOF
import json
import csv
import os
import sys

results = {
    "geojson_exists": False,
    "geojson_valid": False,
    "geojson_feature_count": 0,
    "geojson_all_points": False,
    "geojson_coords_in_bounds": False,
    "geojson_created_during_task": False,
    "csv_exists": False,
    "csv_row_count": 0,
    "csv_has_coord_columns": False,
    "csv_created_during_task": False,
    "timestamp": "$(date -Iseconds)"
}

task_start = int(${TASK_START})

# --- Check GeoJSON ---
if os.path.exists("${GEOJSON_PATH}"):
    results["geojson_exists"] = True
    mtime = int(os.path.getmtime("${GEOJSON_PATH}"))
    if mtime > task_start:
        results["geojson_created_during_task"] = True
        
    try:
        with open("${GEOJSON_PATH}", 'r') as f:
            data = json.load(f)
            
        if data.get("type") == "FeatureCollection" and "features" in data:
            results["geojson_valid"] = True
            features = data["features"]
            results["geojson_feature_count"] = len(features)
            
            # Check geometry type and bounds
            all_points = True
            all_in_bounds = True
            
            for feat in features:
                geom = feat.get("geometry", {})
                if geom.get("type") != "Point":
                    all_points = False
                
                coords = geom.get("coordinates", [])
                if len(coords) >= 2:
                    lon, lat = coords[0], coords[1]
                    # Approx bounds for Central Europe (Austria/Swiss/Czechia)
                    # Lon: 5.0 to 19.0, Lat: 45.0 to 52.0
                    if not (5.0 <= lon <= 19.0 and 45.0 <= lat <= 52.0):
                        all_in_bounds = False
                else:
                    all_in_bounds = False
            
            results["geojson_all_points"] = all_points
            results["geojson_coords_in_bounds"] = all_in_bounds
    except Exception as e:
        results["geojson_error"] = str(e)

# --- Check CSV ---
if os.path.exists("${CSV_PATH}"):
    results["csv_exists"] = True
    mtime = int(os.path.getmtime("${CSV_PATH}"))
    if mtime > task_start:
        results["csv_created_during_task"] = True
        
    try:
        with open("${CSV_PATH}", 'r', encoding='utf-8', errors='replace') as f:
            # Detect delimiter (comma or semicolon)
            sample = f.read(1024)
            f.seek(0)
            dialect = csv.Sniffer().sniff(sample)
            reader = csv.DictReader(f, dialect=dialect)
            
            headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
            rows = list(reader)
            
            results["csv_row_count"] = len(rows)
            
            # Check for coordinate columns
            lon_cols = ['longitude', 'lon', 'long', 'x', 'easting']
            lat_cols = ['latitude', 'lat', 'y', 'northing']
            
            has_lon = any(c in headers for c in lon_cols)
            has_lat = any(c in headers for c in lat_cols)
            
            results["csv_has_coord_columns"] = has_lon and has_lat
            
            # If explicit headers missing, check if values look like coordinates
            if not results["csv_has_coord_columns"] and len(rows) > 0 and len(reader.fieldnames) >= 2:
                # Naive check: Are there two columns with float values in plausible range?
                pass 
                
    except Exception as e:
        results["csv_error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="