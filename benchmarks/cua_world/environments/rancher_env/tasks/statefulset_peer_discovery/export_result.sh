#!/bin/bash
# Export script for statefulset_peer_discovery task

echo "=== Exporting statefulset_peer_discovery result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# ── Collect Service and StatefulSet configurations ───────────────────────────
SVC_JSON=$(docker exec rancher kubectl get svc cache-discovery -n data-grid -o json 2>/dev/null || echo '{}')
STS_JSON=$(docker exec rancher kubectl get sts cache-nodes -n data-grid -o json 2>/dev/null || echo '{}')

# ── Perform live DNS test (Anti-Gaming Integration Check) ────────────────────
DNS_SUCCESS="false"
DNS_OUTPUT="FAILED"

echo "Checking if StatefulSet pods are running..."
POD_STATUS=$(docker exec rancher kubectl get pod cache-nodes-0 -n data-grid -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$POD_STATUS" = "Running" ]; then
    echo "Running DNS integration test from ephemeral pod..."
    # Spin up a temporary pod to test resolution across the cluster
    docker exec rancher kubectl run dns-tester --image=busybox:1.36 --restart=Never -n data-grid -- sleep 60 >/dev/null 2>&1
    
    # Wait for the tester pod to be ready
    docker exec rancher kubectl wait --for=condition=Ready pod/dns-tester -n data-grid --timeout=30s >/dev/null 2>&1
    
    # Attempt to resolve the first stateful pod's exact FQDN
    TARGET_FQDN="cache-nodes-0.cache-discovery.data-grid.svc.cluster.local"
    DNS_OUTPUT=$(docker exec rancher kubectl exec dns-tester -n data-grid -- nslookup "$TARGET_FQDN" 2>&1 || echo "FAILED")
    
    # Check if nslookup returned a valid Address response (BusyBox format)
    if echo "$DNS_OUTPUT" | grep -qi "Address 1: [0-9]"; then
        # Ensure it's not a failure message
        if ! echo "$DNS_OUTPUT" | grep -qi "NXDOMAIN\|can't resolve"; then
            DNS_SUCCESS="true"
            echo "DNS Resolution SUCCESS: Pod IP dynamically resolved."
        fi
    fi
    
    # Cleanup
    docker exec rancher kubectl delete pod dns-tester -n data-grid --force --grace-period=0 >/dev/null 2>&1
else
    echo "StatefulSet pod cache-nodes-0 is not running. Skipping DNS test."
    DNS_OUTPUT="Pod cache-nodes-0 is $POD_STATUS"
fi

# ── Parse and export to JSON ─────────────────────────────────────────────────
export SVC_JSON STS_JSON DNS_SUCCESS DNS_OUTPUT

python3 << 'PYEOF'
import json
import os

def parse_json(raw):
    try:
        return json.loads(raw)
    except Exception:
        return {}

svc = parse_json(os.environ.get("SVC_JSON", "{}"))
sts = parse_json(os.environ.get("STS_JSON", "{}"))
dns_success = os.environ.get("DNS_SUCCESS") == "true"
dns_output = os.environ.get("DNS_OUTPUT", "")

# Safely extract env vars
env_vars = []
try:
    containers = sts.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    if containers:
        env_vars = containers[0].get("env", [])
except Exception:
    pass

result = {
    "service": {
        "exists": bool(svc.get("metadata")),
        "cluster_ip": svc.get("spec", {}).get("clusterIP", ""),
        "selector": svc.get("spec", {}).get("selector", {})
    },
    "statefulset": {
        "exists": bool(sts.get("metadata")),
        "service_name": sts.get("spec", {}).get("serviceName", ""),
        "env": env_vars
    },
    "dns_test": {
        "success": dns_success,
        "output": dns_output
    }
}

# Write out result
output_path = '/tmp/statefulset_peer_discovery_result.json'
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
    
os.chmod(output_path, 0o666)
PYEOF

echo "Result JSON written to /tmp/statefulset_peer_discovery_result.json"
cat /tmp/statefulset_peer_discovery_result.json
echo "=== Export Complete ==="