#!/bin/bash
echo "=== Setting up build_custom_module task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts or pre-existing data (Anti-gaming measure)
echo "Cleaning up any existing Fleet packages or tables..."
# Remove module builder package files
docker exec suitecrm-app rm -rf /var/www/html/custom/modulebuilder/packages/Fleet 2>/dev/null || true
# Remove deployed module files
docker exec suitecrm-app rm -rf /var/www/html/modules/FLT_Vehicle 2>/dev/null || true
# Drop database tables that might exist from previous deployments
suitecrm_db_query "DROP TABLE IF EXISTS flt_vehicle, flt_vehicles, flt_vehicle_cstm, flt_vehicles_cstm, flt_vehicle_audit, flt_vehicles_audit;" 2>/dev/null || true

# Clear system cache just in case
docker exec suitecrm-app bash -c "rm -rf /var/www/html/cache/modules/FLT_Vehicle" 2>/dev/null || true

# 2. Ensure logged in and navigate directly to the Module Builder
# (Found in the Admin panel, but we navigate directly to save initial repetitive clicks)
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=ModuleBuilder&action=index"
sleep 4

# 3. Take initial screenshot for evidence
take_screenshot /tmp/build_custom_module_initial.png

echo "=== build_custom_module task setup complete ==="
echo "Task: Build and deploy the FLT_Vehicle custom module."
echo "Agent should navigate the Module Builder interface, create fields, and Deploy."