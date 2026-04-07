#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting correct_personal_data_discrepancies results ==="

# 1. Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Query Employee Data for Verification
# We fetch the relevant columns for the 3 target employees
# We also join with nationality table to get text names for easier verification

QUERY="
SELECT 
    e.emp_firstname, 
    e.emp_lastname, 
    e.emp_birthday, 
    e.marital_status, 
    e.emp_gender, 
    n.name as nationality_name,
    e.emp_dri_lice_exp_date
FROM hs_hr_employee e
LEFT JOIN ohrm_nationality n ON e.nation_code = n.id
WHERE e.emp_firstname IN ('Dario', 'Mei', 'Sven') 
  AND e.emp_lastname IN ('Rossi', 'Chen', 'Olson')
  AND e.purged_at IS NULL;
"

# Execute query and format as JSON-like structure manually or strictly parsable text
# We'll output tab-separated values to a file, then convert to JSON with Python inline
DATA_FILE="/tmp/employee_data.tsv"
orangehrm_db_query "$QUERY" > "$DATA_FILE"

# 4. Convert to JSON
# Python script to parse the TSV and create the final result JSON
python3 -c "
import json
import time

employees = {}
try:
    with open('$DATA_FILE', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            # Handle potential NULLs which come as string 'NULL' or empty depending on client
            if len(parts) >= 6:
                fname = parts[0]
                lname = parts[1]
                key = f'{fname} {lname}'
                employees[key] = {
                    'dob': parts[2] if parts[2] != 'NULL' else None,
                    'marital_status': parts[3] if parts[3] != 'NULL' else None,
                    'gender': parts[4] if parts[4] != 'NULL' else None, # 1=Male, 2=Female
                    'nationality': parts[5] if parts[5] != 'NULL' else None,
                    'license_exp': parts[6] if len(parts) > 6 and parts[6] != 'NULL' else None
                }
except Exception as e:
    print(f'Error parsing DB result: {e}')

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'employees': employees,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 5. Cleanup permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="