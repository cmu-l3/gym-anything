#!/bin/bash
# Setup script for northwind_employee_hierarchy task

set -e
echo "=== Setting up Northwind Employee Hierarchy Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/northwind.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean previous artifacts
rm -f "$EXPORT_DIR/hierarchy_report.csv"
rm -f "$EXPORT_DIR/manager_summary.csv"
rm -f "$SCRIPTS_DIR/hierarchy_analysis.sql"

# Ensure Northwind database exists and is populated
if [ ! -f "$DB_PATH" ] || [ "$(stat -c%s "$DB_PATH" 2>/dev/null || echo 0)" -lt 10000 ]; then
    echo "Downloading Northwind database..."
    wget -q --timeout=60 "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/main/Northwind_large.sql" \
        -O /tmp/northwind.sql 2>/dev/null || \
    wget -q --timeout=60 "https://raw.githubusercontent.com/jpwhite3/northwind-SQLite3/refs/heads/main/Northwind_large.sql" \
        -O /tmp/northwind.sql 2>/dev/null
    
    if [ -s /tmp/northwind.sql ]; then
        sqlite3 "$DB_PATH" < /tmp/northwind.sql
        rm -f /tmp/northwind.sql
        chown ga:ga "$DB_PATH"
        echo "Database created."
    else
        echo "ERROR: Failed to download Northwind SQL."
        exit 1
    fi
fi

# Verify Employees table exists and has recursive structure
echo "Verifying database structure..."
TABLE_CHECK=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='Employees';" 2>/dev/null || echo 0)
if [ "$TABLE_CHECK" -eq 0 ]; then
    echo "ERROR: Employees table not found in $DB_PATH"
    exit 1
fi

# Pre-calculate Ground Truth values using SQLite for verification later
# We calculate:
# 1. Total employees
# 2. Top level manager name
# 3. Andrew Fuller's total subordinates (Recursive)
echo "Computing ground truth..."

python3 << 'PYEOF'
import sqlite3
import json

conn = sqlite3.connect("/home/ga/Documents/databases/northwind.db")
c = conn.cursor()

# 1. Basic Stats
emp_count = c.execute("SELECT Count(*) FROM Employees").fetchone()[0]

# 2. Top Manager (ReportsTo is NULL)
top_mgr = c.execute("SELECT FirstName || ' ' || LastName FROM Employees WHERE ReportsTo IS NULL").fetchone()
top_mgr_name = top_mgr[0] if top_mgr else "None"

# 3. Recursive check for Total Subordinates (Andrew Fuller is usually ID 2)
# We'll compute a map of ID -> TotalSubs
# Simple recursive DFS in python since dataset is small (9 rows)
employees = c.execute("SELECT EmployeeID, ReportsTo, FirstName || ' ' || LastName FROM Employees").fetchall()
emp_map = {row[0]: {'reports_to': row[1], 'name': row[2], 'subs': []} for row in employees}

# Build tree
for eid, data in emp_map.items():
    if data['reports_to'] and data['reports_to'] in emp_map:
        emp_map[data['reports_to']]['subs'].append(eid)

def count_subs(eid):
    count = 0
    for sub_id in emp_map[eid]['subs']:
        count += 1 + count_subs(sub_id)
    return count

def get_depth(eid, current_depth):
    max_d = current_depth
    for sub_id in emp_map[eid]['subs']:
        max_d = max(max_d, get_depth(sub_id, current_depth + 1))
    return max_d

gt_data = {
    "employee_count": emp_count,
    "top_manager_name": top_mgr_name,
    "managers": {}
}

for eid, data in emp_map.items():
    direct_reports = len(data['subs'])
    if direct_reports > 0:
        total_subs = count_subs(eid)
        max_depth_below = get_depth(eid, 0)
        gt_data["managers"][data['name']] = {
            "direct_reports": direct_reports,
            "total_subordinates": total_subs,
            "max_depth_below": max_depth_below
        }

with open('/tmp/northwind_hierarchy_gt.json', 'w') as f:
    json.dump(gt_data, f, indent=2)

print("Ground truth computed.")
PYEOF

# Record start time
date +%s > /tmp/task_start_time

# Record initial DBeaver connections
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$CONFIG_FILE" ]; then
    grep -c '"id"' "$CONFIG_FILE" > /tmp/initial_conn_count || echo "0" > /tmp/initial_conn_count
else
    echo "0" > /tmp/initial_conn_count
fi

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi
focus_dbeaver

# Take initial screenshot
take_screenshot /tmp/hierarchy_initial.png

echo "=== Setup Complete ==="