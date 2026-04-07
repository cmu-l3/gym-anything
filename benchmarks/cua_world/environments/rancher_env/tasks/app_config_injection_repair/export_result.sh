#!/bin/bash
# Export script for app_config_injection_repair task

echo "=== Exporting app_config_injection_repair result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture screenshot for trajectory analysis
take_screenshot /tmp/app_config_repair_final.png

# ── C1: Check if pods are Running ─────────────────────────────────────────────
PODS_RUNNING=$(docker exec rancher kubectl get pods -n dashboard-prod \
    -l app=analytics-dashboard --field-selector status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Get Deployment JSON
DEPLOYMENT_JSON=$(docker exec rancher kubectl get deployment analytics-dashboard \
    -n dashboard-prod -o json 2>/dev/null || echo '{}')

# ── Check active runtime environment state (if pods are running) ──────────────
ENV_DB_USER=""
ENV_DB_PASS=""
PODINFO_LABELS=""
PODINFO_ANNOTATIONS=""

if [ "$PODS_RUNNING" -ge 1 ]; then
    POD_NAME=$(docker exec rancher kubectl get pods -n dashboard-prod \
        -l app=analytics-dashboard --field-selector status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$POD_NAME" ]; then
        # Check env variables
        ENV_DB_USER=$(docker exec rancher kubectl exec -n dashboard-prod "$POD_NAME" -- sh -c 'echo $DB_USER' 2>/dev/null || echo "")
        ENV_DB_PASS=$(docker exec rancher kubectl exec -n dashboard-prod "$POD_NAME" -- sh -c 'echo $DB_PASS' 2>/dev/null || echo "")
        
        # Check downward API files
        PODINFO_LABELS=$(docker exec rancher kubectl exec -n dashboard-prod "$POD_NAME" -- cat /etc/podinfo/labels.txt 2>/dev/null || echo "")
        PODINFO_ANNOTATIONS=$(docker exec rancher kubectl exec -n dashboard-prod "$POD_NAME" -- cat /etc/podinfo/annotations.txt 2>/dev/null || echo "")
    fi
fi

# ── Write result JSON ─────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/app_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "pods_running": ${PODS_RUNNING:-0},
    "env_db_user_set": $([ -n "$ENV_DB_USER" ] && echo "true" || echo "false"),
    "env_db_pass_set": $([ -n "$ENV_DB_PASS" ] && echo "true" || echo "false"),
    "podinfo_labels_exist": $([ -n "$PODINFO_LABELS" ] && echo "true" || echo "false"),
    "podinfo_annotations_exist": $([ -n "$PODINFO_ANNOTATIONS" ] && echo "true" || echo "false")
}
EOF

# Copy out specifications for API verification
echo "$DEPLOYMENT_JSON" > /tmp/app_config_deployment.json

cp "$TEMP_JSON" /tmp/app_config_result.json
chmod 666 /tmp/app_config_result.json 2>/dev/null || true
chmod 666 /tmp/app_config_deployment.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="