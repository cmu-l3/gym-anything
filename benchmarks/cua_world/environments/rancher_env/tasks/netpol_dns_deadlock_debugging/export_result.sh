#!/bin/bash
# Export script for netpol_dns_deadlock_debugging task

echo "=== Exporting netpol_dns_deadlock_debugging result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Collect the current state of NetworkPolicies
APP_POLICIES=$(docker exec rancher kubectl get networkpolicy -n app-tier -o json 2>/dev/null || echo '{"items":[]}')
CACHE_POLICIES=$(docker exec rancher kubectl get networkpolicy -n cache-tier -o json 2>/dev/null || echo '{"items":[]}')

# Collect the current state of the Deployment
DATA_FETCHER_DEPLOY=$(docker exec rancher kubectl get deploy data-fetcher -n app-tier -o json 2>/dev/null || echo '{}')

# Collect the current state of the Pods
POD_STATUSES=$(docker exec rancher kubectl get pods -n app-tier -l app=data-fetcher -o json 2>/dev/null || echo '{"items":[]}')

# Save final screenshot for reference
take_screenshot /tmp/netpol_dns_deadlock_final.png

# Write everything to a JSON file for the verifier
TEMP_JSON=$(mktemp /tmp/netpol_result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "app_policies": $APP_POLICIES,
  "cache_policies": $CACHE_POLICIES,
  "data_fetcher_deploy": $DATA_FETCHER_DEPLOY,
  "pod_statuses": $POD_STATUSES
}
EOF

rm -f /tmp/netpol_dns_deadlock_result.json 2>/dev/null || sudo rm -f /tmp/netpol_dns_deadlock_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/netpol_dns_deadlock_result.json
chmod 666 /tmp/netpol_dns_deadlock_result.json

echo "Result JSON written to /tmp/netpol_dns_deadlock_result.json"
echo "=== Export Complete ==="