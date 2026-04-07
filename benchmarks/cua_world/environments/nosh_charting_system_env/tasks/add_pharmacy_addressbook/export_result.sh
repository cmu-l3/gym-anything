#!/bin/bash
# Export script for Add Pharmacy Address Book task
set -e

echo "=== Exporting add_pharmacy_addressbook result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get verification data from Database
# We search for the specific pharmacy we asked the agent to create.
# We fetch the most recently added one matching the name to handle multiple attempts.
echo "Querying database for new pharmacy entry..."

# We use a broad LIKE query to find potential matches, then verify fields in python
# Selecting commonly used columns for address book in NOSH/OpenEMR-like systems
DB_RESULT=$(docker exec nosh-db mysql -N -uroot -prootpassword nosh -e \
    "SELECT address_id, displayname, facility, street_address1, city, state, zip, phone, fax, specialty \
     FROM addressbook \
     WHERE displayname LIKE '%Springfield Family Pharmacy%' OR facility LIKE '%Springfield Family Pharmacy%' \
     ORDER BY address_id DESC LIMIT 1;" 2>/dev/null || true)

# 3. Get counts
INITIAL_COUNT=$(cat /tmp/initial_addressbook_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(docker exec nosh-db mysql -N -uroot -prootpassword nosh -e "SELECT COUNT(*) FROM addressbook;" 2>/dev/null || echo "0")

# 4. Construct JSON result
# Use python to safely construct JSON and handle potentially empty DB results
python3 -c "
import json
import sys

try:
    db_row = '''$DB_RESULT'''.strip().split('\t')
    initial = int('$INITIAL_COUNT')
    current = int('$CURRENT_COUNT')
    
    found = False
    entry = {}
    
    if len(db_row) >= 9: # Ensure we have enough columns
        found = True
        # Map columns based on query order
        # address_id, displayname, facility, street_address1, city, state, zip, phone, fax, specialty
        entry = {
            'id': db_row[0],
            'displayname': db_row[1] if len(db_row) > 1 else '',
            'facility': db_row[2] if len(db_row) > 2 else '',
            'street_address1': db_row[3] if len(db_row) > 3 else '',
            'city': db_row[4] if len(db_row) > 4 else '',
            'state': db_row[5] if len(db_row) > 5 else '',
            'zip': db_row[6] if len(db_row) > 6 else '',
            'phone': db_row[7] if len(db_row) > 7 else '',
            'fax': db_row[8] if len(db_row) > 8 else '',
            'specialty': db_row[9] if len(db_row) > 9 else ''
        }

    result = {
        'initial_count': initial,
        'current_count': current,
        'entry_found': found,
        'entry': entry,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e), 'entry_found': False}, indent=2))

" > /tmp/task_result.json

# 5. Permission fix for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="