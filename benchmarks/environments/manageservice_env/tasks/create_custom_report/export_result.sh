#!/bin/bash
echo "=== Exporting Create Custom Report Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query Database for Report Configuration
# We need to fetch the report details to verify columns, grouping, and filters.
# This requires joining a few tables.
# Schema assumptions based on SDP:
# - ReportConfiguration (report_id, report_name, module_name/id)
# - ReportColumns (report_id, column_name)
# - ReportFilters (report_id, column_name, filter_value, criteria)
# - ReportGrouping (report_id, column_name)

echo "Querying database for report details..."

# Python script to fetch and format DB results as JSON
cat > /tmp/fetch_report_data.py << PYEOF
import json
import subprocess
import sys

def run_sql(sql):
    cmd = ["su", "-", "postgres", "-c", f"{psql_bin} -h 127.0.0.1 -p {db_port} -d servicedesk -t -A -c \"{sql}\""]
    # Fallback to direct execution if su fails (e.g. running as root/ga)
    try:
        # Construct psql command for sdp_db_exec style execution
        # We'll rely on the fact that we can run psql if we are root or have pass
        full_cmd = f"/opt/ManageEngine/ServiceDesk/pgsql/bin/psql -h 127.0.0.1 -p 65432 -U postgres -d servicedesk -t -A -F '|||' -c \"{sql}\""
        # Try running with PGPASSWORD set to empty (trusted) or standard defaults
        result = subprocess.check_output(full_cmd, shell=True, stderr=subprocess.STDOUT)
        return result.decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        return ""

# Find the report created by the agent
# We look for reports created after task start or just matching the name pattern
sql_find_report = "SELECT reportid, reportname, description FROM reportconfiguration WHERE reportname ILIKE '%Weekly Open Requests%' ORDER BY reportid DESC LIMIT 1;"
report_info_raw = run_sql(sql_find_report)

result = {
    "report_found": False,
    "report_name": "",
    "columns": [],
    "filters": [],
    "grouping": []
}

if report_info_raw:
    parts = report_info_raw.split('|||')
    if len(parts) >= 2:
        r_id = parts[0]
        r_name = parts[1]
        result["report_found"] = True
        result["report_name"] = r_name
        
        # Get Columns - schema varies, trying standard pattern
        # Usually stored in a table mapping reportid to columns
        sql_cols = f"SELECT columnname FROM reportlist WHERE reportid = {r_id};"
        # If reportlist isn't the table, try reportselectcols or similar
        # For robustness, we'll try a generic query assuming we might not know exact schema
        # but in this env we control, we assume standard SDP schema. 
        # Actually, simpler: SDP stores report definitions often in XML or specific tables.
        # Let's try 'ReportList' or 'ReportSelectCols'
        cols_raw = run_sql(sql_cols)
        if not cols_raw:
             # Try alternate table name
             cols_raw = run_sql(f"SELECT name FROM column_details WHERE reportid = {r_id}")
        
        if cols_raw:
            result["columns"] = [c.strip() for c in cols_raw.split('\n') if c.strip()]

        # Get Filters
        # Often in ReportFilter table
        sql_filters = f"SELECT criteria, value FROM reportfilter WHERE reportid = {r_id};"
        filters_raw = run_sql(sql_filters)
        if filters_raw:
             for line in filters_raw.split('\n'):
                 if line.strip():
                     result["filters"].append(line.strip())

        # Get Grouping
        # Often in ReportGroupBy
        sql_group = f"SELECT columnname FROM reportgroupby WHERE reportid = {r_id};"
        group_raw = run_sql(sql_group)
        if group_raw:
            result["grouping"] = [g.strip() for g in group_raw.split('\n') if g.strip()]

print(json.dumps(result, indent=2))
PYEOF

# Execute the python script
# Need to set vars for the script
export psql_bin="/opt/ManageEngine/ServiceDesk/pgsql/bin/psql"
export db_port="65432"

python3 /tmp/fetch_report_data.py > /tmp/report_db_data.json 2>/dev/null

# Anti-gaming check: Count reports
CURRENT_REPORT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM reportconfiguration;" "servicedesk")
INITIAL_REPORT_COUNT=$(cat /tmp/initial_report_count.txt 2>/dev/null || echo "0")
REPORTS_CREATED=$((CURRENT_REPORT_COUNT - INITIAL_REPORT_COUNT))

# Final JSON construction
cat > /tmp/final_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_report_count": $INITIAL_REPORT_COUNT,
    "current_report_count": $CURRENT_REPORT_COUNT,
    "reports_created_count": $REPORTS_CREATED,
    "db_data": $(cat /tmp/report_db_data.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv /tmp/final_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="