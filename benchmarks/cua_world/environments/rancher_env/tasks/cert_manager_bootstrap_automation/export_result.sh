#!/bin/bash
# Export script for cert_manager_bootstrap_automation task

echo "=== Exporting cert_manager_bootstrap_automation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/task_final.png

# Fetch deployments in cert-manager namespace
DEPLOYS_JSON=$(docker exec rancher kubectl get deploy -n cert-manager -o json 2>/dev/null || echo '{"items":[]}')

# Fetch the specified ClusterIssuer
ISSUER_JSON=$(docker exec rancher kubectl get clusterissuer local-selfsigned -o json 2>/dev/null || echo '{}')

# Fetch the expected Ingress
INGRESS_JSON=$(docker exec rancher kubectl get ingress shop-ingress -n e-commerce -o json 2>/dev/null || echo '{}')

# Fetch all certificates in e-commerce namespace
CERTS_JSON=$(docker exec rancher kubectl get certificate -n e-commerce -o json 2>/dev/null || echo '{"items":[]}')

# Fetch the expected Secret
SECRET_JSON=$(docker exec rancher kubectl get secret shop-tls-secret -n e-commerce -o json 2>/dev/null || echo '{}')

export DEPLOYS_JSON ISSUER_JSON INGRESS_JSON CERTS_JSON SECRET_JSON
export TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
export TASK_END=$(date +%s)

# Use Python to assemble the export data robustly
python3 - << 'PYEOF'
import os
import json

def parse_json(raw_json, default):
    try:
        return json.loads(raw_json)
    except Exception:
        return default

data = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "cert_manager_deployments": parse_json(os.environ.get("DEPLOYS_JSON"), {"items":[]}),
    "cluster_issuer": parse_json(os.environ.get("ISSUER_JSON"), {}),
    "ingress": parse_json(os.environ.get("INGRESS_JSON"), {}),
    "certificates": parse_json(os.environ.get("CERTS_JSON"), {"items":[]}),
    "tls_secret": parse_json(os.environ.get("SECRET_JSON"), {})
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(data, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="