#!/bin/bash
# Export result for "technician_group_routing_configuration" task

echo "=== Exporting Technician Group Routing Configuration Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

RESULT_FILE="/tmp/technician_group_routing_configuration_result.json"

take_screenshot "/tmp/technician_group_routing_final.png" 2>/dev/null || true

# --- SQL queries for new user/group state ---
# Check if Maya Patel exists
MAYA_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM sduser WHERE LOWER(firstname)='maya' AND LOWER(lastname)='patel';" 2>/dev/null | tr -d '[:space:]')
MAYA_ID=$(sdp_db_exec "SELECT userid FROM sduser WHERE LOWER(firstname)='maya' AND LOWER(lastname)='patel' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Check if Carlos Rivera exists
CARLOS_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM sduser WHERE LOWER(firstname)='carlos' AND LOWER(lastname)='rivera';" 2>/dev/null | tr -d '[:space:]')
CARLOS_ID=$(sdp_db_exec "SELECT userid FROM sduser WHERE LOWER(firstname)='carlos' AND LOWER(lastname)='rivera' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Check for login names in aaalogin (case insensitive)
MPATEL_LOGIN=$(sdp_db_exec "SELECT COUNT(*) FROM aaalogin WHERE LOWER(name) LIKE '%mpatel%';" 2>/dev/null | tr -d '[:space:]')
CRIVERA_LOGIN=$(sdp_db_exec "SELECT COUNT(*) FROM aaalogin WHERE LOWER(name) LIKE '%crivera%';" 2>/dev/null | tr -d '[:space:]')

# Try multiple table names for technician groups
NETWORK_GROUP_SQL=$(sdp_db_exec "SELECT COUNT(*) FROM supportgroup WHERE LOWER(groupname) LIKE '%network operations%';" 2>/dev/null | tr -d '[:space:]')
HARDWARE_GROUP_SQL=$(sdp_db_exec "SELECT COUNT(*) FROM supportgroup WHERE LOWER(groupname) LIKE '%hardware support%';" 2>/dev/null | tr -d '[:space:]')

# Ticket group assignments
GROUP_1001=$(sdp_db_exec "SELECT groupid FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
GROUP_1004=$(sdp_db_exec "SELECT groupid FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

cat > /tmp/technician_group_sql_raw.json << SQLEOF
{
  "maya_count_sql": ${MAYA_COUNT:-0},
  "maya_id_sql": ${MAYA_ID:-0},
  "carlos_count_sql": ${CARLOS_COUNT:-0},
  "carlos_id_sql": ${CARLOS_ID:-0},
  "mpatel_login_count": ${MPATEL_LOGIN:-0},
  "crivera_login_count": ${CRIVERA_LOGIN:-0},
  "network_group_sql": ${NETWORK_GROUP_SQL:-0},
  "hardware_group_sql": ${HARDWARE_GROUP_SQL:-0},
  "group_1001_sql": ${GROUP_1001:-0},
  "group_1004_sql": ${GROUP_1004:-0}
}
SQLEOF

# --- Python: REST API queries for groups, technicians, ticket assignments ---
API_KEY=$(cat /tmp/sdp_api_key.txt 2>/dev/null | tr -d '[:space:]' || echo "")

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

with open('/tmp/technician_group_sql_raw.json') as f:
    result = json.load(f)

# Query groups via API (try /api/v3/groups or /api/v3/technician_groups)
network_group_found = False
hardware_group_found = False
network_group_id = None
hardware_group_id = None

for endpoint in ['/api/v3/groups', '/api/v3/technician_groups', '/api/v3/request_groups']:
    groups_resp = api_get(endpoint, {'list_info': {'row_count': 100}})
    groups = groups_resp.get('groups', []) or groups_resp.get('technician_groups', [])
    if groups:
        for g in groups:
            gname = g.get('name', '') or g.get('group_name', '') or g.get('groupname', '')
            if 'network operations' in gname.lower():
                network_group_found = True
                network_group_id = g.get('id', '')
            if 'hardware support' in gname.lower():
                hardware_group_found = True
                hardware_group_id = g.get('id', '')
        break

result['network_group_found_api'] = network_group_found
result['hardware_group_found_api'] = hardware_group_found

# Combine SQL and API checks
result['network_group_found'] = network_group_found or (result.get('network_group_sql', 0) > 0)
result['hardware_group_found'] = hardware_group_found or (result.get('hardware_group_sql', 0) > 0)

# Query technicians via API
maya_found_api = False
carlos_found_api = False

for endpoint in ['/api/v3/technicians', '/api/v3/users']:
    techs_resp = api_get(endpoint, {'list_info': {'row_count': 200}})
    techs = techs_resp.get('technicians', []) or techs_resp.get('users', [])
    if techs:
        for t in techs:
            full_name = t.get('full_name', '') or t.get('name', '')
            email = t.get('email_id', '') or t.get('email', '')
            if 'maya' in full_name.lower() and 'patel' in full_name.lower():
                maya_found_api = True
            if 'mpatel' in (email or '').lower():
                maya_found_api = True
            if 'carlos' in full_name.lower() and 'rivera' in full_name.lower():
                carlos_found_api = True
            if 'crivera' in (email or '').lower():
                carlos_found_api = True
        break

result['maya_patel_found_api'] = maya_found_api
result['carlos_rivera_found_api'] = carlos_found_api
result['maya_patel_found'] = maya_found_api or (result.get('maya_count_sql', 0) > 0)
result['carlos_rivera_found'] = carlos_found_api or (result.get('carlos_count_sql', 0) > 0)

# Check ticket group assignments via API
for woid in [1001, 1004]:
    r = api_get(f'/api/v3/requests/{woid}')
    req_data = r.get('request', {})
    group = req_data.get('group') or {}
    group_name = group.get('name', '') if group else ''
    result[f'ticket_{woid}_group_name'] = group_name

# Determine if correct groups assigned
ticket_1001_group = result.get('ticket_1001_group_name', '').lower()
ticket_1004_group = result.get('ticket_1004_group_name', '').lower()

result['ticket_1001_hardware_group'] = 'hardware' in ticket_1001_group
result['ticket_1004_network_group'] = 'network' in ticket_1004_group

with open('/tmp/technician_group_routing_configuration_result.json', 'w') as f:
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
