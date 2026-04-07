#!/bin/bash
# Export script for externalname_dns_routing task

echo "=== Exporting externalname_dns_routing result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# ── Check Service Abstraction (C1) ───────────────────────────────────────────
echo "Evaluating ExternalName Service..."
SVC_JSON=$(docker exec rancher kubectl get svc database-svc -n legacy-apps -o json 2>/dev/null || echo "{}")

SVC_TYPE=$(echo "$SVC_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('spec', {}).get('type', 'None'))")
SVC_EXT_NAME=$(echo "$SVC_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('spec', {}).get('externalName', 'None'))")

# ── Probing Networks (C2 and C3) ─────────────────────────────────────────────
echo "Running network probes..."

FRONTEND_POD=$(docker exec rancher kubectl get pod -n legacy-apps -l app=inventory-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
ROGUE_POD=$(docker exec rancher kubectl get pod -n rogue-ns -l app=rogue-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

FRONTEND_CONNECT_SVC="false"
FRONTEND_CONNECT_DIRECT="false"
ROGUE_CONNECT_DIRECT="false"

if [ -n "$FRONTEND_POD" ]; then
    # Test connection via the requested DNS abstraction
    if docker exec rancher kubectl exec -n legacy-apps "$FRONTEND_POD" -- nc -z -w 2 database-svc 5432 2>/dev/null; then
        FRONTEND_CONNECT_SVC="true"
    fi
    # Test connection directly via FQDN (to isolate NetworkPolicy status from DNS abstraction status)
    if docker exec rancher kubectl exec -n legacy-apps "$FRONTEND_POD" -- nc -z -w 2 postgres-primary.core-data.svc.cluster.local 5432 2>/dev/null; then
        FRONTEND_CONNECT_DIRECT="true"
    fi
fi

if [ -n "$ROGUE_POD" ]; then
    # Test if rogue pod can bypass isolation
    if docker exec rancher kubectl exec -n rogue-ns "$ROGUE_POD" -- nc -z -w 2 postgres-primary.core-data.svc.cluster.local 5432 2>/dev/null; then
        ROGUE_CONNECT_DIRECT="true"
    fi
fi

# ── Check Deployment Immutability (C4) ───────────────────────────────────────
echo "Evaluating deployment immutability..."
docker exec rancher kubectl get deployment inventory-frontend -n legacy-apps \
    -o jsonpath='{.spec.template.spec.containers[0]}' 2>/dev/null > /tmp/current_container.json || echo "{}" > /tmp/current_container.json

# ── Write Result JSON ────────────────────────────────────────────────────────
echo "Building result JSON..."

cat > /tmp/externalname_dns_routing_result.json <<EOF
{
  "service": {
    "type": "$SVC_TYPE",
    "external_name": "$SVC_EXT_NAME"
  },
  "network_probes": {
    "frontend_to_svc_success": $FRONTEND_CONNECT_SVC,
    "frontend_to_fqdn_success": $FRONTEND_CONNECT_DIRECT,
    "rogue_to_fqdn_success": $ROGUE_CONNECT_DIRECT
  },
  "containers": {
    "baseline": $(cat /tmp/baseline_container.json 2>/dev/null || echo "{}"),
    "current": $(cat /tmp/current_container.json 2>/dev/null || echo "{}")
  }
}
EOF

echo "Result JSON written to /tmp/externalname_dns_routing_result.json"
echo "=== Export Complete ==="