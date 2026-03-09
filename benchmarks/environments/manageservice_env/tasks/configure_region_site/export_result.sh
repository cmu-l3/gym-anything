#!/bin/bash
echo "=== Exporting Configure Region and Site results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the results
# We use a Python script embedded here to handle the DB connection cleanly 
# and export structred JSON, avoiding fragile bash string parsing.
# The container has python3 and psycopg2 installed (per install_servicedesk.sh).

cat > /tmp/export_db_data.py << 'PYEOF'
import json
import subprocess
import sys

def run_query(sql):
    # Use the helper function from task_utils via bash wrapper or direct psql
    # Since we are inside python, we'll wrap the bash sdp_db_exec or just use raw psql command
    # Using raw psql command similar to task_utils.sh logic
    cmd = [
        "/opt/ManageEngine/ServiceDesk/pgsql/bin/psql",
        "-h", "127.0.0.1",
        "-p", "65432",
        "-U", "postgres",
        "-d", "servicedesk",
        "-t", "-A", # Tuple only, unaligned (easier to parse)
        "-F", "|",  # Pipe separator
        "-c", sql
    ]
    try:
        # Try running as postgres user
        result = subprocess.check_output(
            ["su", "-", "postgres", "-c", " ".join(cmd)], 
            stderr=subprocess.STDOUT
        )
        return result.decode('utf-8').strip()
    except subprocess.CalledProcessError:
        # Fallback for different permission setups
        try:
            result = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
            return result.decode('utf-8').strip()
        except:
            return ""

data = {
    "region_found": False,
    "region_id": None,
    "site_found": False,
    "site_details": {}
}

# 1. Check Region
region_sql = "SELECT regionid, regionname FROM regiondefinition WHERE regionname = 'Asia Pacific';"
region_res = run_query(region_sql)
if region_res:
    parts = region_res.split('|')
    if len(parts) >= 2:
        data["region_found"] = True
        data["region_id"] = parts[0].strip()

# 2. Check Site (and get linked Region ID)
# Note: Column names are guesses based on standard schemas, 
# using standard SQL wildcards or known common names.
# Often: siteid, sitename, regionid, description, address, city, zip, postalcode, country
# We will select specific columns likely to exist.
if data["region_found"]:
    site_sql = "SELECT regionid, sitename, description, address, city, postalcode, country FROM sitedefinition WHERE sitename = 'Singapore Hub';"
    site_res = run_query(site_sql)
    if site_res:
        parts = site_res.split('|')
        if len(parts) >= 7:
            data["site_found"] = True
            data["site_details"] = {
                "linked_region_id": parts[0].strip(),
                "name": parts[1].strip(),
                "description": parts[2].strip(),
                "address": parts[3].strip(),
                "city": parts[4].strip(),
                "zip": parts[5].strip(),
                "country": parts[6].strip()
            }

print(json.dumps(data))
PYEOF

# Run the python export script
# We need to run this as root or a user who can su to postgres
DB_RESULT_JSON=$(python3 /tmp/export_db_data.py)

# Combine with other metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_data": $DB_RESULT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="