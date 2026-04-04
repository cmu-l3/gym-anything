#!/bin/bash
# Export result for "sla_compliance_problem_management" task

echo "=== Exporting SLA Compliance Problem Management Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

RESULT_FILE="/tmp/sla_compliance_problem_management_result.json"

take_screenshot "/tmp/sla_compliance_final.png" 2>/dev/null || true

# --- Bash: SQL queries for ticket status/owner (confirmed schema) ---
STATUS_1001=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
STATUS_1003=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1003;" 2>/dev/null | tr -d '[:space:]')
STATUS_1004=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')
OWNER_1001=$(sdp_db_exec "SELECT ownerId FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
OWNER_1003=$(sdp_db_exec "SELECT ownerId FROM workorderstates WHERE workorderid=1003;" 2>/dev/null | tr -d '[:space:]')
OWNER_1004=$(sdp_db_exec "SELECT ownerId FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

# Write SQL results to temp file (avoids heredoc interpolation issues)
cat > /tmp/sla_sql_raw.json << SQLEOF
{
  "status_1001": ${STATUS_1001:-2},
  "status_1003": ${STATUS_1003:-2},
  "status_1004": ${STATUS_1004:-2},
  "owner_1001": ${OWNER_1001:-0},
  "owner_1003": ${OWNER_1003:-0},
  "owner_1004": ${OWNER_1004:-0}
}
SQLEOF

# --- Python: REST API queries for technician name, problems, problem-request links ---
API_KEY=$(cat /tmp/sdp_api_key.txt 2>/dev/null | tr -d '[:space:]' || echo "")

python3 << 'PYEOF'
import json, ssl, urllib.request, urllib.parse, os, sys

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

API_KEY = open('/tmp/sdp_api_key.txt').read().strip() if os.path.exists('/tmp/sdp_api_key.txt') else ''
BASE = 'https://localhost:8080'

def api_get(path, params=None):
    url = f'{BASE}{path}'
    if params:
        url += '?input_data=' + urllib.parse.quote(json.dumps(params))
    req = urllib.request.Request(url, headers={'authtoken': API_KEY})
    try:
        resp = urllib.request.urlopen(req, context=ctx, timeout=30)
        return json.loads(resp.read())
    except Exception as e:
        return {'_error': str(e)}

# Load SQL results
with open('/tmp/sla_sql_raw.json') as f:
    result = json.load(f)

# Query technician names for each target ticket
for woid in [1001, 1003, 1004]:
    try:
        r = api_get(f'/api/v3/requests/{woid}')
        req_data = r.get('request', {})
        tech = req_data.get('technician') or {}
        result[f'technician_name_{woid}'] = tech.get('name', '') if tech else ''
        status = req_data.get('status') or {}
        result[f'status_name_{woid}'] = status.get('name', '') if status else ''
    except Exception as e:
        result[f'technician_name_{woid}'] = ''
        result[f'status_name_{woid}'] = ''

# Query all problems to find the target problem
problems_resp = api_get('/api/v3/problems', {'list_info': {'row_count': 50}})
problems = problems_resp.get('problems', [])

target_problem = None
for p in problems:
    title = p.get('title', '')
    if 'sla' in title.lower() and ('compliance' in title.lower() or 'failure' in title.lower() or 'breach' in title.lower()):
        target_problem = p
        break

result['problem_found'] = target_problem is not None
result['problem_title'] = target_problem.get('title', '') if target_problem else ''
result['problem_id'] = target_problem.get('id', '') if target_problem else ''

# Check problem priority
if target_problem:
    prio = target_problem.get('priority') or {}
    result['problem_priority'] = prio.get('name', '') if prio else ''
else:
    result['problem_priority'] = ''

# Check how many target tickets are linked to the problem
linked_ticket_count = 0
if target_problem:
    prob_id = target_problem.get('id', '')
    # Try API endpoint for problem details (may include related requests)
    prob_detail_resp = api_get(f'/api/v3/problems/{prob_id}')
    prob_detail = prob_detail_resp.get('problem', {})

    # Try different field names for linked requests
    linked_requests = (prob_detail.get('requests') or
                       prob_detail.get('related_requests') or
                       prob_detail.get('linked_requests') or [])

    linked_ids = {str(lr.get('id', '')) for lr in linked_requests if lr}
    linked_ticket_count = sum(1 for tid in ['1001', '1003', '1004'] if tid in linked_ids)

    result['problem_linked_request_ids'] = list(linked_ids)
    result['problem_linked_target_count'] = linked_ticket_count

    # Also try checking via the requests API - some SDP versions link from request side
    if linked_ticket_count == 0:
        for woid in [1001, 1003, 1004]:
            r = api_get(f'/api/v3/requests/{woid}')
            req_data = r.get('request', {})
            req_problems = req_data.get('problem') or req_data.get('problems') or []
            if isinstance(req_problems, dict):
                req_problems = [req_problems]
            for rp in req_problems:
                if str(rp.get('id', '')) == str(prob_id):
                    linked_ticket_count += 1
                    break
        result['problem_linked_target_count_v2'] = linked_ticket_count
else:
    result['problem_linked_request_ids'] = []
    result['problem_linked_target_count'] = 0

with open('/tmp/sla_compliance_problem_management_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Export complete')
print(json.dumps(result, indent=2))
PYEOF

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "WARNING: Python export script exited with code $EXIT_CODE"
fi

echo "=== Export Complete ==="
cat "$RESULT_FILE" 2>/dev/null || echo "Result file not found"
