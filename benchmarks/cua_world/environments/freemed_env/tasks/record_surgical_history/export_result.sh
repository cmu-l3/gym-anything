#!/bin/bash
echo "=== Exporting record_surgical_history result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Create a Python script to scan the database schema for the target data.
# This avoids guessing the exact EMR table name (which varies by FreeMED versions) 
# and programmatically locates the 'Cholecystectomy' substring across all clinical tables.

cat > /tmp/db_scanner.py << 'EOF'
import mysql.connector
import json
import sys

def scan_db():
    result = {
        "success": False,
        "patient_id": -1,
        "records": [],
        "error": None
    }
    
    try:
        conn = mysql.connector.connect(user='freemed', password='freemed', database='freemed')
        cursor = conn.cursor(dictionary=True)
        
        # 1. Get Thomas Anderson's ID
        cursor.execute("SELECT id FROM patient WHERE ptfname='Thomas' AND ptlname='Anderson' LIMIT 1")
        pt = cursor.fetchone()
        if not pt:
            result["error"] = "Patient Thomas Anderson not found in DB."
            return result
            
        pt_id = pt['id']
        result["patient_id"] = pt_id
        
        # 2. Get all tables
        cursor.execute("SHOW TABLES")
        tables = [list(r.values())[0] for r in cursor.fetchall()]
        
        # 3. Scan tables for the text "Cholecystectomy"
        for table in tables:
            cursor.execute(f"SHOW COLUMNS FROM {table}")
            cols = cursor.fetchall()
            
            # Find text-based columns
            text_cols = [c['Field'] for c in cols if 'char' in c['Type'].lower() or 'text' in c['Type'].lower()]
            if not text_cols:
                continue
                
            where_clauses = [f"{c} LIKE '%Cholecystectomy%'" for c in text_cols]
            query = f"SELECT * FROM {table} WHERE " + " OR ".join(where_clauses)
            
            try:
                cursor.execute(query)
                rows = cursor.fetchall()
                
                for row in rows:
                    # Check if the row contains the patient ID (FreeMED relies heavily on numeric foreign keys)
                    linked_to_patient = False
                    for k, v in row.items():
                        if str(v) == str(pt_id):
                            linked_to_patient = True
                            break
                            
                    # Convert dict values to strings for JSON serialization
                    row_str = {k: str(v) for k, v in row.items()}
                    
                    result["records"].append({
                        "table": table,
                        "row_data": row_str,
                        "linked_to_patient": linked_to_patient
                    })
            except Exception as e:
                # Ignore tables that fail to query (e.g., views or corrupted tables)
                pass
                
        result["success"] = True
        return result
        
    except Exception as e:
        result["error"] = str(e)
        return result

if __name__ == "__main__":
    print(json.dumps(scan_db()))
EOF

# Run scanner and save output to temporary JSON file
python3 /tmp/db_scanner.py > /tmp/task_result_temp.json

# Add task timestamps and finalize JSON output
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Merge metadata into the final JSON output
jq --arg start "$START_TIME" --arg end "$END_TIME" \
   '. + {task_start: ($start|tonumber), task_end: ($end|tonumber)}' \
   /tmp/task_result_temp.json > /tmp/task_result.json

chmod 666 /tmp/task_result.json

echo "Export complete. Database scanner results:"
cat /tmp/task_result.json