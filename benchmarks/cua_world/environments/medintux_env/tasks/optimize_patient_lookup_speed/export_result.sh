#!/bin/bash
echo "=== Exporting optimize_patient_lookup_speed result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROOF_FILE="/home/ga/optimization_proof.txt"

# 1. Check if proof file exists
if [ -f "$PROOF_FILE" ]; then
    PROOF_EXISTS="true"
    # Read content, escape double quotes for JSON
    PROOF_CONTENT=$(cat "$PROOF_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
else
    PROOF_EXISTS="false"
    PROOF_CONTENT=""
fi

# 2. Check Database State (Run SQL queries locally and export results)
# We need to verify if the index exists and what it is named
DB_RESULT_JSON=$(mysql -u root DrTuxTest -N -e "
SELECT JSON_OBJECT(
    'index_count', COUNT(*),
    'index_names', GROUP_CONCAT(INDEX_NAME),
    'is_unique', MAX(NON_UNIQUE) = 0
)
FROM information_schema.STATISTICS 
WHERE TABLE_SCHEMA = 'DrTuxTest' 
  AND TABLE_NAME = 'fchpat' 
  AND COLUMN_NAME = 'FchPat_NumSS';
" 2>/dev/null || echo "{}")

# 3. Verify Optimization Effect (Run EXPLAIN)
# We run the explain ourselves to see if the engine picks it up
EXPLAIN_JSON=$(mysql -u root DrTuxTest -N -e "
EXPLAIN FORMAT=JSON SELECT * FROM fchpat WHERE FchPat_NumSS = '1750578999999';
" 2>/dev/null || echo "{}")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Construct final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "proof_file_exists": $PROOF_EXISTS,
    "proof_file_content": "$PROOF_CONTENT",
    "db_state": $DB_RESULT_JSON,
    "explain_output": $EXPLAIN_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="