#!/bin/bash
# Export script for rbac_least_privilege_audit task

echo "=== Exporting rbac_least_privilege_audit result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── Check Violation 1: dev-all-access ClusterRoleBinding ─────────────────────
DEV_CRB_ROLEREF=$(docker exec rancher kubectl get clusterrolebinding dev-all-access \
    -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")

DEV_CRB_SUBJECT_KIND=$(docker exec rancher kubectl get clusterrolebinding dev-all-access \
    -o jsonpath='{.subjects[0].kind}' 2>/dev/null || echo "deleted")

DEV_CRB_SUBJECT_NS=$(docker exec rancher kubectl get clusterrolebinding dev-all-access \
    -o jsonpath='{.subjects[0].namespace}' 2>/dev/null || echo "deleted")

# ── Check Violation 2: wildcard-staging-role Role ────────────────────────────
WILDCARD_ROLE_EXISTS=$(docker exec rancher kubectl get role wildcard-staging-role \
    -n staging --no-headers 2>/dev/null | wc -l | tr -d ' ')

WILDCARD_ROLE_VERBS=$(docker exec rancher kubectl get role wildcard-staging-role \
    -n staging -o jsonpath='{.rules[0].verbs}' 2>/dev/null || echo "deleted")

WILDCARD_ROLE_RESOURCES=$(docker exec rancher kubectl get role wildcard-staging-role \
    -n staging -o jsonpath='{.rules[0].resources}' 2>/dev/null || echo "deleted")

WILDCARD_ROLE_APIGROUPS=$(docker exec rancher kubectl get role wildcard-staging-role \
    -n staging -o jsonpath='{.rules[0].apiGroups}' 2>/dev/null || echo "deleted")

# Check if the wildcard rolebinding still exists (binding ci-runner to wildcard role)
WILDCARD_RB_ROLEREF=$(docker exec rancher kubectl get rolebinding wildcard-staging-binding \
    -n staging -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")

# ── Check Violation 3: monitoring-cluster-admin ClusterRoleBinding ────────────
MON_CRB_ROLEREF=$(docker exec rancher kubectl get clusterrolebinding monitoring-cluster-admin \
    -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")

MON_CRB_SUBJECT_SA=$(docker exec rancher kubectl get clusterrolebinding monitoring-cluster-admin \
    -o jsonpath='{.subjects[0].name}' 2>/dev/null || echo "deleted")

MON_CRB_SUBJECT_NS=$(docker exec rancher kubectl get clusterrolebinding monitoring-cluster-admin \
    -o jsonpath='{.subjects[0].namespace}' 2>/dev/null || echo "deleted")

# ── Check Violation 4: ci-elevated-access RoleBinding in staging ─────────────
CI_RB_ROLEREF=$(docker exec rancher kubectl get rolebinding ci-elevated-access \
    -n staging -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")

CI_RB_SUBJECT_SA=$(docker exec rancher kubectl get rolebinding ci-elevated-access \
    -n staging -o jsonpath='{.subjects[0].name}' 2>/dev/null || echo "deleted")

# ── Also check if scoped replacement roles were created ──────────────────────
# Look for any non-cluster-admin ClusterRoleBindings for dev-automation
DEV_REPLACEMENT_CRB=$(docker exec rancher kubectl get clusterrolebinding \
    -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
replacements = []
for item in items:
    subjects = item.get('subjects', [])
    role_ref = item.get('roleRef', {})
    for subj in subjects:
        if subj.get('name') == 'dev-automation' and subj.get('namespace') == 'development':
            if role_ref.get('name') != 'cluster-admin':
                replacements.append(role_ref.get('name', ''))
print(','.join(replacements) if replacements else 'none')
" 2>/dev/null || echo "none")

# Check if dev-automation has scoped RoleBinding in development namespace
DEV_SCOPED_RB=$(docker exec rancher kubectl get rolebinding \
    -n development -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
for item in items:
    subjects = item.get('subjects', [])
    for subj in subjects:
        if subj.get('name') == 'dev-automation':
            print(item.get('roleRef', {}).get('name', ''))
            sys.exit(0)
print('none')
" 2>/dev/null || echo "none")

# Check if metrics-collector has scoped RoleBinding in monitoring namespace
MON_SCOPED_RB=$(docker exec rancher kubectl get rolebinding \
    -n monitoring -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data.get('items', [])
for item in items:
    subjects = item.get('subjects', [])
    for subj in subjects:
        if subj.get('name') == 'metrics-collector':
            print(item.get('roleRef', {}).get('name', ''))
            sys.exit(0)
print('none')
" 2>/dev/null || echo "none")

# ── Write result JSON ─────────────────────────────────────────────────────────
export DEV_CRB_ROLEREF DEV_CRB_SUBJECT_KIND DEV_CRB_SUBJECT_NS
export WILDCARD_ROLE_EXISTS WILDCARD_ROLE_VERBS WILDCARD_ROLE_RESOURCES WILDCARD_ROLE_APIGROUPS
export WILDCARD_RB_ROLEREF
export MON_CRB_ROLEREF MON_CRB_SUBJECT_SA MON_CRB_SUBJECT_NS
export CI_RB_ROLEREF CI_RB_SUBJECT_SA
export DEV_REPLACEMENT_CRB DEV_SCOPED_RB MON_SCOPED_RB

python3 << 'PYEOF'
import json, os

result = {
    "dev_crb_roleref": os.environ.get("DEV_CRB_ROLEREF", "unknown"),
    "dev_crb_subject_kind": os.environ.get("DEV_CRB_SUBJECT_KIND", "unknown"),
    "dev_crb_subject_ns": os.environ.get("DEV_CRB_SUBJECT_NS", "unknown"),
    "wildcard_role_exists": os.environ.get("WILDCARD_ROLE_EXISTS", "1"),
    "wildcard_role_verbs": os.environ.get("WILDCARD_ROLE_VERBS", "deleted"),
    "wildcard_role_resources": os.environ.get("WILDCARD_ROLE_RESOURCES", "deleted"),
    "wildcard_role_apigroups": os.environ.get("WILDCARD_ROLE_APIGROUPS", "deleted"),
    "wildcard_rb_roleref": os.environ.get("WILDCARD_RB_ROLEREF", "deleted"),
    "mon_crb_roleref": os.environ.get("MON_CRB_ROLEREF", "unknown"),
    "mon_crb_subject_sa": os.environ.get("MON_CRB_SUBJECT_SA", "unknown"),
    "mon_crb_subject_ns": os.environ.get("MON_CRB_SUBJECT_NS", "unknown"),
    "ci_rb_roleref": os.environ.get("CI_RB_ROLEREF", "unknown"),
    "ci_rb_subject_sa": os.environ.get("CI_RB_SUBJECT_SA", "unknown"),
    "dev_replacement_crb": os.environ.get("DEV_REPLACEMENT_CRB", "none"),
    "dev_scoped_rb": os.environ.get("DEV_SCOPED_RB", "none"),
    "mon_scoped_rb": os.environ.get("MON_SCOPED_RB", "none"),
}

with open('/tmp/rbac_least_privilege_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/rbac_least_privilege_audit_result.json")
print(f"  dev_crb_roleref: {result['dev_crb_roleref']}")
print(f"  wildcard_role_exists: {result['wildcard_role_exists']}")
print(f"  wildcard_role_verbs: {result['wildcard_role_verbs']}")
print(f"  mon_crb_roleref: {result['mon_crb_roleref']}")
print(f"  ci_rb_roleref: {result['ci_rb_roleref']}")
PYEOF

echo "=== Export complete ==="
