#!/bin/bash
echo "=== Exporting Configure Lab Procedure Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Retrieve Initial State info
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper to query DB and output JSON object or null
# We select relevant fields: id, parent, name, procedure_code, standard_code
# We filter by the created names to check structure

echo "Querying database for created records..."

# 1. Look for the Group
GROUP_JSON=$(librehealth_query "SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, 'name', name, 'code', procedure_code) FROM procedure_type WHERE name LIKE '%In-House Lab%' AND procedure_type_id > $INITIAL_MAX_ID LIMIT 1" 2>/dev/null)

# 2. Look for the Order
ORDER_JSON=$(librehealth_query "SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, 'name', name, 'code', procedure_code, 'standard_code', standard_code) FROM procedure_type WHERE name LIKE '%Comprehensive Metabolic Panel%' AND procedure_type_id > $INITIAL_MAX_ID LIMIT 1" 2>/dev/null)

# 3. Look for the Results
# We search for them individually to verify specific attributes
RES_GLU_JSON=$(librehealth_query "SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, 'name', name, 'code', procedure_code) FROM procedure_type WHERE name LIKE '%Glucose%' AND procedure_code='GLU' AND procedure_type_id > $INITIAL_MAX_ID LIMIT 1" 2>/dev/null)
RES_CRE_JSON=$(librehealth_query "SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, 'name', name, 'code', procedure_code) FROM procedure_type WHERE name LIKE '%Creatinine%' AND procedure_code='CREAT' AND procedure_type_id > $INITIAL_MAX_ID LIMIT 1" 2>/dev/null)
RES_NA_JSON=$(librehealth_query "SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, 'name', name, 'code', procedure_code) FROM procedure_type WHERE name LIKE '%Sodium%' AND procedure_code='NA' AND procedure_type_id > $INITIAL_MAX_ID LIMIT 1" 2>/dev/null)

# Construct final JSON
# Use jq if available, otherwise manual string construction. 
# Since jq is installed in the environment (librehealth_ehr_env), we use it for safety.

cat > /tmp/db_export.json << EOF
{
  "group": ${GROUP_JSON:-null},
  "order": ${ORDER_JSON:-null},
  "results": {
    "glucose": ${RES_GLU_JSON:-null},
    "creatinine": ${RES_CRE_JSON:-null},
    "sodium": ${RES_NA_JSON:-null}
  },
  "initial_max_id": $INITIAL_MAX_ID,
  "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv /tmp/db_export.json /tmp/task_result.json

echo "Export complete. content of /tmp/task_result.json:"
cat /tmp/task_result.json