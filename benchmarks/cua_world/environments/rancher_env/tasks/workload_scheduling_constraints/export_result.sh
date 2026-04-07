#!/bin/bash
echo "=== Exporting workload_scheduling_constraints result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── Gather Node Labels ────────────────────────────────────────────────────────
NODE_LABELS=$(docker exec rancher kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null)
if [ -z "$NODE_LABELS" ]; then NODE_LABELS="{}"; fi

# ── Gather Node Taints ────────────────────────────────────────────────────────
NODE_TAINTS=$(docker exec rancher kubectl get nodes -o jsonpath='{.items[0].spec.taints}' 2>/dev/null)
if [ -z "$NODE_TAINTS" ]; then NODE_TAINTS="[]"; fi

# ── Gather PriorityClasses ────────────────────────────────────────────────────
PRIORITY_CLASSES=$(docker exec rancher kubectl get priorityclasses -o json 2>/dev/null)
if [ -z "$PRIORITY_CLASSES" ]; then PRIORITY_CLASSES='{"items":[]}'; fi

# ── Gather DaemonSet ──────────────────────────────────────────────────────────
DAEMONSET=$(docker exec rancher kubectl get daemonset log-collector -n monitoring -o json 2>/dev/null)
if [ -z "$DAEMONSET" ]; then DAEMONSET="{}"; fi

# ── Gather Pods Running Status ────────────────────────────────────────────────
# Count pods in monitoring namespace that are running and belong to the log-collector daemonset
DS_PODS_RUNNING=$(docker exec rancher kubectl get pods -n monitoring -l name=log-collector --field-selector status.phase=Running --no-headers 2>/dev/null | grep -c "Running" || true)

# If standard name label wasn't used, just look for pods with log-collector in the name
if [ "$DS_PODS_RUNNING" -eq 0 ]; then
    DS_PODS_RUNNING=$(docker exec rancher kubectl get pods -n monitoring --field-selector status.phase=Running --no-headers 2>/dev/null | grep "log-collector" -c || true)
fi

# ── Generate JSON Output ──────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start_time": $TASK_START,
  "node_labels": $NODE_LABELS,
  "node_taints": $NODE_TAINTS,
  "priority_classes": $PRIORITY_CLASSES,
  "daemonset": $DAEMONSET,
  "ds_pods_running": $DS_PODS_RUNNING
}
EOF

# Move securely
mv "$TEMP_JSON" /tmp/scheduling_constraints_result.json
chmod 644 /tmp/scheduling_constraints_result.json

echo "Result JSON written to /tmp/scheduling_constraints_result.json"
echo "=== Export Complete ==="