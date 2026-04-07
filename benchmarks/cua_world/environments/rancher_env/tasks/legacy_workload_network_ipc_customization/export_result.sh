#!/bin/bash
echo "=== Exporting legacy_workload_network_ipc_customization result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Fetch the deployment JSON
DEPLOY_JSON=$(docker exec rancher kubectl get deployment trading-monolith -n legacy-migration -o json 2>/dev/null || echo '{}')

# Process deployment configuration securely via Python
TEMP_JSON=$(mktemp /tmp/legacy_workload_result.XXXXXX.json)
python3 - <<PYEOF > "$TEMP_JSON"
import json
import sys

deploy_json = """$DEPLOY_JSON"""

try:
    deploy = json.loads(deploy_json)
except Exception:
    deploy = {}

spec = deploy.get("spec", {}).get("template", {}).get("spec", {})
status = deploy.get("status", {})

# Extract values
host_aliases = spec.get("hostAliases", [])
dns_policy = spec.get("dnsPolicy", "")
dns_config = spec.get("dnsConfig", {})
volumes = spec.get("volumes", [])

# Health check
replicas = deploy.get("spec", {}).get("replicas", 1)
ready_replicas = status.get("readyReplicas", 0)
updated_replicas = status.get("updatedReplicas", 0)

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "host_aliases": host_aliases,
    "dns_policy": dns_policy,
    "dns_config": dns_config,
    "volumes": volumes,
    "health": {
        "replicas": replicas,
        "ready_replicas": ready_replicas,
        "updated_replicas": updated_replicas
    }
}

print(json.dumps(result, indent=2))
PYEOF

# Move to final location safely
rm -f /tmp/legacy_workload_network_ipc_customization_result.json 2>/dev/null || sudo rm -f /tmp/legacy_workload_network_ipc_customization_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/legacy_workload_network_ipc_customization_result.json
chmod 666 /tmp/legacy_workload_network_ipc_customization_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/legacy_workload_network_ipc_customization_result.json"
cat /tmp/legacy_workload_network_ipc_customization_result.json
echo "=== Export Complete ==="