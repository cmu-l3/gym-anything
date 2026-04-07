#!/bin/bash
# Export script for hpa_pdb_surge_preparation task

echo "=== Exporting hpa_pdb_surge_preparation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Retrieve all HPAs in the target namespace in JSON format
echo "Fetching HPAs..."
HPA_JSON=$(docker exec rancher kubectl get hpa -n ecommerce-prod -o json 2>/dev/null || echo '{"items":[]}')

# Retrieve all PDBs in the target namespace in JSON format
echo "Fetching PDBs..."
PDB_JSON=$(docker exec rancher kubectl get pdb -n ecommerce-prod -o json 2>/dev/null || echo '{"items":[]}')

# Fetch start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Combine into a single result file safely
TEMP_JSON=$(mktemp /tmp/hpa_pdb_result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "hpas": $HPA_JSON,
  "pdbs": $PDB_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with open permissions
mv "$TEMP_JSON" /tmp/hpa_pdb_result.json
chmod 666 /tmp/hpa_pdb_result.json

echo "Result JSON written to /tmp/hpa_pdb_result.json"
echo "=== Export complete ==="