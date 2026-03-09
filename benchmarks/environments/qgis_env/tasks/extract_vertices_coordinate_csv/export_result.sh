#!/bin/bash
set -e
echo "=== Exporting verification results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

RESULT_FILE="/tmp/extract_vertices_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check for CSV file
CSV_PATH="/home/ga/GIS_Data/exports/polygon_vertices.csv"

# Also check alternative locations/names if main one missing
if [ ! -f "$CSV_PATH" ]; then
    ALT=$(find /home/ga/GIS_Data/exports/ -name "*vertice*.csv" -o -name "*vertex*.csv" 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        CSV_PATH="$ALT"
        echo "Found alternative CSV: $CSV_PATH"
    fi
fi

# Check for project file
PROJECT_EXISTS="false"
if ls /home/ga/GIS_Data/projects/vertex_extraction.qg* 1> /dev/null 2>&1; then
    PROJECT_EXISTS="true"
fi

# Use Python to parse CSV and generate comprehensive result JSON
python3 << PYEOF
import json
import csv
import os
import sys
import time

result = {
    "csv_exists": False,
    "csv_valid": False,
    "row_count": 0,
    "has_coord_columns": False,
    "coords_in_range": False,
    "has_vertex_index": False,
    "file_is_new": False,
    "project_exists": ${PROJECT_EXISTS,,}, # convert bash string to python bool
    "column_names": [],
    "sample_rows": [],
    "errors": [],
    "x_col_name": None,
    "y_col_name": None,
    "coords_in_range_count": 0
}

csv_path = "$CSV_PATH"

if os.path.isfile(csv_path):
    result["csv_exists"] = True
    
    # Check timestamp
    try:
        file_mtime = int(os.path.getmtime(csv_path))
        start_time = int("$TASK_START_TIME")
        result["file_is_new"] = file_mtime > start_time
    except Exception as e:
        result["errors"].append(f"Timestamp check error: {str(e)}")

    # Parse CSV content
    try:
        with open(csv_path, 'r', newline='', errors='replace') as f:
            # Sniff delimiter
            sample = f.read(2048)
            f.seek(0)
            sniffer = csv.Sniffer()
            try:
                dialect = sniffer.sniff(sample)
                has_header = sniffer.has_header(sample)
            except:
                dialect = None
            
            if dialect:
                reader = csv.DictReader(f, dialect=dialect)
            else:
                # Fallback to comma
                reader = csv.DictReader(f)
                
            columns = reader.fieldnames or []
            result["column_names"] = list(columns)
            
            rows = []
            for row in reader:
                rows.append(dict(row))
            
            result["row_count"] = len(rows)
            result["csv_valid"] = len(rows) > 0 and len(columns) > 0
            result["sample_rows"] = rows[:3] if rows else []
            
            # Identify coordinate columns (fuzzy match)
            col_map = {c.lower().strip(): c for c in columns}
            
            x_candidates = ['xcoord', 'longitude', 'lon', 'long', 'x_coord', 'x']
            y_candidates = ['ycoord', 'latitude', 'lat', 'y_coord', 'y']
            
            x_col = None
            y_col = None
            
            for cand in x_candidates:
                if cand in col_map: x_col = col_map[cand]; break
                # check partial match
                for c in col_map:
                    if cand in c: x_col = col_map[c]; break
                if x_col: break
            
            for cand in y_candidates:
                if cand in col_map: y_col = col_map[cand]; break
                for c in col_map:
                    if cand in c: y_col = col_map[c]; break
                if y_col: break
                
            result["x_col_name"] = x_col
            result["y_col_name"] = y_col
            result["has_coord_columns"] = (x_col is not None and y_col is not None)
            
            # Check coordinate ranges
            if x_col and y_col and rows:
                valid_count = 0
                for row in rows:
                    try:
                        x = float(row.get(x_col, 0))
                        y = float(row.get(y_col, 0))
                        # Expected range: lon -122.6 to -121.8, lat 37.4 to 37.9
                        if -122.6 <= x <= -121.8 and 37.4 <= y <= 37.9:
                            valid_count += 1
                    except ValueError:
                        pass
                result["coords_in_range_count"] = valid_count
                # If at least 70% of rows are valid, consider pass
                if len(rows) > 0:
                    result["coords_in_range"] = (valid_count / len(rows)) > 0.7

            # Check for vertex index
            idx_candidates = ['vertex_index', 'vertex_pos', 'vertex_part', 'fid', 'id', 'vertex']
            for cand in idx_candidates:
                found = False
                for c in col_map:
                    if cand in c: 
                        result["has_vertex_index"] = True
                        found = True
                        break
                if found: break

    except Exception as e:
        result["errors"].append(f"CSV parse error: {str(e)}")

# Close QGIS cleanly
try:
    os.system("su - ga -c 'DISPLAY=:1 xdotool key ctrl+q'")
    time.sleep(2)
    os.system("pkill -u ga -f qgis")
except:
    pass

# Write result to temp file then move
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=2)
os.rename('/tmp/temp_result.json', '$RESULT_FILE')
os.chmod('$RESULT_FILE', 0o666)

print("Verification result generated.")
PYEOF

cat "$RESULT_FILE"
echo "=== Export complete ==="