#!/bin/bash
# Export result for "change_request_full_lifecycle" task

echo "=== Exporting Change Request Full Lifecycle Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

RESULT_FILE="/tmp/change_request_full_lifecycle_result.json"

take_screenshot "/tmp/change_request_full_lifecycle_final.png" 2>/dev/null || true

# --- SQL: Try multiple table names for changes (SDP version dependent) ---
CHANGE_COUNT_MAIN=$(sdp_db_exec "SELECT COUNT(*) FROM changemanagement WHERE LOWER(title) LIKE '%campus network%' OR LOWER(title) LIKE '%switch replacement%';" 2>/dev/null | tr -d '[:space:]')
CHANGE_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM changedetails WHERE LOWER(title) LIKE '%campus network%' OR LOWER(title) LIKE '%switch replacement%';" 2>/dev/null | tr -d '[:space:]')
CHANGE_COUNT_ALT2=$(sdp_db_exec "SELECT COUNT(*) FROM globalchange WHERE LOWER(title) LIKE '%campus network%' OR LOWER(title) LIKE '%switch replacement%';" 2>/dev/null | tr -d '[:space:]')

# Get change ID and status for target change (first matching)
CHANGE_ID_MAIN=$(sdp_db_exec "SELECT changeid FROM changemanagement WHERE LOWER(title) LIKE '%campus network%' OR LOWER(title) LIKE '%switch replacement%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
CHANGE_STATUS_MAIN=$(sdp_db_exec "SELECT statusid FROM changemanagement WHERE LOWER(title) LIKE '%campus network%' OR LOWER(title) LIKE '%switch replacement%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Check for change tasks (changetask or change_task table)
TASK_COUNT_MAIN=$(sdp_db_exec "SELECT COUNT(*) FROM changetask WHERE changeid='${CHANGE_ID_MAIN:-0}';" 2>/dev/null | tr -d '[:space:]')
TASK_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM changeactivity WHERE changeid='${CHANGE_ID_MAIN:-0}';" 2>/dev/null | tr -d '[:space:]')

# Check for linked incident (changerequestlink or similar)
LINK_COUNT_MAIN=$(sdp_db_exec "SELECT COUNT(*) FROM changerequestlink WHERE changeid='${CHANGE_ID_MAIN:-0}' AND workorderid=1004;" 2>/dev/null | tr -d '[:space:]')
LINK_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM changeincidentlink WHERE changeid='${CHANGE_ID_MAIN:-0}' AND workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

cat > /tmp/change_sql_raw.json << SQLEOF
{
  "change_count_main": ${CHANGE_COUNT_MAIN:-0},
  "change_count_alt": ${CHANGE_COUNT_ALT:-0},
  "change_count_alt2": ${CHANGE_COUNT_ALT2:-0},
  "change_id_sql": "${CHANGE_ID_MAIN:-}",
  "change_status_sql": ${CHANGE_STATUS_MAIN:-0},
  "change_task_count_main": ${TASK_COUNT_MAIN:-0},
  "change_task_count_alt": ${TASK_COUNT_ALT:-0},
  "link_to_1004_main": ${LINK_COUNT_MAIN:-0},
  "link_to_1004_alt": ${LINK_COUNT_ALT:-0}
}
SQLEOF

# --- Python: REST API queries ---
python3 << 'PYEOF'
import json, ssl, urllib.request, urllib.parse, os

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

with open('/tmp/change_sql_raw.json') as f:
    result = json.load(f)

# Query changes via API
changes_resp = api_get('/api/v3/changes', {'list_info': {'row_count': 50}})
changes = changes_resp.get('changes', [])

target_change = None
for c in changes:
    title = c.get('title', '')
    if ('campus network' in title.lower() or
        'switch replacement' in title.lower() or
        'core switch' in title.lower()):
        target_change = c
        break

result['change_found_api'] = target_change is not None
result['change_title_api'] = target_change.get('title', '') if target_change else ''
result['change_id_api'] = str(target_change.get('id', '')) if target_change else ''

if target_change:
    change_id = target_change.get('id', '')
    # Check change type
    change_type = target_change.get('change_type') or {}
    result['change_type_name'] = change_type.get('name', '') if change_type else ''

    # Check status
    status = target_change.get('status') or {}
    result['change_status_name'] = status.get('name', '') if status else ''

    # Check for rollout/backout plan
    reason = target_change.get('reason_for_change', '') or ''
    rollout = target_change.get('rollout_plan', '') or ''
    backout = target_change.get('backout_plan', '') or ''
    result['has_reason'] = len(reason.strip()) > 20
    result['has_rollout_plan'] = len(rollout.strip()) > 20
    result['has_backout_plan'] = len(backout.strip()) > 20

    # Check change tasks
    tasks_resp = api_get(f'/api/v3/changes/{change_id}/tasks',
                          {'list_info': {'row_count': 20}})
    tasks = (tasks_resp.get('tasks', []) or
             tasks_resp.get('change_tasks', []) or
             tasks_resp.get('changetasks', []))
    result['change_task_count_api'] = len(tasks)

    # Check linked incidents
    linked_reqs_resp = api_get(f'/api/v3/changes/{change_id}/linked_requests',
                                {'list_info': {'row_count': 20}})
    linked_reqs = (linked_reqs_resp.get('linked_requests', []) or
                   linked_reqs_resp.get('requests', []) or
                   linked_reqs_resp.get('related_requests', []))
    linked_ids = [str(lr.get('id', '')) for lr in linked_reqs]
    result['linked_request_ids_api'] = linked_ids
    result['vpn_ticket_linked_api'] = '1004' in linked_ids

    # Also check from request side
    req_resp = api_get('/api/v3/requests/1004')
    req_data = req_resp.get('request', {})
    req_changes = req_data.get('change') or req_data.get('changes') or []
    if isinstance(req_changes, dict):
        req_changes = [req_changes]
    result['vpn_linked_from_request_side'] = any(
        str(rc.get('id', '')) == str(change_id) for rc in req_changes
    )
else:
    result['change_type_name'] = ''
    result['change_status_name'] = ''
    result['has_reason'] = False
    result['has_rollout_plan'] = False
    result['has_backout_plan'] = False
    result['change_task_count_api'] = 0
    result['linked_request_ids_api'] = []
    result['vpn_ticket_linked_api'] = False
    result['vpn_linked_from_request_side'] = False

# Combine SQL and API results
result['change_found'] = result.get('change_found_api', False) or (
    result.get('change_count_main', 0) + result.get('change_count_alt', 0) + result.get('change_count_alt2', 0)
) > 0

result['change_task_count'] = max(
    result.get('change_task_count_api', 0),
    result.get('change_task_count_main', 0),
    result.get('change_task_count_alt', 0)
)

result['vpn_ticket_linked'] = (
    result.get('vpn_ticket_linked_api', False) or
    result.get('vpn_linked_from_request_side', False) or
    result.get('link_to_1004_main', 0) > 0 or
    result.get('link_to_1004_alt', 0) > 0
)

# Status check: "Requested" in SDP means CAB review submitted
status_name = result.get('change_status_name', '').lower()
result['change_status_is_requested'] = ('request' in status_name or 'submit' in status_name)

with open('/tmp/change_request_full_lifecycle_result.json', 'w') as f:
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
