#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper for SQL to JSON
sql_json() {
    query="$1"
    # Use docker exec to run query and format as JSON
    # We use a python one-liner inside the container or host to parse TSV from MySQL
    # Simpler: Just dump TSV and let python verifier parse it
    orangehrm_db_query "$query"
}

# 1. Export Pay Grades and Currencies
echo "Exporting Pay Grade configurations..."
# Structure: PayGradeName | CurrencyID | MinSalary | MaxSalary
PAY_GRADE_DATA=$(sql_json "
SELECT pg.name, pgc.currency_id, pgc.min_salary, pgc.max_salary 
FROM ohrm_pay_grade pg 
JOIN ohrm_pay_grade_currency pgc ON pg.id = pgc.pay_grade_id 
WHERE pg.name IN ('Software Engineer', 'Data Scientist');
")

# 2. Export Employee Salary Records
echo "Exporting Employee Salaries..."
# Structure: FirstName | LastName | Component | Currency | Amount
EMP_SALARY_DATA=$(sql_json "
SELECT e.emp_firstname, e.emp_lastname, s.salary_component, s.currency_id, s.ebsal_basic_salary
FROM hs_hr_employee e
JOIN hs_hr_emp_basicsalary s ON e.emp_number = s.emp_number
WHERE (e.emp_firstname='Michael' AND e.emp_lastname='Chen') 
   OR (e.emp_firstname='David' AND e.emp_lastname='Morris');
")

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pay_grade_data": $(echo "$PAY_GRADE_DATA" | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t"))'),
    "emp_salary_data": $(echo "$EMP_SALARY_DATA" | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t"))')
}
EOF

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Move Result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json