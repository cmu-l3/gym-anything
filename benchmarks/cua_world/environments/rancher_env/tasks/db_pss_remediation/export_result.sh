#!/bin/bash
echo "=== Exporting db_pss_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Fetch deployment and pod state
DEPLOY_JSON=$(docker exec rancher kubectl get deployment secure-db -n finance -o json 2>/dev/null || echo '{}')
PODS_JSON=$(docker exec rancher kubectl get pods -n finance -l app=secure-db -o json 2>/dev/null || echo '{"items":[]}')

# Determine if at least one pod is running and ready
POD_READY=$(echo "$PODS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
for pod in items:
    if pod.get('status', {}).get('phase') == 'Running':
        conditions = pod.get('status', {}).get('conditions', [])
        for cond in conditions:
            if cond.get('type') == 'Ready' and cond.get('status') == 'True':
                print('true')
                sys.exit(0)
print('false')
" 2>/dev/null || echo "false")

POD_PHASE=$(echo "$PODS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
if items:
    print(items[0].get('status', {}).get('phase', 'unknown'))
else:
    print('missing')
" 2>/dev/null || echo "missing")

# Check security constraints on the deployment container
READ_ONLY_ROOT=$(echo "$DEPLOY_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
for c in containers:
    if c.get('name') == 'postgres':
        ro = c.get('securityContext', {}).get('readOnlyRootFilesystem', False)
        print('true' if ro else 'false')
        sys.exit(0)
print('false')
" 2>/dev/null || echo "false")

RUN_AS_USER=$(echo "$DEPLOY_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
pod_sec = data.get('spec', {}).get('template', {}).get('spec', {}).get('securityContext', {})
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
pod_uid = pod_sec.get('runAsUser', None)
for c in containers:
    if c.get('name') == 'postgres':
        c_uid = c.get('securityContext', {}).get('runAsUser', None)
        uid = c_uid if c_uid is not None else pod_uid
        print(uid if uid is not None else 'null')
        sys.exit(0)
print('null')
" 2>/dev/null || echo "null")

TLS_CONFIGURED=$(echo "$DEPLOY_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
volumes = data.get('spec', {}).get('template', {}).get('spec', {}).get('volumes', [])

secret_mounted = False
for v in volumes:
    if v.get('secret', {}).get('secretName') == 'db-tls-certs':
        secret_mounted = True

for c in containers:
    if c.get('name') == 'postgres':
        args = c.get('args', [])
        ssl_on = 'ssl=on' in args or any('ssl=on' in str(a) for a in args)
        if secret_mounted and ssl_on:
            print('true')
            sys.exit(0)
print('false')
" 2>/dev/null || echo "false")

cat > /tmp/task_result.json << EOF
{
  "pod_ready": $POD_READY,
  "pod_phase": "$POD_PHASE",
  "read_only_root": $READ_ONLY_ROOT,
  "run_as_user": $RUN_AS_USER,
  "tls_configured": $TLS_CONFIGURED
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="