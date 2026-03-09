#!/bin/bash
set -e
echo "=== Exporting Add Custom Drug Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ============================================================
# Query Database for the Result
# ============================================================

# We search for the specific brand name requested in the task
# We select key fields to verify content accuracy
# Using separator | for easier parsing in the shell script if needed, 
# but passing the raw output to Python is often safer if we assume tab separated.
# Here we'll construct a JSON object manually.

echo "Querying database for 'Menthol 1% Cream'..."

# Get the most recently added drug that matches the brand name pattern
DRUG_DATA=$(oscar_query "SELECT brand_name, generic_name, strength, form, route, create_date FROM drug WHERE brand_name LIKE '%Menthol 1% Cream%' ORDER BY drugid DESC LIMIT 1" 2>/dev/null)

DRUG_FOUND="false"
BRAND=""
GENERIC=""
STRENGTH=""
FORM=""
ROUTE=""
CREATE_DATE=""

if [ -n "$DRUG_DATA" ]; then
    DRUG_FOUND="true"
    # Parse tab-separated values
    BRAND=$(echo "$DRUG_DATA" | cut -f1)
    GENERIC=$(echo "$DRUG_DATA" | cut -f2)
    STRENGTH=$(echo "$DRUG_DATA" | cut -f3)
    FORM=$(echo "$DRUG_DATA" | cut -f4)
    ROUTE=$(echo "$DRUG_DATA" | cut -f5)
    CREATE_DATE=$(echo "$DRUG_DATA" | cut -f6)
    
    echo "Found drug: $BRAND ($GENERIC)"
else
    echo "Drug not found in database."
fi

# Get start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# Construct JSON Result
# ============================================================
# We use Python to robustly create JSON to avoid escaping issues
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'drug_found': $DRUG_FOUND,
    'drug_details': {
        'brand_name': '''$BRAND''',
        'generic_name': '''$GENERIC''',
        'strength': '''$STRENGTH''',
        'form': '''$FORM''',
        'route': '''$ROUTE''',
        'create_date': '''$CREATE_DATE'''
    }
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

# Ensure permissions are open so the host can copy it
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json