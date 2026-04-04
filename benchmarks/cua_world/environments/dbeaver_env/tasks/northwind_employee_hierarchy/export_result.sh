#!/bin/bash
# Export script for northwind_employee_hierarchy

echo "=== Exporting Hierarchy Result ==="

source /workspace/scripts/task_utils.sh

# Paths
HIERARCHY_CSV="/home/ga/Documents/exports/hierarchy_report.csv"
MANAGER_CSV="/home/ga/Documents/exports/manager_summary.csv"
SQL_SCRIPT="/home/ga/Documents/scripts/hierarchy_analysis.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
take_screenshot /tmp/hierarchy_final.png

# 1. Check Connection 'NorthwindHR'
CONN_FOUND="false"
CONN_CORRECT_DB="false"

if [ -f "$DBEAVER_CONFIG" ]; then
    CONN_CHECK=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        data = json.load(f)
    found = False
    correct_db = False
    for k, v in data.get('connections', {}).items():
        if v.get('name') == 'NorthwindHR':
            found = True
            db_path = v.get('configuration', {}).get('database', '')
            if 'northwind.db' in db_path:
                correct_db = True
    print(f'{found}|{correct_db}')
except:
    print('False|False')
")
    CONN_FOUND=$(echo "$CONN_CHECK" | cut -d'|' -f1)
    CONN_CORRECT_DB=$(echo "$CONN_CHECK" | cut -d'|' -f2)
fi

# 2. Check Files Existence & Metadata
HIERARCHY_EXISTS="false"
MANAGER_EXISTS="false"
SQL_EXISTS="false"

if [ -f "$HIERARCHY_CSV" ] && [ -s "$HIERARCHY_CSV" ]; then HIERARCHY_EXISTS="true"; fi
if [ -f "$MANAGER_CSV" ] && [ -s "$MANAGER_CSV" ]; then MANAGER_EXISTS="true"; fi
if [ -f "$SQL_SCRIPT" ] && [ -s "$SQL_SCRIPT" ]; then SQL_EXISTS="true"; fi

# 3. Analyze CSV Content (Agent's Output)
# We will extract specific values from the agent's CSVs to compare with Ground Truth
AGENT_DATA_JSON=$(python3 << 'PYEOF'
import csv
import json
import sys

results = {
    "hierarchy_rows": 0,
    "hierarchy_cols": [],
    "top_level_manager": None,
    "top_level_level": -1,
    "manager_rows": 0,
    "manager_cols": [],
    "andrew_fuller_stats": {"direct": -1, "total": -1}
}

# Parse Hierarchy Report
h_csv = "/home/ga/Documents/exports/hierarchy_report.csv"
try:
    with open(h_csv, 'r') as f:
        reader = csv.DictReader(f)
        results["hierarchy_cols"] = [c.lower() for c in (reader.fieldnames or [])]
        rows = list(reader)
        results["hierarchy_rows"] = len(rows)
        
        # Find top level manager (Level 0)
        for row in rows:
            # Flexible key matching
            keys = {k.lower(): k for k in row.keys()}
            
            # Check for ManagementLevel
            level_key = keys.get('managementlevel')
            name_key = keys.get('fullname')
            
            if level_key and row[level_key]:
                try:
                    lvl = int(float(row[level_key]))
                    if lvl == 0:
                        results["top_level_level"] = 0
                        results["top_level_manager"] = row.get(name_key, "Unknown")
                except:
                    pass
except Exception as e:
    pass

# Parse Manager Summary
m_csv = "/home/ga/Documents/exports/manager_summary.csv"
try:
    with open(m_csv, 'r') as f:
        reader = csv.DictReader(f)
        results["manager_cols"] = [c.lower() for c in (reader.fieldnames or [])]
        
        for row in reader:
            results["manager_rows"] += 1
            # Look for Andrew Fuller stats
            keys = {k.lower(): k for k in row.keys()}
            name_key = keys.get('managername')
            direct_key = keys.get('directreportcount')
            total_key = keys.get('totalsubordinates')
            
            if name_key and 'andrew' in row[name_key].lower() and 'fuller' in row[name_key].lower():
                if direct_key: results["andrew_fuller_stats"]["direct"] = row[direct_key]
                if total_key: results["andrew_fuller_stats"]["total"] = row[total_key]

except Exception as e:
    pass

print(json.dumps(results))
PYEOF
)

# 4. Load Ground Truth
GT_JSON="{}"
if [ -f /tmp/northwind_hierarchy_gt.json ]; then
    GT_JSON=$(cat /tmp/northwind_hierarchy_gt.json)
fi

# 5. Timestamp Check
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)
FILES_CREATED_DURING_TASK="false"
if [ "$HIERARCHY_EXISTS" = "true" ]; then
    FILE_TIME=$(stat -c%Y "$HIERARCHY_CSV" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 6. Construct Final JSON
cat > /tmp/hierarchy_result.json << EOF
{
    "connection": {
        "found": $CONN_FOUND,
        "correct_db": $CONN_CORRECT_DB
    },
    "files": {
        "hierarchy_exists": $HIERARCHY_EXISTS,
        "manager_exists": $MANAGER_EXISTS,
        "sql_exists": $SQL_EXISTS,
        "created_during_task": $FILES_CREATED_DURING_TASK
    },
    "agent_data": $AGENT_DATA_JSON,
    "ground_truth": $GT_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
cp /tmp/hierarchy_result.json /tmp/safe_result.json
chmod 666 /tmp/safe_result.json
mv /tmp/safe_result.json /tmp/hierarchy_result.json

echo "Result exported to /tmp/hierarchy_result.json"