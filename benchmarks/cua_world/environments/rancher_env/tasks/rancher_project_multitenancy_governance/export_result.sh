#!/bin/bash
# Export script for rancher_project_multitenancy_governance task

echo "=== Exporting Rancher Project Multi-Tenancy Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Dump projects
PROJECTS_JSON=$(docker exec rancher kubectl get projects.management.cattle.io -n local -o json 2>/dev/null || echo '{"items":[]}')

# Dump project quotas
PROJECT_QUOTAS_JSON=$(docker exec rancher kubectl get projectresourcequotas.management.cattle.io -n local -o json 2>/dev/null || echo '{"items":[]}')

# Dump namespaces
NAMESPACES_JSON=$(docker exec rancher kubectl get namespaces -o json 2>/dev/null || echo '{"items":[]}')

# Check standard ResourceQuotas (for partial credit if they missed ProjectResourceQuotas)
NS_QUOTAS_JSON=$(docker exec rancher kubectl get resourcequotas -A -o json 2>/dev/null || echo '{"items":[]}')

# Check workloads
DEPS_M_SITE=$(docker exec rancher kubectl get deployment marketing-frontend -n marketing-site -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
DEPS_M_ANALYTICS=$(docker exec rancher kubectl get deployment analytics-worker -n marketing-analytics -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
DEPS_S_API=$(docker exec rancher kubectl get deployment sales-gateway -n sales-api -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
DEPS_S_DB=$(docker exec rancher kubectl get deployment sales-postgres -n sales-db -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")

# Check if application is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/rancher_project_multitenancy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "projects": $PROJECTS_JSON,
    "project_quotas": $PROJECT_QUOTAS_JSON,
    "namespaces": $NAMESPACES_JSON,
    "ns_quotas": $NS_QUOTAS_JSON,
    "workloads": {
        "marketing_site_dep": "$DEPS_M_SITE",
        "marketing_analytics_dep": "$DEPS_M_ANALYTICS",
        "sales_api_dep": "$DEPS_S_API",
        "sales_db_dep": "$DEPS_S_DB"
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/rancher_project_multitenancy_result.json 2>/dev/null || sudo rm -f /tmp/rancher_project_multitenancy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rancher_project_multitenancy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rancher_project_multitenancy_result.json
chmod 666 /tmp/rancher_project_multitenancy_result.json 2>/dev/null || sudo chmod 666 /tmp/rancher_project_multitenancy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/rancher_project_multitenancy_result.json"
echo "=== Export complete ==="