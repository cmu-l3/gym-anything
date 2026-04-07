#!/bin/bash
echo "=== Exporting import_leads_csv results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/import_leads_final.png

# 2. Collect timestamps and counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_LEAD_COUNT=$(cat /tmp/initial_lead_count.txt 2>/dev/null || echo "0")
CURRENT_LEAD_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_leaddetails l INNER JOIN vtiger_crmentity e ON l.leadid = e.crmid WHERE e.deleted = 0" | tr -d '[:space:]')

# 3. Fetch recently created leads joining detail, address, and subdetail tables
vtiger_db_query "SELECT l.lastname, l.company, l.email, l.phone, a.city, s.leadsource, UNIX_TIMESTAMP(e.createdtime) FROM vtiger_leaddetails l INNER JOIN vtiger_crmentity e ON l.leadid = e.crmid LEFT JOIN vtiger_leadaddress a ON l.leadid = a.leadaddressid LEFT JOIN vtiger_leadsubdetails s ON l.leadid = s.leadsubscriptionid WHERE e.deleted = 0 AND e.setype = 'Leads' ORDER BY e.crmid DESC LIMIT 20" > /tmp/recent_leads.tsv

# 4. Use Python to robustly parse the TSV into JSON
python3 << 'EOF' > /tmp/recent_leads.json
import json

leads = []
try:
    with open('/tmp/recent_leads.tsv', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 7:
                leads.append({
                    'lastname': parts[0],
                    'company': parts[1],
                    'email': parts[2],
                    'phone': parts[3],
                    'city': parts[4],
                    'leadsource': parts[5],
                    'createdtime_ts': int(parts[6]) if parts[6].isdigit() else 0
                })
except Exception as e:
    print(json.dumps([]))
    exit(0)

print(json.dumps(leads))
EOF

# 5. Combine metadata and leads array into final result JSON
python3 << EOF > /tmp/import_leads_result.json
import json
try:
    with open('/tmp/recent_leads.json', 'r') as f:
        leads = json.load(f)
except:
    leads = []

result = {
    "task_start_time": $TASK_START,
    "initial_count": $INITIAL_LEAD_COUNT,
    "current_count": $CURRENT_LEAD_COUNT,
    "recent_leads": leads
}

with open('/tmp/import_leads_result.json', 'w') as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/import_leads_result.json

echo "Result saved to /tmp/import_leads_result.json"
cat /tmp/import_leads_result.json
echo "=== import_leads_csv export complete ==="