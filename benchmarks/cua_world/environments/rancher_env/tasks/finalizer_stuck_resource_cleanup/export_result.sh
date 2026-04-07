#!/bin/bash
# Export script for finalizer_stuck_resource_cleanup task

echo "=== Exporting finalizer_stuck_resource_cleanup result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/task_final.png

# ── Check Namespace 'old-project' ────────────────────────────────────────────
NS_EXISTS=$(docker exec rancher kubectl get namespace old-project --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NS_EXISTS" -gt 0 ]; then
    NS_PHASE=$(docker exec rancher kubectl get namespace old-project -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
else
    NS_PHASE="Deleted"
fi

# ── Check PVC 'data-vol' ─────────────────────────────────────────────────────
PVC_EXISTS=$(docker exec rancher kubectl get pvc data-vol -n staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PVC_EXISTS" -gt 0 ]; then
    PVC_DEL_TS=$(docker exec rancher kubectl get pvc data-vol -n staging -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "")
else
    PVC_DEL_TS=""
fi

# ── Check ConfigMap 'legacy-config' ──────────────────────────────────────────
CM_EXISTS=$(docker exec rancher kubectl get configmap legacy-config -n staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$CM_EXISTS" -gt 0 ]; then
    CM_DEL_TS=$(docker exec rancher kubectl get configmap legacy-config -n staging -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "")
else
    CM_DEL_TS=""
fi

# ── Check Service 'orphaned-svc' ─────────────────────────────────────────────
SVC_EXISTS=$(docker exec rancher kubectl get service orphaned-svc -n staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SVC_EXISTS" -gt 0 ]; then
    SVC_DEL_TS=$(docker exec rancher kubectl get service orphaned-svc -n staging -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo "")
else
    SVC_DEL_TS=""
fi

# ── Check Collateral Damage ──────────────────────────────────────────────────
# The staging namespace and its core workloads should still exist
STAGING_EXISTS=$(docker exec rancher kubectl get namespace staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
NGINX_EXISTS=$(docker exec rancher kubectl get deployment nginx-web -n staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
REDIS_EXISTS=$(docker exec rancher kubectl get deployment redis-primary -n staging --no-headers 2>/dev/null | wc -l | tr -d ' ')

# ── Write Result JSON ────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
  "task_end_time": $(date +%s),
  "namespace_old_project": {
    "exists": $NS_EXISTS,
    "phase": "$NS_PHASE"
  },
  "pvc_data_vol": {
    "exists": $PVC_EXISTS,
    "has_deletion_timestamp": $([ -n "$PVC_DEL_TS" ] && echo "true" || echo "false")
  },
  "cm_legacy_config": {
    "exists": $CM_EXISTS,
    "has_deletion_timestamp": $([ -n "$CM_DEL_TS" ] && echo "true" || echo "false")
  },
  "svc_orphaned_svc": {
    "exists": $SVC_EXISTS,
    "has_deletion_timestamp": $([ -n "$SVC_DEL_TS" ] && echo "true" || echo "false")
  },
  "collateral": {
    "staging_exists": $STAGING_EXISTS,
    "nginx_web_exists": $NGINX_EXISTS,
    "redis_primary_exists": $REDIS_EXISTS
  }
}
EOF

# Move to final location safely
rm -f /tmp/finalizer_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/finalizer_task_result.json
chmod 666 /tmp/finalizer_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/finalizer_task_result.json"
cat /tmp/finalizer_task_result.json
echo "=== Export Complete ==="