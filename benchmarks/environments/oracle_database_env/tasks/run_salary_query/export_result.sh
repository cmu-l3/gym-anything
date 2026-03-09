#!/bin/bash
# Export script for Run Salary Query task
# Validates results by comparing with independent database query

echo "=== Exporting Run Salary Query Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ============================================================
# CRITICAL: Verify database is accessible before export
# ============================================================

echo "Verifying database connectivity..."
DB_CHECK=$(sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT 'DB_OK' FROM DUAL;
EXIT;
SQLEOF" 2>&1)

if ! echo "$DB_CHECK" | grep -q "DB_OK"; then
    echo "ERROR: Database connection failed during export!"
    echo "Output: $DB_CHECK"

    # Create error result JSON
    cat > /tmp/salary_query_result.json << EOJSON
{
    "result_file_exists": false,
    "result_file_path": "/tmp/query_results.txt",
    "file_line_count": 0,
    "ground_truth": {
        "expected_count": 0,
        "employees": []
    },
    "validation": {
        "matched_employee_count": 0,
        "matched_employee_ids": "",
        "has_proper_structure": false
    },
    "error": "Database connection failed during export",
    "db_error": "$(echo "$DB_CHECK" | grep "ORA-" | head -1 | sed 's/"/\\"/g')",
    "file_content_preview": "",
    "export_timestamp": "$(date -Iseconds)"
}
EOJSON
    chmod 644 /tmp/salary_query_result.json 2>/dev/null || true
    echo "Error result JSON saved"
    cat /tmp/salary_query_result.json
    exit 1
fi
echo "Database connection: OK"

# Check if result file exists
RESULT_FILE="/tmp/query_results.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_LINE_COUNT=0

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE" 2>/dev/null | head -100)
    FILE_LINE_COUNT=$(wc -l < "$RESULT_FILE" 2>/dev/null || echo "0")
    echo "Result file found: $RESULT_FILE ($FILE_LINE_COUNT lines)"
else
    echo "Result file NOT found: $RESULT_FILE"
fi

# CRITICAL: Run independent database query to get ground truth
echo ""
echo "=== Running independent database validation ==="
GROUND_TRUTH=$(oracle_query "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT employee_id || '|' || first_name || '|' || last_name || '|' || salary || '|' || job_id
FROM employees
WHERE department_id = 60 AND salary > 5000
ORDER BY employee_id;" "hr" 2>/dev/null | grep -v '^$' | grep '|')

# Parse ground truth into structured format
EXPECTED_EMPLOYEES=""
EXPECTED_COUNT=0
while IFS='|' read -r emp_id fname lname sal job; do
    emp_id=$(echo "$emp_id" | tr -d ' ')
    fname=$(echo "$fname" | tr -d ' ')
    lname=$(echo "$lname" | tr -d ' ')
    sal=$(echo "$sal" | tr -d ' ')
    job=$(echo "$job" | tr -d ' ')

    if [ -n "$emp_id" ]; then
        EXPECTED_EMPLOYEES="${EXPECTED_EMPLOYEES}{\"employee_id\": $emp_id, \"first_name\": \"$fname\", \"last_name\": \"$lname\", \"salary\": $sal, \"job_id\": \"$job\"},"
        EXPECTED_COUNT=$((EXPECTED_COUNT + 1))
    fi
done <<< "$GROUND_TRUTH"

# Remove trailing comma
EXPECTED_EMPLOYEES=$(echo "$EXPECTED_EMPLOYEES" | sed 's/,$//')
echo "Ground truth: Found $EXPECTED_COUNT employees matching criteria"

# Check which expected employees appear in the result file
FOUND_EMPLOYEES=0
MATCHED_EMPLOYEES=""
if [ "$FILE_EXISTS" = "true" ] && [ -n "$FILE_CONTENT" ]; then
    # Parse each expected employee and check if they appear in the file
    while IFS='|' read -r emp_id fname lname sal job; do
        emp_id=$(echo "$emp_id" | tr -d ' ')
        fname=$(echo "$fname" | tr -d ' ')
        lname=$(echo "$lname" | tr -d ' ')

        if [ -n "$emp_id" ]; then
            # CRITICAL: Check if employee_id AND name appear on the SAME LINE
            # This prevents cheating by listing IDs and names separately
            # We check each line of the file for both emp_id AND (fname OR lname)
            EMPLOYEE_MATCHED="false"
            while IFS= read -r line; do
                # Check if this line contains the employee_id with word boundary
                # Use -w to prevent matching "103" in "1030" or "2103"
                if echo "$line" | grep -qw "$emp_id"; then
                    # Now check if the SAME line also contains first_name or last_name
                    if echo "$line" | grep -qi "$fname" || echo "$line" | grep -qi "$lname"; then
                        EMPLOYEE_MATCHED="true"
                        break
                    fi
                fi
            done <<< "$FILE_CONTENT"

            if [ "$EMPLOYEE_MATCHED" = "true" ]; then
                FOUND_EMPLOYEES=$((FOUND_EMPLOYEES + 1))
                MATCHED_EMPLOYEES="${MATCHED_EMPLOYEES}$emp_id,"
            fi
        fi
    done <<< "$GROUND_TRUTH"
fi

echo "Found $FOUND_EMPLOYEES of $EXPECTED_COUNT expected employees in result file"

# Check file structure (has headers and data rows)
HAS_PROPER_STRUCTURE="false"
if [ "$FILE_LINE_COUNT" -gt 1 ]; then
    # First line should look like a header (no numeric ID at start)
    FIRST_LINE=$(head -1 "$RESULT_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if echo "$FIRST_LINE" | grep -qi "employee.*\|first.*\|last.*\|salary\|job"; then
        # Data lines should start with employee ID
        DATA_LINES=$(tail -n +2 "$RESULT_FILE" 2>/dev/null | grep -cE '^\s*[0-9]+' || echo "0")
        if [ "$DATA_LINES" -ge "$EXPECTED_COUNT" ]; then
            HAS_PROPER_STRUCTURE="true"
        fi
    fi
fi

# Escape content for JSON (limit size)
FILE_CONTENT_ESCAPED=$(echo "$FILE_CONTENT" | head -30 | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' '\\n' | sed 's/\\n$//' | cut -c1-2000)

# Create result JSON
cat > /tmp/salary_query_result.json << EOJSON
{
    "result_file_exists": $FILE_EXISTS,
    "result_file_path": "$RESULT_FILE",
    "file_line_count": $FILE_LINE_COUNT,
    "ground_truth": {
        "expected_count": $EXPECTED_COUNT,
        "employees": [$EXPECTED_EMPLOYEES]
    },
    "validation": {
        "matched_employee_count": $FOUND_EMPLOYEES,
        "matched_employee_ids": "$(echo $MATCHED_EMPLOYEES | sed 's/,$//')",
        "has_proper_structure": $HAS_PROPER_STRUCTURE
    },
    "file_content_preview": "$FILE_CONTENT_ESCAPED",
    "export_timestamp": "$(date -Iseconds)"
}
EOJSON

chmod 644 /tmp/salary_query_result.json 2>/dev/null || true

echo ""
echo "Result JSON saved to /tmp/salary_query_result.json"
cat /tmp/salary_query_result.json

echo ""
echo "=== Export Complete ==="
