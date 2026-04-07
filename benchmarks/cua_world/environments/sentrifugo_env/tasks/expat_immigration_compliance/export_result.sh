#!/bin/bash
echo "=== Exporting expat_immigration_compliance result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot for trajectory / state evidence
take_screenshot /tmp/task_end_screenshot.png

# =====================================================================
# Export DB State to TSV
# =====================================================================
# We query the MySQL database directly for immigration records
# formatting the dates explicitly to YYYY-MM-DD
TSV_FILE="/tmp/imm_data.tsv"
QUERY="SELECT u.employeeId, i.documentno, DATE_FORMAT(i.issueddate, '%Y-%m-%d'), DATE_FORMAT(i.expirydate, '%Y-%m-%d') FROM main_empimmigration i JOIN main_users u ON i.user_id = u.id WHERE i.isactive=1;"

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "$QUERY" > "$TSV_FILE" 2>/dev/null || true

# =====================================================================
# Convert TSV to JSON via Python
# =====================================================================
cat << 'PYEOF' > /tmp/parse_tsv.py
import json
import sys
import os

task_start = sys.argv[1]
task_end = sys.argv[2]
tsv_file = "/tmp/imm_data.tsv"
out_json = "/tmp/result_temp.json"

records = []
if os.path.exists(tsv_file):
    with open(tsv_file, "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 4:
                records.append({
                    "employeeId": parts[0],
                    "documentno": parts[1],
                    "issueddate": parts[2] if parts[2] != "NULL" else "",
                    "expirydate": parts[3] if parts[3] != "NULL" else ""
                })

result = {
    "task_start": task_start,
    "task_end": task_end,
    "records": records
}

with open(out_json, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/parse_tsv.py "$TASK_START" "$TASK_END"

# Move JSON into place securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup
rm -f /tmp/result_temp.json "$TSV_FILE" /tmp/parse_tsv.py

echo "Export completed. Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="