#!/bin/bash
# Export script for statefulset_database_recovery task

echo "=== Exporting statefulset_database_recovery result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── C1: Check if any postgres-primary pods are Running ───────────────────────
PODS_RUNNING=$(docker exec rancher kubectl get pods -n data-platform \
    -l app=postgres-primary --field-selector status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')

PODS_TOTAL=$(docker exec rancher kubectl get pods -n data-platform \
    -l app=postgres-primary --no-headers 2>/dev/null | wc -l | tr -d ' ')

PODS_PHASES=$(docker exec rancher kubectl get pods -n data-platform \
    -l app=postgres-primary -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")

# ── C2: Check StorageClass used by PVCs ──────────────────────────────────────
PVC_JSON=$(docker exec rancher kubectl get pvc -n data-platform -o json 2>/dev/null || echo '{"items":[]}')

PVC_STORAGECLASS=$(echo "$PVC_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
classes = []
for item in items:
    sc = item.get('spec', {}).get('storageClassName', 'none')
    name = item.get('metadata', {}).get('name', '')
    classes.append({'name': name, 'storageClass': sc})
print(json.dumps(classes))
" 2>/dev/null || echo '[]')

# Check if any PVC uses 'premium-ssd' (the bad SC)
PVC_HAS_PREMIUM_SSD=$(echo "$PVC_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
for item in items:
    if item.get('spec', {}).get('storageClassName') == 'premium-ssd':
        print('true')
        sys.exit(0)
print('false')
" 2>/dev/null || echo "false")

# Get the StorageClass actually used by postgres-primary PVCs
POSTGRES_PVC_SC=$(echo "$PVC_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
for item in items:
    if 'postgres' in item.get('metadata', {}).get('name', ''):
        print(item.get('spec', {}).get('storageClassName', 'unknown'))
        sys.exit(0)
print('none')
" 2>/dev/null || echo "none")

# ── C3: Check if StatefulSet references correct Secret ───────────────────────
STS_JSON=$(docker exec rancher kubectl get statefulset postgres-primary \
    -n data-platform -o json 2>/dev/null || echo '{}')

SECRET_REFS=$(echo "$STS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
secrets = set()
for c in containers:
    for env in c.get('env', []):
        ref = env.get('valueFrom', {}).get('secretKeyRef', {})
        if ref:
            secrets.add(ref.get('name', ''))
print(json.dumps(list(secrets)))
" 2>/dev/null || echo '[]')

# Check if the correct secret 'postgres-credentials' exists
CORRECT_SECRET_EXISTS=$(docker exec rancher kubectl get secret postgres-credentials \
    -n data-platform --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Check if the wrong secret 'postgres-db-secret' is still referenced
WRONG_SECRET_STILL_REF=$(echo "$SECRET_REFS" | python3 -c "
import json, sys
refs = json.load(sys.stdin)
print('true' if 'postgres-db-secret' in refs else 'false')
" 2>/dev/null || echo "true")

CORRECT_SECRET_REFERENCED=$(echo "$SECRET_REFS" | python3 -c "
import json, sys
refs = json.load(sys.stdin)
print('true' if 'postgres-credentials' in refs else 'false')
" 2>/dev/null || echo "false")

# ── C4: Check memory request (should be <= 4Gi) ───────────────────────────────
MEMORY_REQUEST=$(echo "$STS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
for c in containers:
    mem = c.get('resources', {}).get('requests', {}).get('memory', 'unknown')
    print(mem)
    sys.exit(0)
print('unknown')
" 2>/dev/null || echo "unknown")

# Parse memory value to Gi for comparison
MEMORY_REQUEST_GI=$(python3 -c "
import re
val = '$MEMORY_REQUEST'
if val.endswith('Gi'):
    print(float(val[:-2]))
elif val.endswith('Mi'):
    print(float(val[:-2]) / 1024)
elif val.endswith('G'):
    print(float(val[:-1]))
elif val.endswith('M'):
    print(float(val[:-1]) / 1024)
else:
    print(999)
" 2>/dev/null || echo "999")

# ── Also check volume mount path ─────────────────────────────────────────────
VOLUME_MOUNT_PATH=$(echo "$STS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
for c in containers:
    for vm in c.get('volumeMounts', []):
        if 'postgres' in vm.get('name', ''):
            print(vm.get('mountPath', 'unknown'))
            sys.exit(0)
print('unknown')
" 2>/dev/null || echo "unknown")

# ── Write result JSON ─────────────────────────────────────────────────────────
export PODS_RUNNING PODS_TOTAL PODS_PHASES
export PVC_HAS_PREMIUM_SSD POSTGRES_PVC_SC PVC_STORAGECLASS
export SECRET_REFS CORRECT_SECRET_EXISTS WRONG_SECRET_STILL_REF CORRECT_SECRET_REFERENCED
export MEMORY_REQUEST MEMORY_REQUEST_GI VOLUME_MOUNT_PATH

python3 << 'PYEOF'
import json, os

def to_bool(s):
    return s.strip().lower() == 'true'

def parse_json(s, default):
    try:
        return json.loads(s)
    except Exception:
        return default

def to_int(s, default=0):
    try:
        return int(s.strip())
    except Exception:
        return default

def to_float(s, default=999.0):
    try:
        return float(s.strip())
    except Exception:
        return default

result = {
    "pods_running": to_int(os.environ.get("PODS_RUNNING", "0")),
    "pods_total": to_int(os.environ.get("PODS_TOTAL", "0")),
    "pods_phases": os.environ.get("PODS_PHASES", ""),
    "pvc_has_premium_ssd": to_bool(os.environ.get("PVC_HAS_PREMIUM_SSD", "false")),
    "postgres_pvc_storageclass": os.environ.get("POSTGRES_PVC_SC", "none"),
    "pvc_storageclass_details": parse_json(os.environ.get("PVC_STORAGECLASS", "[]"), []),
    "secret_refs": parse_json(os.environ.get("SECRET_REFS", "[]"), []),
    "correct_secret_exists": to_int(os.environ.get("CORRECT_SECRET_EXISTS", "0")) > 0,
    "wrong_secret_still_referenced": to_bool(os.environ.get("WRONG_SECRET_STILL_REF", "true")),
    "correct_secret_referenced": to_bool(os.environ.get("CORRECT_SECRET_REFERENCED", "false")),
    "memory_request": os.environ.get("MEMORY_REQUEST", "unknown"),
    "memory_request_gi": to_float(os.environ.get("MEMORY_REQUEST_GI", "999")),
    "volume_mount_path": os.environ.get("VOLUME_MOUNT_PATH", "unknown"),
}

with open('/tmp/statefulset_database_recovery_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/statefulset_database_recovery_result.json")
print(f"  pods_running: {result['pods_running']}")
print(f"  pvc_storageclass: {result['postgres_pvc_storageclass']}")
print(f"  correct_secret_referenced: {result['correct_secret_referenced']}")
print(f"  memory_request: {result['memory_request']} ({result['memory_request_gi']} Gi)")
print(f"  volume_mount_path: {result['volume_mount_path']}")
PYEOF

echo "=== Export complete ==="
