#!/bin/bash
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run DB check using Python
cat > /tmp/check_db.py << 'EOF'
import mysql.connector
import json
import os

result = {
    "group_name_found": False,
    "description_found": False,
    "valid_table_found": False,
    "new_record_created": False,
    "found_in_tables": []
}

try:
    db = mysql.connector.connect(host="localhost", user="freemed", password="freemed", database="freemed")
    cursor = db.cursor()
    
    # Read initial counts
    initial_counts = {}
    if os.path.exists('/tmp/initial_table_counts.txt'):
        with open('/tmp/initial_table_counts.txt', 'r') as f:
            for line in f:
                if ':' in line:
                    t, c = line.strip().split(':')
                    initial_counts[t] = int(c)
    
    cursor.execute("SHOW TABLES")
    tables = [t[0] for t in cursor.fetchall()]
    
    for table in tables:
        cursor.execute(f"SELECT COUNT(*) FROM `{table}`")
        current_count = cursor.fetchone()[0]
        initial_count = initial_counts.get(table, 0)
        
        cursor.execute(f"SELECT * FROM `{table}`")
        rows = cursor.fetchall()
        
        table_has_string = False
        table_has_desc = False
        
        for row in rows:
            row_str = str(row).lower()
            if "medical records specialist" in row_str:
                table_has_string = True
                if "scanning" in row_str or "chart" in row_str or "document" in row_str:
                    table_has_desc = True
                    
        if table_has_string:
            # Table must be related to groups, roles, or ACLs. Prevents gaming via messages/notes
            is_valid = any(k in table.lower() for k in ['group', 'role', 'acl'])
            
            result["found_in_tables"].append({
                "table": table,
                "has_description": table_has_desc,
                "initial_count": initial_count,
                "current_count": current_count,
                "is_valid_table": is_valid
            })
            
            if is_valid:
                result["valid_table_found"] = True
                result["group_name_found"] = True
                if table_has_desc:
                    result["description_found"] = True
                if current_count > initial_count:
                    result["new_record_created"] = True

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/check_db.py

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="