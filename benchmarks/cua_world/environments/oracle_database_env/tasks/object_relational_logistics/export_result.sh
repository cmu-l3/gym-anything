#!/bin/bash
# Export script for Object-Relational Logistics task
# Inspects database objects, types, nested table storage, and view calculations.

set -e
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if file was modified (anti-gaming, though strictly this task is DB based)
FILE_MODIFIED="false"
if [ -f "/home/ga/Desktop/legacy_manifests.csv" ]; then
    # We don't expect them to modify the CSV, but just checking
    FILE_MODIFIED="false" 
fi

# Python script to query database metadata and data
python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "types_exist": False,
    "types_valid": False,
    "table_exists": False,
    "nested_column_type": None,
    "storage_table_name": None,
    "row_count": 0,
    "view_exists": False,
    "view_data": {},
    "sample_nested_data": [],
    "errors": []
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Types
    cursor.execute("""
        SELECT type_name, typecode, attributes 
        FROM user_types 
        WHERE type_name IN ('T_MANIFEST_ITEM', 'T_MANIFEST_TAB')
    """)
    found_types = {row[0]: row[1] for row in cursor.fetchall()}
    if "T_MANIFEST_ITEM" in found_types and "T_MANIFEST_TAB" in found_types:
        result["types_exist"] = True
        if found_types["T_MANIFEST_ITEM"] == "OBJECT" and found_types["T_MANIFEST_TAB"] == "COLLECTION":
            result["types_valid"] = True

    # 2. Check Table and Nested Column
    cursor.execute("""
        SELECT data_type 
        FROM user_tab_cols 
        WHERE table_name = 'SHIPMENT_OBJECTS' AND column_name = 'MANIFEST'
    """)
    row = cursor.fetchone()
    if row:
        result["table_exists"] = True
        result["nested_column_type"] = row[0] # Should be T_MANIFEST_TAB

    # 3. Check Nested Table Storage Name
    # Oracle stores this in user_nested_tables
    cursor.execute("""
        SELECT table_name 
        FROM user_nested_tables 
        WHERE parent_table_name = 'SHIPMENT_OBJECTS'
    """)
    row = cursor.fetchone()
    if row:
        result["storage_table_name"] = row[0]

    # 4. Check Data Content (Row Count)
    if result["table_exists"]:
        cursor.execute("SELECT COUNT(*) FROM shipment_objects")
        result["row_count"] = cursor.fetchone()[0]

        # 5. Check specific nested data for Shipment 1003
        # Unnesting using TABLE() operator
        try:
            cursor.execute("""
                SELECT i.item_name, i.quantity, i.unit_weight_kg
                FROM shipment_objects s, TABLE(s.manifest) i
                WHERE s.shipment_id = 1003
                ORDER BY i.item_name
            """)
            result["sample_nested_data"] = [
                {"name": r[0], "qty": r[1], "weight": r[2]} 
                for r in cursor.fetchall()
            ]
        except Exception as e:
            result["errors"].append(f"Failed to query nested data: {str(e)}")

    # 6. Check View
    cursor.execute("""
        SELECT object_name, object_type, status 
        FROM user_objects 
        WHERE object_name = 'V_MANIFEST_WEIGHTS' AND object_type = 'VIEW'
    """)
    row = cursor.fetchone()
    if row and row[2] == 'VALID':
        result["view_exists"] = True
        
        try:
            cursor.execute("""
                SELECT shipment_id, total_items, total_weight_kg 
                FROM v_manifest_weights 
                ORDER BY shipment_id
            """)
            # Store as dict keyed by shipment_id
            for r in cursor.fetchall():
                result["view_data"][str(r[0])] = {
                    "total_items": float(r[1]),
                    "total_weight": float(r[2])
                }
        except Exception as e:
            result["errors"].append(f"Failed to query view: {str(e)}")

    cursor.close()
    conn.close()

except Exception as e:
    result["errors"].append(f"Database error: {str(e)}")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json