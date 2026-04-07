#!/bin/bash
# Export script for daemonset_fleet_remediation task

echo "=== Exporting daemonset_fleet_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── Check pod states ──────────────────────────────────────────────────────────

check_running_pods() {
    local app_label=$1
    local count=$(docker exec rancher kubectl get pods -n monitoring -l app=$app_label --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ -z "$count" ]; then
        echo "0"
    else
        echo "$count"
    fi
}

NODE_EXPORTER_RUNNING=$(check_running_pods "node-exporter")
LOG_COLLECTOR_RUNNING=$(check_running_pods "log-collector")
DISK_MONITOR_RUNNING=$(check_running_pods "disk-monitor")
NETWORK_PROBE_RUNNING=$(check_running_pods "network-probe")

# ── Extract DaemonSet properties for root cause validation ────────────────────
DS_JSON=$(docker exec rancher kubectl get daemonset -n monitoring -o json 2>/dev/null || echo '{"items":[]}')

# Use Python to extract values robustly
NODE_SELECTOR_OS=$(echo "$DS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('metadata', {}).get('name') == 'node-exporter':
        print(item.get('spec', {}).get('template', {}).get('spec', {}).get('nodeSelector', {}).get('kubernetes.io/os', 'none'))
        sys.exit(0)
print('none')
" 2>/dev/null || echo "none")

LOG_COLLECTOR_IMAGE=$(echo "$DS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('metadata', {}).get('name') == 'log-collector':
        containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
        for c in containers:
            if c.get('name') == 'log-collector':
                print(c.get('image', 'none'))
                sys.exit(0)
print('none')
" 2>/dev/null || echo "none")

DISK_MONITOR_SEC_CTX=$(echo "$DS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('metadata', {}).get('name') == 'disk-monitor':
        sec = item.get('spec', {}).get('template', {}).get('spec', {}).get('securityContext', {})
        print(json.dumps(sec))
        sys.exit(0)
print('{}')
" 2>/dev/null || echo "{}")

NETWORK_PROBE_CPU=$(echo "$DS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('metadata', {}).get('name') == 'network-probe':
        containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
        for c in containers:
            if c.get('name') == 'network-probe':
                print(c.get('resources', {}).get('requests', {}).get('cpu', 'none'))
                sys.exit(0)
print('none')
" 2>/dev/null || echo "none")

# Export to JSON
cat > /tmp/daemonset_fleet_remediation_result.json <<EOF
{
    "node_exporter": {
        "running_pods": $NODE_EXPORTER_RUNNING,
        "node_selector_os": "$NODE_SELECTOR_OS"
    },
    "log_collector": {
        "running_pods": $LOG_COLLECTOR_RUNNING,
        "image": "$LOG_COLLECTOR_IMAGE"
    },
    "disk_monitor": {
        "running_pods": $DISK_MONITOR_RUNNING,
        "security_context": $DISK_MONITOR_SEC_CTX
    },
    "network_probe": {
        "running_pods": $NETWORK_PROBE_RUNNING,
        "cpu_request": "$NETWORK_PROBE_CPU"
    }
}
EOF

echo "Result JSON written to /tmp/daemonset_fleet_remediation_result.json"
echo "=== Export Complete ==="