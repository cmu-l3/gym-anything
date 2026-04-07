#!/bin/bash
# Export script for readiness_probe_circular_deadlock task

echo "=== Exporting readiness_probe_circular_deadlock result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# ── Extract data for checkout-service ─────────────────────────────────────────
CHECKOUT_JSON=$(docker exec rancher kubectl get deployment checkout-service -n ecommerce-core -o json 2>/dev/null || echo "{}")

CHECKOUT_DATA=$(echo "$CHECKOUT_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ready_replicas = data.get('status', {}).get('readyReplicas', 0)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
probe = {}
if containers:
    probe = containers[0].get('readinessProbe', {})
print(json.dumps({'ready_replicas': ready_replicas, 'probe': probe}))
" 2>/dev/null || echo '{"ready_replicas": 0, "probe": {}}')

# ── Extract data for inventory-service ────────────────────────────────────────
INVENTORY_JSON=$(docker exec rancher kubectl get deployment inventory-service -n ecommerce-core -o json 2>/dev/null || echo "{}")

INVENTORY_DATA=$(echo "$INVENTORY_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ready_replicas = data.get('status', {}).get('readyReplicas', 0)
containers = data.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
probe = {}
if containers:
    probe = containers[0].get('readinessProbe', {})
print(json.dumps({'ready_replicas': ready_replicas, 'probe': probe}))
" 2>/dev/null || echo '{"ready_replicas": 0, "probe": {}}')

# ── Write result JSON ─────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "checkout": $CHECKOUT_DATA,
    "inventory": $INVENTORY_DATA
}
EOF

# Move to final location safely
rm -f /tmp/readiness_probe_circular_deadlock_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/readiness_probe_circular_deadlock_result.json
chmod 666 /tmp/readiness_probe_circular_deadlock_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/readiness_probe_circular_deadlock_result.json"
cat /tmp/readiness_probe_circular_deadlock_result.json

echo "=== Export Complete ==="