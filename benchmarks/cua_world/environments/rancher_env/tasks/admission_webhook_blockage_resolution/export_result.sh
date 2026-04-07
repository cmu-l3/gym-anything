#!/bin/bash
# Export script for admission_webhook_blockage_resolution task

echo "=== Exporting admission_webhook_blockage_resolution result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ── 1. Collect Webhook States ───────────────────────────────────────────────
VWC_JSON=$(docker exec rancher kubectl get validatingwebhookconfiguration security-policy-validator -o json 2>/dev/null || echo "{}")
MWC_JSON=$(docker exec rancher kubectl get mutatingwebhookconfiguration resource-defaults-injector -o json 2>/dev/null || echo "{}")

# ── 2. Collect Namespace Labels ─────────────────────────────────────────────
STAGING_JSON=$(docker exec rancher kubectl get namespace staging -o json 2>/dev/null || echo "{}")

# ── 3. Collect Test Deployment State ────────────────────────────────────────
TEST_DEPLOY_JSON=$(docker exec rancher kubectl get deployment webhook-test -n staging -o json 2>/dev/null || echo "{}")
TEST_PODS_JSON=$(docker exec rancher kubectl get pods -n staging -l app=webhook-test -o json 2>/dev/null || echo "{\"items\":[]}")

# ── 4. Collect Existing Workload State ──────────────────────────────────────
NGINX_DEPLOY_JSON=$(docker exec rancher kubectl get deployment nginx-web -n staging -o json 2>/dev/null || echo "{}")
NGINX_PODS_JSON=$(docker exec rancher kubectl get pods -n staging -l app=nginx-web -o json 2>/dev/null || echo "{\"items\":[]}")

# ── 5. Write everything to a structured JSON file ───────────────────────────
TEMP_JSON=$(mktemp /tmp/webhook_result.XXXXXX.json)

cat > "$TEMP_JSON" <<EOF
{
  "timestamp": $(date +%s),
  "vwc_security_policy": $VWC_JSON,
  "mwc_resource_injector": $MWC_JSON,
  "staging_namespace": $STAGING_JSON,
  "test_deployment": $TEST_DEPLOY_JSON,
  "test_pods": $TEST_PODS_JSON,
  "nginx_deployment": $NGINX_DEPLOY_JSON,
  "nginx_pods": $NGINX_PODS_JSON
}
EOF

# Ensure file is readable by the verifier
rm -f /tmp/admission_webhook_blockage_resolution_result.json 2>/dev/null || sudo rm -f /tmp/admission_webhook_blockage_resolution_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/admission_webhook_blockage_resolution_result.json
chmod 666 /tmp/admission_webhook_blockage_resolution_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/admission_webhook_blockage_resolution_result.json"
echo "=== Export complete ==="