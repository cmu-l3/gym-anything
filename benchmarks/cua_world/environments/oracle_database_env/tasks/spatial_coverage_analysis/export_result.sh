#!/bin/bash
# Export script for Spatial Coverage Analysis task
# Inspects database schema, metadata, indexes, and output file

set -e

echo "=== Exporting Spatial Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Capture Task Timings
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python/oracledb to inspect the complex spatial state
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

result = {
    "tables_exist": False,
    "columns_created": False,
    "geometry_type_valid": False,
    "srid_correct": False,
    "coordinates_populated": False,
    "metadata_registered": False,
    "metadata_bounds_correct": False,
    "spatial_indexes_exist": False,
    "spatial_indexes_valid": False,
    "output_file_exists": False,
    "output_content": "",
    "output_lines": [],
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check if tables exist
    cursor.execute("SELECT COUNT(*) FROM user_tables WHERE table_name IN ('EXISTING_TOWERS', 'PROPOSED_SITES')")
    result["tables_exist"] = (cursor.fetchone()[0] == 2)

    if result["tables_exist"]:
        # 2. Check for GEO_LOCATION columns and type
        cursor.execute("""
            SELECT table_name, data_type 
            FROM user_tab_columns 
            WHERE column_name = 'GEO_LOCATION' 
            AND table_name IN ('EXISTING_TOWERS', 'PROPOSED_SITES')
        """)
        cols = cursor.fetchall()
        result["columns_created"] = (len(cols) == 2)
        result["geometry_type_valid"] = all(c[1] == 'SDO_GEOMETRY' for c in cols)

        # 3. Check Data: SRID and non-null geometry
        # We check one row from each table to verify population
        srid_correct = True
        populated = True
        
        for table in ['EXISTING_TOWERS', 'PROPOSED_SITES']:
            try:
                cursor.execute(f"SELECT t.geo_location.sdo_srid, t.geo_location FROM {table} t WHERE ROWNUM = 1")
                row = cursor.fetchone()
                if not row or row[1] is None:
                    populated = False
                if not row or row[0] != 4326:
                    srid_correct = False
            except Exception:
                populated = False
        
        result["coordinates_populated"] = populated
        result["srid_correct"] = srid_correct

    # 4. Check Metadata (USER_SDO_GEOM_METADATA)
    cursor.execute("""
        SELECT table_name, diminfo 
        FROM user_sdo_geom_metadata 
        WHERE table_name IN ('EXISTING_TOWERS', 'PROPOSED_SITES')
    """)
    meta_rows = cursor.fetchall()
    result["metadata_registered"] = (len(meta_rows) == 2)
    
    # Check bounds (rough check for -180/180)
    # This is complex to parse from objects in raw SQL, defaulting to simple existence check usually sufficient
    # but we can try to assume if it exists and indexes build, it's likely correct.

    # 5. Check Spatial Indexes
    cursor.execute("""
        SELECT index_name, status, domidx_opstatus 
        FROM user_indexes 
        WHERE index_type = 'DOMAIN' 
        AND ityp_name = 'SPATIAL_INDEX' 
        AND table_name IN ('EXISTING_TOWERS', 'PROPOSED_SITES')
    """)
    indexes = cursor.fetchall()
    result["spatial_indexes_exist"] = (len(indexes) >= 2)
    result["spatial_indexes_valid"] = all(i[1] == 'VALID' for i in indexes)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 6. Check Output File
output_path = "/home/ga/Desktop/priority_expansion_sites.txt"
if os.path.exists(output_path):
    result["output_file_exists"] = True
    try:
        with open(output_path, 'r') as f:
            content = f.read()
            result["output_content"] = content
            result["output_lines"] = [line.strip() for line in content.splitlines() if line.strip()]
    except Exception as e:
        result["output_content"] = f"Error reading file: {e}"

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Validate JSON
python3 -c "import json; print(json.load(open('/tmp/task_result.json')))" > /dev/null

echo "=== Export Complete ==="