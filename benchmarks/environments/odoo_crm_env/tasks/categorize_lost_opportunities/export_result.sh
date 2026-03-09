#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python script to fetch results
cat > /tmp/fetch_results.py << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

def fetch():
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USER, PASS, {})
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

        target_names = [
            "Enterprise License - Summit Financial",
            "Fleet Tracking System - BlueWave Logistics",
            "Cloud Storage Migration - Apex Healthcare"
        ]

        # Fetch records (active or inactive)
        ids = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search',
            [[['name', 'in', target_names], '|', ['active', '=', True], ['active', '=', False]]])
        
        records = models.execute_kw(DB, uid, PASS, 'crm.lead', 'read',
            [ids], {'fields': ['name', 'active', 'lost_reason_id']})

        # Structure for export
        results = {rec['name']: {
            'active': rec['active'],
            'lost_reason_name': rec['lost_reason_id'][1] if rec['lost_reason_id'] else None
        } for rec in records}

        print(json.dumps(results, indent=2))

    except Exception as e:
        print(json.dumps({"error": str(e)}))

fetch()
PYEOF

# Execute and save to temp file
python3 /tmp/fetch_results.py > /tmp/opp_data.json

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end": $(date +%s),
    "opportunity_data": $(cat /tmp/opp_data.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="