#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Beverage Unit Hierarchy Result ==="

# 1. Take final screenshot
FINAL_SCREENSHOT="/tmp/openlca_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT"

# 2. Check if OpenLCA is running
OPENLCA_RUNNING="false"
if is_openlca_running; then
    OPENLCA_RUNNING="true"
fi

# 3. Query the Derby database to verify the data structure
# We need to find the active database first.
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_MTIME=0

# Find the most recently modified database directory
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    # Get modification time of the log file or seg0 directory
    MTIME=$(stat -c %Y "$db_path/service.properties" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$MAX_MTIME" ]; then
        MAX_MTIME="$MTIME"
        ACTIVE_DB="$db_path"
    fi
done

echo "Active Database: $ACTIVE_DB"

# Initialize result variables
GROUP_FOUND="false"
GROUP_ID=""
UNITS_JSON="[]"
FLOW_FOUND="false"
PROCESS_FOUND="false"

if [ -n "$ACTIVE_DB" ]; then
    # Close OpenLCA to unlock Derby DB for querying
    echo "Closing OpenLCA to query database..."
    close_openlca
    sleep 3

    # A. Check for Unit Group
    echo "Querying TBL_UNIT_GROUPS..."
    # We use a broader query in case of casing differences, handle filtering in Python later if needed
    # but Derby LIKE is case-sensitive usually. We'll try exact match first or broad dump.
    GROUPS_DUMP=$(derby_query "$ACTIVE_DB" "SELECT ID, NAME FROM TBL_UNIT_GROUPS WHERE NAME LIKE '%Beverage%' OR NAME LIKE '%Packaging%';")
    echo "$GROUPS_DUMP" > /tmp/derby_groups.txt
    
    # B. Check for Flow
    echo "Querying TBL_FLOWS..."
    FLOWS_DUMP=$(derby_query "$ACTIVE_DB" "SELECT NAME, REF_UNIT_GROUP_ID FROM TBL_FLOWS WHERE NAME LIKE '%Cola%';")
    echo "$FLOWS_DUMP" > /tmp/derby_flows.txt

    # C. Check for Process
    echo "Querying TBL_PROCESSES..."
    PROCESS_DUMP=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_PROCESSES WHERE NAME LIKE '%Cola%' OR NAME LIKE '%Pallet%';")
    echo "$PROCESS_DUMP" > /tmp/derby_processes.txt

    # D. If Group found, get Units
    # We use python to parse the ID from the dump and then query units
    GROUP_ID=$(python3 -c "
import sys, re
content = open('/tmp/derby_groups.txt').read()
match = re.search(r'^\s*(\d+)\s*\|\s*Beverage\s*Packaging', content, re.MULTILINE | re.IGNORECASE)
if match:
    print(match.group(1))
" 2>/dev/null || echo "")

    if [ -n "$GROUP_ID" ]; then
        GROUP_FOUND="true"
        echo "Found Group ID: $GROUP_ID"
        
        echo "Querying TBL_UNITS for Group $GROUP_ID..."
        UNITS_DUMP=$(derby_query "$ACTIVE_DB" "SELECT NAME, CONVERSION_FACTOR FROM TBL_UNITS WHERE UNIT_GROUP_ID = $GROUP_ID;")
        echo "$UNITS_DUMP" > /tmp/derby_units.txt
    else
        echo "Unit Group not found in DB dump."
    fi
fi

# 4. Parse everything into a clean JSON using Python
# This runs inside the container
python3 << 'EOF'
import json
import re
import os
import sys

def parse_derby_table(filepath):
    """Parses ij output into list of dicts/tuples."""
    if not os.path.exists(filepath):
        return []
    rows = []
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    # Derby output usually looks like:
    # ID         |NAME
    # ------------------
    # 123        |SomeName
    
    start_parsing = False
    for line in lines:
        if line.strip().startswith('---'):
            start_parsing = True
            continue
        if start_parsing:
            if line.strip() == "" or 'rows selected' in line:
                continue
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 2:
                rows.append(parts)
    return rows

result = {
    "group_found": False,
    "group_id": None,
    "units": [],
    "flow_found": False,
    "flow_linked_correctly": False,
    "process_found": False,
    "screenshot_path": "/tmp/openlca_final_screenshot.png",
    "openlca_was_running": os.environ.get("OPENLCA_RUNNING") == "true"
}

# Check Group
groups = parse_derby_table('/tmp/derby_groups.txt')
for row in groups:
    # row[0] is ID, row[1] is NAME
    if len(row) >= 2 and 'Beverage Packaging' in row[1]:
        result["group_found"] = True
        result["group_id"] = row[0]
        break

# Check Units
if result["group_found"]:
    units = parse_derby_table('/tmp/derby_units.txt')
    for row in units:
        # row[0] is NAME, row[1] is FACTOR
        if len(row) >= 2:
            try:
                name = row[0]
                factor = float(row[1])
                result["units"].append({"name": name, "factor": factor})
            except ValueError:
                pass

# Check Flow
flows = parse_derby_table('/tmp/derby_flows.txt')
for row in flows:
    # row[0] is NAME, row[1] is REF_UNIT_GROUP_ID
    if len(row) >= 2 and 'Cola 500mL' in row[0]:
        result["flow_found"] = True
        if result["group_id"] and row[1] == result["group_id"]:
            result["flow_linked_correctly"] = True
        break

# Check Process
processes = parse_derby_table('/tmp/derby_processes.txt')
for row in processes:
    if len(row) >= 1 and 'Cola Palletizing' in row[0]:
        result["process_found"] = True
        break

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Python export logic complete.")
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json