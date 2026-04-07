#!/bin/bash
echo "=== Exporting hpc_gpu_parent_child_tracking results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/hpc_task_final.png

LOC_RACK=$(cat /tmp/hpc_rack_location_id.txt 2>/dev/null || echo "0")
LEGACY_SERVER=$(cat /tmp/hpc_legacy_server_id.txt 2>/dev/null || echo "0")

build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, COALESCE(assigned_to, 0), COALESCE(assigned_type, ''), COALESCE(rtd_location_id, 0) FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local id=$(echo "$data" | awk -F'\t' '{print $1}')
    local assigned_to=$(echo "$data" | awk -F'\t' '{print $2}')
    local assigned_type=$(echo "$data" | awk -F'\t' '{print $3}')
    local rtd_location_id=$(echo "$data" | awk -F'\t' '{print $4}')
    echo "{\"tag\": \"$tag\", \"found\": true, \"id\": \"$id\", \"assigned_to\": \"$assigned_to\", \"assigned_type\": \"$(json_escape "$assigned_type")\", \"rtd_location_id\": \"$rtd_location_id\"}"
}

CHASSIS_01=$(build_asset_json "AI-CHASSIS-01")
CHASSIS_LEGACY=$(build_asset_json "AI-CHASSIS-LEGACY")
GPU_101=$(build_asset_json "GPU-H100-101")
GPU_102=$(build_asset_json "GPU-H100-102")
GPU_001=$(build_asset_json "GPU-H100-001")
GPU_002=$(build_asset_json "GPU-H100-002")

RESULT_JSON=$(cat << JSONEOF
{
  "rack_location_id": "$LOC_RACK",
  "legacy_server_id": "$LEGACY_SERVER",
  "chassis_01": $CHASSIS_01,
  "chassis_legacy": $CHASSIS_LEGACY,
  "gpu_101": $GPU_101,
  "gpu_102": $GPU_102,
  "gpu_001": $GPU_001,
  "gpu_002": $GPU_002
}
JSONEOF
)

safe_write_result "/tmp/hpc_gpu_parent_child_tracking_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/hpc_gpu_parent_child_tracking_result.json"
echo "$RESULT_JSON"
echo "=== hpc_gpu_parent_child_tracking export complete ==="