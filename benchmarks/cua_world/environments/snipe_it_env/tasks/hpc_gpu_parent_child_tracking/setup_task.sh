#!/bin/bash
echo "=== Setting up hpc_gpu_parent_child_tracking task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare dependencies (Manufacturers, Categories, Models, Status, Location)
MAN_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name LIKE '%Dell%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_DELL" ]; then
    MAN_DELL=$(snipeit_api POST "manufacturers" '{"name":"Dell"}' | jq -r '.payload.id // empty')
fi

MAN_NVIDIA=$(snipeit_api POST "manufacturers" '{"name":"NVIDIA"}' | jq -r '.payload.id // empty')
if [ -z "$MAN_NVIDIA" ]; then
    snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('NVIDIA', NOW(), NOW())"
    MAN_NVIDIA=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='NVIDIA' LIMIT 1" | tr -d '[:space:]')
fi

CAT_SERVER=$(snipeit_db_query "SELECT id FROM categories WHERE name='Servers' LIMIT 1" | tr -d '[:space:]')
CAT_GPU=$(snipeit_api POST "categories" '{"name":"AI Accelerators","category_type":"asset"}' | jq -r '.payload.id // empty')
if [ -z "$CAT_GPU" ]; then
    snipeit_db_query "INSERT INTO categories (name, category_type, created_at, updated_at) VALUES ('AI Accelerators', 'asset', NOW(), NOW())"
    CAT_GPU=$(snipeit_db_query "SELECT id FROM categories WHERE name='AI Accelerators' LIMIT 1" | tr -d '[:space:]')
fi

MDL_SERVER=$(snipeit_api POST "models" "{\"name\":\"Dell PowerEdge XE9680\",\"manufacturer_id\":$MAN_DELL,\"category_id\":$CAT_SERVER}" | jq -r '.payload.id // empty')
if [ -z "$MDL_SERVER" ]; then
    snipeit_db_query "INSERT INTO models (name, manufacturer_id, category_id, created_at, updated_at) VALUES ('Dell PowerEdge XE9680', $MAN_DELL, $CAT_SERVER, NOW(), NOW())"
    MDL_SERVER=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell PowerEdge XE9680' LIMIT 1" | tr -d '[:space:]')
fi

MDL_GPU=$(snipeit_api POST "models" "{\"name\":\"NVIDIA H100 Tensor Core 80GB\",\"manufacturer_id\":$MAN_NVIDIA,\"category_id\":$CAT_GPU}" | jq -r '.payload.id // empty')
if [ -z "$MDL_GPU" ]; then
    snipeit_db_query "INSERT INTO models (name, manufacturer_id, category_id, created_at, updated_at) VALUES ('NVIDIA H100 Tensor Core 80GB', $MAN_NVIDIA, $CAT_GPU, NOW(), NOW())"
    MDL_GPU=$(snipeit_db_query "SELECT id FROM models WHERE name='NVIDIA H100 Tensor Core 80GB' LIMIT 1" | tr -d '[:space:]')
fi

LOC_RACK=$(snipeit_api POST "locations" '{"name":"Data Center - Rack 42"}' | jq -r '.payload.id // empty')
if [ -z "$LOC_RACK" ]; then
    snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('Data Center - Rack 42', NOW(), NOW())"
    LOC_RACK=$(snipeit_db_query "SELECT id FROM locations WHERE name='Data Center - Rack 42' LIMIT 1" | tr -d '[:space:]')
fi

SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# 2. Delete existing target assets to ensure clean state
for tag in "AI-CHASSIS-01" "AI-CHASSIS-LEGACY" "GPU-H100-101" "GPU-H100-102" "GPU-H100-001" "GPU-H100-002"; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
done

# 3. Create Legacy Chassis and Legacy GPUs
LEGACY_SERVER=$(snipeit_api POST "hardware" "{\"asset_tag\":\"AI-CHASSIS-LEGACY\",\"name\":\"Legacy Compute Node\",\"model_id\":$MDL_SERVER,\"status_id\":$SL_READY}" | jq -r '.payload.id // empty')
if [ -z "$LEGACY_SERVER" ]; then
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, created_at, updated_at) VALUES ('AI-CHASSIS-LEGACY', 'Legacy Compute Node', $MDL_SERVER, $SL_READY, NOW(), NOW())"
    LEGACY_SERVER=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='AI-CHASSIS-LEGACY' LIMIT 1" | tr -d '[:space:]')
fi

GPU_001=$(snipeit_api POST "hardware" "{\"asset_tag\":\"GPU-H100-001\",\"name\":\"Legacy H100 1\",\"model_id\":$MDL_GPU,\"status_id\":$SL_READY}" | jq -r '.payload.id // empty')
if [ -z "$GPU_001" ]; then
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, created_at, updated_at) VALUES ('GPU-H100-001', 'Legacy H100 1', $MDL_GPU, $SL_READY, NOW(), NOW())"
    GPU_001=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='GPU-H100-001' LIMIT 1" | tr -d '[:space:]')
fi

GPU_002=$(snipeit_api POST "hardware" "{\"asset_tag\":\"GPU-H100-002\",\"name\":\"Legacy H100 2\",\"model_id\":$MDL_GPU,\"status_id\":$SL_READY}" | jq -r '.payload.id // empty')
if [ -z "$GPU_002" ]; then
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, created_at, updated_at) VALUES ('GPU-H100-002', 'Legacy H100 2', $MDL_GPU, $SL_READY, NOW(), NOW())"
    GPU_002=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='GPU-H100-002' LIMIT 1" | tr -d '[:space:]')
fi

# 4. Check out Legacy GPUs to Legacy Chassis (Assign to Asset)
# Note: the four backslashes ensure MySQL receives "App\Models\Asset"
snipeit_db_query "UPDATE assets SET assigned_to=$LEGACY_SERVER, assigned_type='App\\\\Models\\\\Asset' WHERE id IN ($GPU_001, $GPU_002)"

echo "Rack Location ID: $LOC_RACK"
echo "Legacy Server ID: $LEGACY_SERVER"
echo "$LOC_RACK" > /tmp/hpc_rack_location_id.txt
echo "$LEGACY_SERVER" > /tmp/hpc_legacy_server_id.txt

# 5. Record task start
date +%s > /tmp/hpc_task_start.txt

# 6. Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/hpc_task_initial.png

echo "=== hpc_gpu_parent_child_tracking task setup complete ==="