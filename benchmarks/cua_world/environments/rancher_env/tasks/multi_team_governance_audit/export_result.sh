#!/bin/bash
# Export script for multi_team_governance_audit task
#
# Collects Rancher governance state via kubectl CRDs and REST API:
# - Projects with resource quotas
# - Role templates with rules
# - Users
# - Cluster and project role template bindings

echo "=== Exporting multi_team_governance_audit result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# ── Collect state via kubectl CRDs ───────────────────────────────────────────
echo "Querying Rancher Management CRDs..."

python3 << 'PYEOF'
import json
import subprocess
import sys

def run_kubectl_get(resource, namespace=None):
    """Query Rancher CRDs via kubectl inside the rancher container."""
    cmd = ['docker', 'exec', 'rancher', 'kubectl', 'get', resource, '-o', 'json']
    if namespace:
        cmd.extend(['-n', namespace])
    else:
        cmd.append('-A')
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            print(f"kubectl error for {resource}: {result.stderr}", file=sys.stderr)
            return {'items': []}
    except Exception as e:
        print(f"Error getting {resource}: {e}", file=sys.stderr)
        return {'items': []}

def test_user_auth(username, password):
    """Test if a user can authenticate to Rancher."""
    try:
        cmd = [
            'curl', '-sk', '-X', 'POST',
            'https://localhost/v3-public/localProviders/local?action=login',
            '-H', 'Content-Type: application/json',
            '-d', json.dumps({
                'username': username,
                'password': password,
                'responseType': 'token'
            })
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        resp = json.loads(result.stdout)
        return bool(resp.get('token'))
    except Exception:
        return False

def main():
    # Collect all Rancher management CRDs
    data = {
        'projects': run_kubectl_get('projects.management.cattle.io', 'local'),
        'role_templates': run_kubectl_get('roletemplates.management.cattle.io'),
        'users': run_kubectl_get('users.management.cattle.io'),
        'cluster_bindings': run_kubectl_get('clusterroletemplatebindings.management.cattle.io', 'local'),
        'project_bindings': run_kubectl_get('projectroletemplatebindings.management.cattle.io'),
    }

    # Test user authentication
    data['auth_status'] = {
        'ops-lead': test_user_auth('ops-lead', 'OpsLead2024!#'),
        'alpha-lead': test_user_auth('alpha-lead', 'AlphaLead2024!#'),
        'alpha-dev': test_user_auth('alpha-dev', 'AlphaDev2024!#'),
    }

    with open('/tmp/multi_team_governance_audit_result.json', 'w') as f:
        json.dump(data, f, indent=2)

    print("Result JSON written successfully.")

if __name__ == '__main__':
    main()
PYEOF

# Set permissions
chmod 666 /tmp/multi_team_governance_audit_result.json 2>/dev/null || \
    sudo chmod 666 /tmp/multi_team_governance_audit_result.json 2>/dev/null || true

echo "Result saved to /tmp/multi_team_governance_audit_result.json"
echo "=== Export Complete ==="
