#!/bin/bash
# Export script for api_version_deprecation_migration task

echo "=== Exporting api_version_deprecation_migration result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target namespace
NS="legacy-billing"

# ── Extract Cluster State ─────────────────────────────────────────────────────
# If namespace doesn't exist, these will safely return empty/error JSON
INGRESS_JSON=$(docker exec rancher kubectl get ingress billing-ingress -n "$NS" -o json 2>/dev/null || echo "{}")
HPA_JSON=$(docker exec rancher kubectl get hpa billing-hpa -n "$NS" -o json 2>/dev/null || echo "{}")
PDB_JSON=$(docker exec rancher kubectl get pdb billing-pdb -n "$NS" -o json 2>/dev/null || echo "{}")
PODS_JSON=$(docker exec rancher kubectl get pods -n "$NS" -l app=billing-app -o json 2>/dev/null || echo '{"items":[]}')

# Check file modification times on the desktop
MANIFEST_DIR="/home/ga/Desktop/legacy-billing-manifests"
INGRESS_MODIFIED=0
HPA_MODIFIED=0
PDB_MODIFIED=0

if [ -f "$MANIFEST_DIR/ingress.yaml" ]; then
    INGRESS_MODIFIED=$(stat -c %Y "$MANIFEST_DIR/ingress.yaml" 2>/dev/null || echo 0)
fi
if [ -f "$MANIFEST_DIR/hpa.yaml" ]; then
    HPA_MODIFIED=$(stat -c %Y "$MANIFEST_DIR/hpa.yaml" 2>/dev/null || echo 0)
fi
if [ -f "$MANIFEST_DIR/pdb.yaml" ]; then
    PDB_MODIFIED=$(stat -c %Y "$MANIFEST_DIR/pdb.yaml" 2>/dev/null || echo 0)
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── Write result JSON safely using a temporary file ───────────────────────────
TEMP_JSON=$(mktemp /tmp/api_migration_result.XXXXXX.json)

cat > "$TEMP_JSON" <<EOF
{
  "task_start_time": $TASK_START,
  "file_mtimes": {
    "ingress": $INGRESS_MODIFIED,
    "hpa": $HPA_MODIFIED,
    "pdb": $PDB_MODIFIED
  },
  "cluster_resources": {
    "ingress": $INGRESS_JSON,
    "hpa": $HPA_JSON,
    "pdb": $PDB_JSON,
    "pods": $PODS_JSON
  }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="