#!/bin/bash
echo "=== Exporting Dept Salary Analysis Results ==="
source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_end.png

SQL_SCRIPT="/home/ga/Documents/sql_scripts/dept_salary_analysis.sql"
CSV_EXPORT="/home/ga/Documents/exports/dept_salary_report.csv"

SQL_EXISTS=false
SQL_SIZE=0
SQL_MTIME=0

# Exporting and test-running user's SQL script if it exists
if [ -f "$SQL_SCRIPT" ]; then
    SQL_EXISTS=true
    SQL_SIZE=$(stat -c%s "$SQL_SCRIPT")
    SQL_MTIME=$(stat -c%Y "$SQL_SCRIPT")
    
    # Run the script using sqlcl to get a standardized CSV output
    echo "SET SQLFORMAT csv" > /tmp/run_test.sql
    echo "SET FEEDBACK OFF" >> /tmp/run_test.sql
    cat "$SQL_SCRIPT" >> /tmp/run_test.sql
    echo "" >> /tmp/run_test.sql
    echo "/" >> /tmp/run_test.sql
    echo "EXIT;" >> /tmp/run_test.sql
    
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    /usr/local/bin/sql -S hr/hr123@localhost:1521/XEPDB1 < /tmp/run_test.sql > /tmp/query_output.csv 2>&1
    
    cp "$SQL_SCRIPT" /tmp/user_script.sql
else
    echo "" > /tmp/query_output.csv
    echo "" > /tmp/user_script.sql
fi

CSV_EXISTS=false
CSV_SIZE=0
CSV_MTIME=0

# Exporting the user's manual CSV export
if [ -f "$CSV_EXPORT" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c%s "$CSV_EXPORT")
    CSV_MTIME=$(stat -c%Y "$CSV_EXPORT")
    cp "$CSV_EXPORT" /tmp/user_export.csv
else
    echo "" > /tmp/user_export.csv
fi

# Checking GUI signals (MRU modifications, Window interaction history)
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null)
if [ -z "$GUI_EVIDENCE" ]; then
    GUI_EVIDENCE='"gui_evidence": {}'
fi

# Dump execution metrics into JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $(cat /home/ga/.task_start_time 2>/dev/null || echo 0),
    "sql_exists": $SQL_EXISTS,
    "sql_size": $SQL_SIZE,
    "sql_mtime": $SQL_MTIME,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_mtime": $CSV_MTIME,
    "timestamp": "$(date -Iseconds)",
    ${GUI_EVIDENCE}
}
EOF

# Ensure the files are available for the host script (python verifier)
chmod 666 /tmp/task_result.json /tmp/query_output.csv /tmp/user_script.sql /tmp/user_export.csv 2>/dev/null || true
echo "Export complete."