#!/bin/bash
echo "=== Exporting Custom Billing Code Result ==="

# 1. Take final screenshot for visual verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for the created code
# We look in the 'cpt' table which typically stores service codes in NOSH/OpenEMR schemas
# We fetch relevant columns: code, description (code_text), fee (charge), active status
echo "Querying database for SPT-PHY..."

# Execute query via Docker
# Note: Schema column names are assumed based on standard NOSH structure. 
# Adjusting to likely column names: code, code_text, charge, active
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT code, code_text, charge, active FROM cpt WHERE code='SPT-PHY' LIMIT 1" 2>/dev/null)

# 3. Parse Result
FOUND="false"
CODE=""
DESCRIPTION=""
FEE="0"
ACTIVE=""

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    CODE=$(echo "$DB_RESULT" | awk '{print $1}')
    # Description might contain spaces, so we cut from index
    # However, awk default split is space. A safer way for tab separated (mysql -N output is tab separated usually)
    # But mysql shell output format can vary. Let's assume tab separation.
    
    CODE=$(echo "$DB_RESULT" | cut -f1)
    DESCRIPTION=$(echo "$DB_RESULT" | cut -f2)
    FEE=$(echo "$DB_RESULT" | cut -f3)
    ACTIVE=$(echo "$DB_RESULT" | cut -f4)
    
    echo "Found record: Code=$CODE, Desc=$DESCRIPTION, Fee=$FEE, Active=$ACTIVE"
else
    echo "No record found for SPT-PHY"
fi

# 4. Create JSON Result
# Use python for safe JSON creation to handle strings with quotes/spaces
python3 -c "
import json
import sys

try:
    result = {
        'found': $FOUND,
        'code': '$CODE',
        'description': '''$DESCRIPTION''',
        'fee': '$FEE',
        'active': '$ACTIVE',
        'timestamp': '$(date -Iseconds)'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    print(f'Error creating JSON: {e}')
"

# Set permissions so the host can read it via copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json