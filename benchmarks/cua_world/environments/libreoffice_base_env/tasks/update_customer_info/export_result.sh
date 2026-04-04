#!/bin/bash
set -e
echo "=== Exporting update_customer_info result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file modification
FILE_MODIFIED="false"
FILE_SAVED_DURING_TASK="false"
CURRENT_HASH=""
INITIAL_HASH=$(cat /tmp/initial_odb_hash.txt 2>/dev/null || echo "")

if [ -f "$ODB_PATH" ]; then
    CURRENT_HASH=$(md5sum "$ODB_PATH" | awk '{print $1}')
    FILE_MTIME=$(stat -c %Y "$ODB_PATH")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_SAVED_DURING_TASK="true"
    fi
fi

# 2. Extract data from ODB to verify specific record updates
# The ODB is a zip file. The data is inside 'database/script' (for HSQLDB embedded memory tables).
# We will unzip it and use a python script to parse the SQL INSERT statement.

mkdir -p /tmp/odb_extract
rm -rf /tmp/odb_extract/*
unzip -q -o "$ODB_PATH" "database/script" -d /tmp/odb_extract/ 2>/dev/null || true

DATA_FOUND="false"
CUSTOMER_DATA="{}"

if [ -f "/tmp/odb_extract/database/script" ]; then
    # Create a python script to parse the SQL dump
    # We are looking for: INSERT INTO "Customer" VALUES(17,...)
    cat > /tmp/parse_odb_data.py << 'EOF'
import re
import json
import sys

def parse_sql_value(val):
    val = val.strip()
    if val == 'NULL':
        return None
    if val.startswith("'") and val.endswith("'"):
        # Basic unescaping for SQL
        return val[1:-1].replace("''", "'")
    return val

try:
    target_id = 17
    # Regex to find the insert statement for Customer 17
    # INSERT INTO "Customer" VALUES(17,'Jack','Smith',...)
    # We need to handle the fact that values are comma separated but can contain commas inside quotes.
    
    with open('/tmp/odb_extract/database/script', 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            if line.startswith('INSERT INTO "Customer" VALUES') or line.startswith("INSERT INTO \"Customer\" VALUES"):
                # Check if it's ID 17
                if f"VALUES({target_id}," in line.replace(" ", ""):
                    # Simple CSV-like parsing for the values part
                    # Extract content inside VALUES(...)
                    content = line[line.find("VALUES(")+7 : line.rfind(")")]
                    
                    # Split by comma respecting quotes
                    # This is a simple parser, might be fragile for complex nested quotes but sufficient here
                    values = []
                    current_val = []
                    in_quote = False
                    for char in content:
                        if char == "'" and (not current_val or current_val[-1] != '\\'): # Simple quote check
                            in_quote = not in_quote
                            current_val.append(char)
                        elif char == ',' and not in_quote:
                            values.append("".join(current_val))
                            current_val = []
                        else:
                            current_val.append(char)
                    values.append("".join(current_val))
                    
                    # Map to schema:
                    # 0:CustomerId, 1:FirstName, 2:LastName, 3:Company, 4:Address, 5:City, 6:State, 
                    # 7:Country, 8:PostalCode, 9:Phone, 10:Fax, 11:Email, 12:SupportRepId
                    
                    # Clean values
                    clean_values = [parse_sql_value(v) for v in values]
                    
                    if len(clean_values) >= 12:
                        record = {
                            "CustomerId": clean_values[0],
                            "FirstName": clean_values[1],
                            "LastName": clean_values[2],
                            "Company": clean_values[3],
                            "Address": clean_values[4],
                            "City": clean_values[5],
                            "State": clean_values[6],
                            "Country": clean_values[7],
                            "PostalCode": clean_values[8],
                            "Phone": clean_values[9],
                            "Fax": clean_values[10],
                            "Email": clean_values[11]
                        }
                        print(json.dumps(record))
                        sys.exit(0)
                        
    print("{}")
except Exception as e:
    sys.stderr.write(str(e))
    print("{}")
EOF

    CUSTOMER_DATA=$(python3 /tmp/parse_odb_data.py)
    if [ "$CUSTOMER_DATA" != "{}" ]; then
        DATA_FOUND="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "file_saved_during_task": $FILE_SAVED_DURING_TASK,
    "data_found_in_script": $DATA_FOUND,
    "record_data": $CUSTOMER_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="