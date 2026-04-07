#!/bin/bash
echo "=== Exporting status_label_taxonomy_restructuring results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Run a Python script inside the environment to securely fetch
# database data and write it directly to JSON without bash
# string escaping nightmares.
# ---------------------------------------------------------------
cat << 'PYEOF' > /tmp/export_db_data.py
import json
import subprocess

def run_sql(query):
    cmd = f"docker exec snipeit-db mysql -u snipeit -psnipeit_pass snipeit -N -e \"{query}\""
    try:
        return subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
    except Exception as e:
        return ""

result = {
    "labels": [],
    "assets": {}
}

# Fetch custom ITSM status labels
labels_out = run_sql("SELECT name, deployable, pending, archived FROM status_labels WHERE name LIKE 'ITSM - %'")
for line in labels_out.split('\n'):
    if line.strip():
        parts = line.split('\t')
        if len(parts) >= 4:
            result["labels"].append({
                "name": parts[0],
                "deployable": parts[1] == '1',
                "pending": parts[2] == '1',
                "archived": parts[3] == '1'
            })

# Fetch the status assignment of our injected assets
assets_out = run_sql("""
    SELECT a.asset_tag, sl.name 
    FROM assets a 
    LEFT JOIN status_labels sl ON a.status_id = sl.id 
    WHERE a.asset_tag LIKE 'ASSET-BR%' 
       OR a.asset_tag LIKE 'ASSET-TF%' 
       OR a.asset_tag LIKE 'ASSET-SH%' 
       OR a.asset_tag LIKE 'ASSET-DA%' 
       OR a.asset_tag LIKE 'ASSET-NS%'
""")
for line in assets_out.split('\n'):
    if line.strip():
        parts = line.split('\t')
        if len(parts) >= 2:
            result["assets"][parts[0]] = parts[1]
        elif len(parts) == 1:
            result["assets"][parts[0]] = "unknown"

# Save to disk
with open('/tmp/status_taxonomy_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/export_db_data.py

# Fix permissions
chmod 666 /tmp/status_taxonomy_result.json 2>/dev/null || sudo chmod 666 /tmp/status_taxonomy_result.json

echo "Result JSON written to /tmp/status_taxonomy_result.json"
cat /tmp/status_taxonomy_result.json
echo "=== Export complete ==="