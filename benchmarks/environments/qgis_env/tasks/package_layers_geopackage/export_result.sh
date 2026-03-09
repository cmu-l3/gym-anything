#!/bin/bash
set -e
echo "=== Exporting package_layers_geopackage results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
GPKG_PATH="/home/ga/GIS_Data/exports/project_data.gpkg"
PROJECT_DIR="/home/ga/GIS_Data/projects"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to inspect the GeoPackage (it's an SQLite DB)
# We embed the python script to run inside the container
python3 << 'PYEOF'
import json
import os
import sqlite3
import sys
import glob

result = {
    "gpkg_exists": False,
    "gpkg_valid_sqlite": False,
    "gpkg_has_contents_table": False,
    "gpkg_layers": [],
    "gpkg_layer_details": {},
    "gpkg_size_bytes": 0,
    "gpkg_created_after_task_start": False,
    "project_exists": False,
    "project_path": None,
    "project_size_bytes": 0
}

gpkg_path = "/home/ga/GIS_Data/exports/project_data.gpkg"
project_prefix = "/home/ga/GIS_Data/projects/delivery_project"
task_start_path = "/tmp/task_start_time.txt"

# Get task start time
try:
    with open(task_start_path, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Check GeoPackage
if os.path.exists(gpkg_path):
    result["gpkg_exists"] = True
    result["gpkg_size_bytes"] = os.path.getsize(gpkg_path)
    
    # Check timestamp
    mtime = os.path.getmtime(gpkg_path)
    if mtime > task_start:
        result["gpkg_created_after_task_start"] = True

    # Validate SQLite/GeoPackage structure
    try:
        conn = sqlite3.connect(gpkg_path)
        cursor = conn.cursor()
        
        # Check if it's a valid database
        cursor.execute("PRAGMA integrity_check;")
        integrity = cursor.fetchone()
        if integrity and integrity[0] == "ok":
            result["gpkg_valid_sqlite"] = True
            
        # Check for gpkg_contents (standard GeoPackage table)
        try:
            cursor.execute("SELECT table_name, data_type, srs_id FROM gpkg_contents")
            rows = cursor.fetchall()
            result["gpkg_has_contents_table"] = True
            
            for row in rows:
                table_name = row[0]
                data_type = row[1]
                srs_id = row[2]
                
                # Verify this is a user table (features)
                if data_type == 'features':
                    result["gpkg_layers"].append(table_name)
                    
                    # Count features in the table
                    try:
                        cursor.execute(f'SELECT COUNT(*) FROM "{table_name}"')
                        count = cursor.fetchone()[0]
                        
                        # Get geometry type from gpkg_geometry_columns
                        geom_type = "unknown"
                        try:
                            cursor.execute('SELECT geometry_type_name FROM gpkg_geometry_columns WHERE table_name=?', (table_name,))
                            g_row = cursor.fetchone()
                            if g_row:
                                geom_type = g_row[0]
                        except:
                            pass
                            
                        result["gpkg_layer_details"][table_name] = {
                            "count": count,
                            "geom_type": geom_type,
                            "srs_id": srs_id
                        }
                    except Exception as e:
                        result["gpkg_layer_details"][table_name] = {"error": str(e)}

        except sqlite3.OperationalError:
            pass # gpkg_contents missing
            
        conn.close()
    except Exception as e:
        result["sqlite_error"] = str(e)

# Check Project File
# Check for .qgs or .qgz
for ext in ['.qgs', '.qgz']:
    p_path = project_prefix + ext
    if os.path.exists(p_path):
        result["project_exists"] = True
        result["project_path"] = p_path
        result["project_size_bytes"] = os.path.getsize(p_path)
        break

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to allow permission access if needed
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="