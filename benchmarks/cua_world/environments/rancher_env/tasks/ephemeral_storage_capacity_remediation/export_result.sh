#!/bin/bash
# Export script for ephemeral_storage_capacity_remediation task

echo "=== Exporting ephemeral_storage_capacity_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/ephemeral_storage_final.png

# 1. Check report-generator state
RG_RUNNING=$(docker exec rancher kubectl get pods -n data-platform -l app=report-generator --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
RG_CMD=$(docker exec rancher kubectl get deployment report-generator -n data-platform -o jsonpath='{.spec.template.spec.containers[0].command[*]} {.spec.template.spec.containers[0].args[*]}' 2>/dev/null)

# 2. Check query-engine state
QE_RUNNING=$(docker exec rancher kubectl get pods -n data-platform -l app=query-engine --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

# 3. Check data-cache state
DC_RUNNING=$(docker exec rancher kubectl get pods -n data-platform -l app=data-cache --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
DC_CMD=$(docker exec rancher kubectl get deployment data-cache -n data-platform -o jsonpath='{.spec.template.spec.containers[0].command[*]} {.spec.template.spec.containers[0].args[*]}' 2>/dev/null)

# 4. Check for hygiene: Are there any Failed (Evicted) pods left in the namespace?
EVICTED_COUNT=$(docker exec rancher kubectl get pods -n data-platform --field-selector status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')

# Escape commands for JSON safely
RG_CMD_ESC=$(echo "$RG_CMD" | sed 's/"/\\"/g')
DC_CMD_ESC=$(echo "$DC_CMD" | sed 's/"/\\"/g')

# Create JSON result
cat > /tmp/ephemeral_storage_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "rg_running": $RG_RUNNING,
  "rg_cmd": "$RG_CMD_ESC",
  "qe_running": $QE_RUNNING,
  "dc_running": $DC_RUNNING,
  "dc_cmd": "$DC_CMD_ESC",
  "evicted_count": $EVICTED_COUNT
}
EOF

echo "Result JSON written to /tmp/ephemeral_storage_result.json"
cat /tmp/ephemeral_storage_result.json
echo "=== Export Complete ==="