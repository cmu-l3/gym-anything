#!/bin/bash
# Export script for cluster_rbac_audit_and_remediation
# Queries cluster RBAC state across dev-team, qa-team, and platform-ops namespaces

echo "=== Exporting cluster_rbac_audit_and_remediation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cluster_rbac_audit_and_remediation_end.png

TASK_START=$(cat /tmp/cluster_rbac_audit_and_remediation_start_ts 2>/dev/null || echo "0")

# ── Criterion 1: No CRB binding ci-runner (dev-team) to 'edit' ClusterRole ───
echo "Checking FINDING-A: ci-runner ClusterRoleBinding..."

CI_RUNNER_EDIT_CRB=$(docker exec rancher kubectl get clusterrolebinding -o json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for item in data.get('items', []):
        subs = item.get('subjects', [])
        role = item.get('roleRef', {}).get('name', '')
        crb_kind = item.get('roleRef', {}).get('kind', '')
        for s in subs:
            if (s.get('name') == 'ci-runner' and
                s.get('namespace') == 'dev-team' and
                role == 'edit' and
                crb_kind == 'ClusterRole'):
                print('present')
                sys.exit()
    print('removed')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null || echo "error")
[ -z "$CI_RUNNER_EDIT_CRB" ] && CI_RUNNER_EDIT_CRB="error"

# ── Criterion 2: qa-tester Role must NOT have wildcard verbs on pods ──────────
echo "Checking FINDING-B: qa-tester Role wildcard verbs..."

QA_TESTER_WILDCARD=$(docker exec rancher kubectl get role qa-tester -n qa-team \
    -o json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    rules = data.get('rules', [])
    for rule in rules:
        resources = rule.get('resources', [])
        verbs = rule.get('verbs', [])
        if 'pods' in resources and '*' in verbs:
            print('wildcard-present')
            sys.exit()
    print('wildcard-removed')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null || echo "not-found")
[ -z "$QA_TESTER_WILDCARD" ] && QA_TESTER_WILDCARD="not-found"

QA_TESTER_EXISTS=$(docker exec rancher kubectl get role qa-tester -n qa-team \
    --no-headers 2>/dev/null | grep -c "qa-tester" || echo "0")
[ -z "$QA_TESTER_EXISTS" ] && QA_TESTER_EXISTS=0

# ── Criterion 3: No CRB binding ops-agent (platform-ops) to cluster-admin ────
echo "Checking FINDING-C: ops-agent cluster-admin binding..."

OPS_AGENT_ADMIN_CRB=$(docker exec rancher kubectl get clusterrolebinding -o json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for item in data.get('items', []):
        subs = item.get('subjects', [])
        role = item.get('roleRef', {}).get('name', '')
        for s in subs:
            if (s.get('name') == 'ops-agent' and
                s.get('namespace') == 'platform-ops' and
                role == 'cluster-admin'):
                print('present')
                sys.exit()
    print('removed')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null || echo "error")
[ -z "$OPS_AGENT_ADMIN_CRB" ] && OPS_AGENT_ADMIN_CRB="error"

# ── Criterion 4: dev-team namespace has pod-security label ────────────────────
echo "Checking FINDING-D: dev-team namespace pod-security label..."

DEV_TEAM_POD_SECURITY=$(docker exec rancher kubectl get namespace dev-team \
    -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
[ -z "$DEV_TEAM_POD_SECURITY" ] && DEV_TEAM_POD_SECURITY="not-set"

# Also capture all labels for diagnostics
DEV_TEAM_LABELS=$(docker exec rancher kubectl get namespace dev-team \
    -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")

# ── Write result JSON ─────────────────────────────────────────────────────────
cat > /tmp/cluster_rbac_audit_and_remediation_result.json << EOF
{
  "task_start": $TASK_START,
  "namespaces": ["dev-team", "qa-team", "platform-ops"],
  "finding_a": {
    "ci_runner_edit_crb_status": "$CI_RUNNER_EDIT_CRB"
  },
  "finding_b": {
    "qa_tester_role_exists": $QA_TESTER_EXISTS,
    "wildcard_status": "$QA_TESTER_WILDCARD"
  },
  "finding_c": {
    "ops_agent_admin_crb_status": "$OPS_AGENT_ADMIN_CRB"
  },
  "finding_d": {
    "dev_team_pod_security_enforce": "$DEV_TEAM_POD_SECURITY"
  }
}
EOF

echo "Result JSON written."
echo "FINDING-A ci-runner edit CRB status: $CI_RUNNER_EDIT_CRB"
echo "FINDING-B qa-tester wildcard verbs: $QA_TESTER_WILDCARD"
echo "FINDING-C ops-agent cluster-admin CRB status: $OPS_AGENT_ADMIN_CRB"
echo "FINDING-D dev-team pod-security enforce label: $DEV_TEAM_POD_SECURITY"

echo "=== Export Complete ==="
