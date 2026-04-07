#!/bin/bash
echo "=== Exporting rbac_row_level_security result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_end_screenshot.png

# Use Python to interact with the Splunk REST API and perform behavioral verification
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def run_splunk_search(user, password, query):
    cmd = [
        'curl', '-sk', '-u', f'{user}:{password}',
        'https://localhost:8089/services/search/jobs',
        '-d', f'search=search {query} | stats count',
        '-d', 'exec_mode=oneshot',
        '-d', 'output_mode=json'
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    try:
        data = json.loads(res.stdout)
        results = data.get('results', [])
        if results:
            return int(results[0].get('count', 0))
    except:
        pass
    return -1

# 1. Baseline checks (anti-gaming: prove the data wasn't just deleted)
admin_failed = run_splunk_search("admin", "SplunkAdmin1!", 'index=security_logs "Failed"')
admin_accepted = run_splunk_search("admin", "SplunkAdmin1!", 'index=security_logs "Accepted"')

# 2. Behavioral test checks (proving the RBAC rules work)
auditor_failed = run_splunk_search("auditor_joe", "Auditor123!", 'index=security_logs "Failed"')
auditor_web = run_splunk_search("auditor_joe", "Auditor123!", 'index=web_logs')
auditor_accepted = run_splunk_search("auditor_joe", "Auditor123!", 'index=security_logs "Accepted"')

# 3. Structural checks (fallback in case behavioral search fails due to 'require password change' UI traps)
cmd_role = ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/services/authorization/roles/compliance_auditor?output_mode=json']
res_role = subprocess.run(cmd_role, capture_output=True, text=True)
role_data = {}
try:
    role_json = json.loads(res_role.stdout)
    if role_json.get('entry'):
        role_data = role_json['entry'][0]['content']
except:
    pass

cmd_user = ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/services/authentication/users/auditor_joe?output_mode=json']
res_user = subprocess.run(cmd_user, capture_output=True, text=True)
user_data = {}
try:
    user_json = json.loads(res_user.stdout)
    if user_json.get('entry'):
        user_data = user_json['entry'][0]['content']
except:
    pass

output = {
    "admin_failed_count": admin_failed,
    "admin_accepted_count": admin_accepted,
    "auditor_failed_count": auditor_failed,
    "auditor_web_count": auditor_web,
    "auditor_accepted_count": auditor_accepted,
    "role_exists": bool(role_data),
    "role_srchFilter": role_data.get('srchFilter', ''),
    "role_srchIndexesAllowed": role_data.get('srchIndexesAllowed', []),
    "user_exists": bool(user_data),
    "user_roles": user_data.get('roles', [])
}
print(json.dumps(output))
PYEOF
)

# Store results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/rbac_result.json
echo "Result saved to /tmp/rbac_result.json"
cat /tmp/rbac_result.json
echo "=== Export complete ==="