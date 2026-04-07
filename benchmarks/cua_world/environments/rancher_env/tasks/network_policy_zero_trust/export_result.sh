#!/bin/bash
# Export script for network_policy_zero_trust task

echo "=== Exporting network_policy_zero_trust result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── Collect all NetworkPolicies in online-banking ─────────────────────────────
NP_JSON=$(docker exec rancher kubectl get networkpolicy -n online-banking \
    -o json 2>/dev/null || echo '{"items":[]}')

# Parse all NetworkPolicies into structured data
python3 - << 'PYEOF'
import json, subprocess, sys

# Re-fetch with fresh data
result = subprocess.run(
    ['docker', 'exec', 'rancher', 'kubectl', 'get', 'networkpolicy',
     '-n', 'online-banking', '-o', 'json'],
    capture_output=True, text=True
)
try:
    data = json.loads(result.stdout)
except Exception:
    data = {'items': []}

items = data.get('items', [])
policies = {}

for item in items:
    name = item.get('metadata', {}).get('name', '')
    spec = item.get('spec', {})
    policies[name] = {
        'pod_selector': spec.get('podSelector', {}),
        'policy_types': spec.get('policyTypes', []),
        'ingress': spec.get('ingress', []),
        'egress': spec.get('egress', []),
    }

# ── C1: Default deny-all policy ─────────────────────────────────────────────
# Criteria: podSelector={} (empty, matches all), policyTypes includes both Ingress and Egress
# AND the ingress/egress rules arrays are empty (deny all)
default_deny = policies.get('default-deny-all', {})
c1_exists = 'default-deny-all' in policies
c1_pod_selector_empty = (default_deny.get('pod_selector', {}).get('matchLabels') is None and
                          default_deny.get('pod_selector', {}).get('matchExpressions') is None) if c1_exists else False
c1_has_ingress_type = 'Ingress' in default_deny.get('policy_types', []) if c1_exists else False
c1_has_egress_type = 'Egress' in default_deny.get('policy_types', []) if c1_exists else False
c1_ingress_empty = len(default_deny.get('ingress', [])) == 0 if c1_exists else False
c1_egress_empty = len(default_deny.get('egress', [])) == 0 if c1_exists else False

# ── C2: Frontend policy ──────────────────────────────────────────────────────
# Must allow ingress from ingress-nginx namespace and egress to api-gateway:8080
frontend_policy = None
for name, pol in policies.items():
    sel = pol.get('pod_selector', {}).get('matchLabels', {})
    if sel.get('app') == 'frontend-app':
        frontend_policy = pol
        break

c2_exists = frontend_policy is not None

# Check if ingress allows from ingress-nginx namespace
c2_ingress_from_ingress_ns = False
c2_egress_to_api_gateway = False

if c2_exists:
    for ingress_rule in frontend_policy.get('ingress', []):
        for frm in ingress_rule.get('from', []):
            ns_sel = frm.get('namespaceSelector', {})
            labels = ns_sel.get('matchLabels', {})
            if (labels.get('kubernetes.io/metadata.name') == 'ingress-nginx' or
                    labels.get('name') == 'ingress-nginx' or
                    labels.get('kubernetes.io/metadata.name') == 'ingress-nginx'):
                c2_ingress_from_ingress_ns = True

    for egress_rule in frontend_policy.get('egress', []):
        for to in egress_rule.get('to', []):
            pod_sel = to.get('podSelector', {})
            if pod_sel.get('matchLabels', {}).get('app') == 'api-gateway':
                c2_egress_to_api_gateway = True

# ── C3: API gateway policy ───────────────────────────────────────────────────
api_policy = None
for name, pol in policies.items():
    sel = pol.get('pod_selector', {}).get('matchLabels', {})
    if sel.get('app') == 'api-gateway':
        api_policy = pol
        break

c3_exists = api_policy is not None
c3_ingress_from_frontend = False
c3_egress_to_auth = False
c3_egress_to_account = False

if c3_exists:
    for ingress_rule in api_policy.get('ingress', []):
        for frm in ingress_rule.get('from', []):
            if frm.get('podSelector', {}).get('matchLabels', {}).get('app') == 'frontend-app':
                c3_ingress_from_frontend = True

    for egress_rule in api_policy.get('egress', []):
        for to in egress_rule.get('to', []):
            pod_sel = to.get('podSelector', {}).get('matchLabels', {})
            if pod_sel.get('app') == 'auth-service':
                c3_egress_to_auth = True
            if pod_sel.get('app') == 'account-service':
                c3_egress_to_account = True

# ── C4: Database policy ──────────────────────────────────────────────────────
db_policy = None
for name, pol in policies.items():
    sel = pol.get('pod_selector', {}).get('matchLabels', {})
    if sel.get('app') == 'account-db':
        db_policy = pol
        break

c4_exists = db_policy is not None
c4_ingress_from_account_service_only = False
c4_ingress_sources_count = 0
c4_port_5432 = False

if c4_exists:
    for ingress_rule in db_policy.get('ingress', []):
        for frm in ingress_rule.get('from', []):
            c4_ingress_sources_count += 1
            if frm.get('podSelector', {}).get('matchLabels', {}).get('app') == 'account-service':
                c4_ingress_from_account_service_only = True
        for port_spec in ingress_rule.get('ports', []):
            if port_spec.get('port') == 5432:
                c4_port_5432 = True

output = {
    'total_policies': len(policies),
    'policy_names': list(policies.keys()),
    'c1_exists': c1_exists,
    'c1_pod_selector_empty': c1_pod_selector_empty,
    'c1_has_ingress_type': c1_has_ingress_type,
    'c1_has_egress_type': c1_has_egress_type,
    'c1_ingress_empty': c1_ingress_empty,
    'c1_egress_empty': c1_egress_empty,
    'c2_exists': c2_exists,
    'c2_ingress_from_ingress_ns': c2_ingress_from_ingress_ns,
    'c2_egress_to_api_gateway': c2_egress_to_api_gateway,
    'c3_exists': c3_exists,
    'c3_ingress_from_frontend': c3_ingress_from_frontend,
    'c3_egress_to_auth': c3_egress_to_auth,
    'c3_egress_to_account': c3_egress_to_account,
    'c4_exists': c4_exists,
    'c4_ingress_from_account_service_only': c4_ingress_from_account_service_only,
    'c4_ingress_sources_count': c4_ingress_sources_count,
    'c4_port_5432': c4_port_5432,
}

with open('/tmp/network_policy_zero_trust_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print("Result written to /tmp/network_policy_zero_trust_result.json")
print(f"  Total policies: {len(policies)}")
print(f"  C1 default-deny-all: exists={c1_exists}")
print(f"  C2 frontend: exists={c2_exists}, from_ingress={c2_ingress_from_ingress_ns}, to_api={c2_egress_to_api_gateway}")
print(f"  C3 api-gateway: exists={c3_exists}, from_frontend={c3_ingress_from_frontend}")
print(f"  C4 account-db: exists={c4_exists}, from_account_svc={c4_ingress_from_account_service_only}, port_5432={c4_port_5432}")
PYEOF

echo "=== Export complete ==="
