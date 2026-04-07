#!/bin/bash
# Export script for resource_governance_implementation task

echo "=== Exporting resource_governance_implementation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── fintech-prod ResourceQuota ────────────────────────────────────────────────
PROD_QUOTA_JSON=$(docker exec rancher kubectl get resourcequota -n fintech-prod \
    -o json 2>/dev/null || echo '{"items":[]}')

PROD_QUOTA_EXISTS=$(echo "$PROD_QUOTA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('items') else 'false')
" 2>/dev/null || echo "false")

PROD_QUOTA_DETAILS=$(echo "$PROD_QUOTA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
if not items:
    print(json.dumps({}))
    sys.exit(0)
quota = items[0]
hard = quota.get('spec', {}).get('hard', {})
print(json.dumps(hard))
" 2>/dev/null || echo '{}')

# ── fintech-staging ResourceQuota ────────────────────────────────────────────
STAGING_QUOTA_JSON=$(docker exec rancher kubectl get resourcequota -n fintech-staging \
    -o json 2>/dev/null || echo '{"items":[]}')

STAGING_QUOTA_EXISTS=$(echo "$STAGING_QUOTA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('items') else 'false')
" 2>/dev/null || echo "false")

STAGING_QUOTA_DETAILS=$(echo "$STAGING_QUOTA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
if not items:
    print(json.dumps({}))
    sys.exit(0)
quota = items[0]
hard = quota.get('spec', {}).get('hard', {})
print(json.dumps(hard))
" 2>/dev/null || echo '{}')

# ── fintech-prod LimitRange ───────────────────────────────────────────────────
PROD_LR_JSON=$(docker exec rancher kubectl get limitrange -n fintech-prod \
    -o json 2>/dev/null || echo '{"items":[]}')

PROD_LR_EXISTS=$(echo "$PROD_LR_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('items') else 'false')
" 2>/dev/null || echo "false")

PROD_LR_DETAILS=$(echo "$PROD_LR_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
if not items:
    print(json.dumps([]))
    sys.exit(0)
lr = items[0]
limits = lr.get('spec', {}).get('limits', [])
print(json.dumps(limits))
" 2>/dev/null || echo '[]')

# ── fintech-staging LimitRange ────────────────────────────────────────────────
STAGING_LR_JSON=$(docker exec rancher kubectl get limitrange -n fintech-staging \
    -o json 2>/dev/null || echo '{"items":[]}')

STAGING_LR_EXISTS=$(echo "$STAGING_LR_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('items') else 'false')
" 2>/dev/null || echo "false")

STAGING_LR_DETAILS=$(echo "$STAGING_LR_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
if not items:
    print(json.dumps([]))
    sys.exit(0)
lr = items[0]
limits = lr.get('spec', {}).get('limits', [])
print(json.dumps(limits))
" 2>/dev/null || echo '[]')

# ── fintech-dev LimitRange ────────────────────────────────────────────────────
DEV_LR_JSON=$(docker exec rancher kubectl get limitrange -n fintech-dev \
    -o json 2>/dev/null || echo '{"items":[]}')

DEV_LR_EXISTS=$(echo "$DEV_LR_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('items') else 'false')
" 2>/dev/null || echo "false")

DEV_LR_DETAILS=$(echo "$DEV_LR_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
if not items:
    print(json.dumps([]))
    sys.exit(0)
lr = items[0]
limits = lr.get('spec', {}).get('limits', [])
print(json.dumps(limits))
" 2>/dev/null || echo '[]')

# ── Write result JSON ─────────────────────────────────────────────────────────
export PROD_QUOTA_EXISTS PROD_QUOTA_DETAILS
export STAGING_QUOTA_EXISTS STAGING_QUOTA_DETAILS
export PROD_LR_EXISTS PROD_LR_DETAILS
export STAGING_LR_EXISTS STAGING_LR_DETAILS
export DEV_LR_EXISTS DEV_LR_DETAILS

python3 << 'PYEOF'
import json, os

def to_bool(s):
    return s.strip().lower() == 'true'

def parse_json(s, default):
    try:
        return json.loads(s)
    except Exception:
        return default

result = {
    "prod_quota_exists": to_bool(os.environ.get("PROD_QUOTA_EXISTS", "false")),
    "prod_quota_details": parse_json(os.environ.get("PROD_QUOTA_DETAILS", "{}"), {}),
    "staging_quota_exists": to_bool(os.environ.get("STAGING_QUOTA_EXISTS", "false")),
    "staging_quota_details": parse_json(os.environ.get("STAGING_QUOTA_DETAILS", "{}"), {}),
    "prod_lr_exists": to_bool(os.environ.get("PROD_LR_EXISTS", "false")),
    "prod_lr_details": parse_json(os.environ.get("PROD_LR_DETAILS", "[]"), []),
    "staging_lr_exists": to_bool(os.environ.get("STAGING_LR_EXISTS", "false")),
    "staging_lr_details": parse_json(os.environ.get("STAGING_LR_DETAILS", "[]"), []),
    "dev_lr_exists": to_bool(os.environ.get("DEV_LR_EXISTS", "false")),
    "dev_lr_details": parse_json(os.environ.get("DEV_LR_DETAILS", "[]"), []),
}

with open('/tmp/resource_governance_implementation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/resource_governance_implementation_result.json")
print(f"  prod_quota_exists: {result['prod_quota_exists']}")
print(f"  staging_quota_exists: {result['staging_quota_exists']}")
print(f"  prod_lr_exists: {result['prod_lr_exists']}")
print(f"  staging_lr_exists: {result['staging_lr_exists']}")
print(f"  dev_lr_exists: {result['dev_lr_exists']}")
PYEOF

echo "=== Export complete ==="
