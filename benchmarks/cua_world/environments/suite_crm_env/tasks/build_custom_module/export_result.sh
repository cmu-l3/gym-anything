#!/bin/bash
echo "=== Exporting build_custom_module results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/build_custom_module_final.png

# 1. Check Filesystem presence inside the PHP container
export PKG_EXISTS=$(docker exec suitecrm-app test -d /var/www/html/custom/modulebuilder/packages/Fleet && echo "true" || echo "false")
export MOD_EXISTS=$(docker exec suitecrm-app test -d /var/www/html/modules/FLT_Vehicle && echo "true" || echo "false")

# 2. Query MariaDB schema
# A deployed module typically creates a table matching the prefix + module name (e.g., flt_vehicle)
# We pull all columns belonging to any table starting with 'flt_vehicle'
export DB_DATA=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -B -e "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'suitecrm' AND table_name LIKE 'flt_vehicle%'" 2>/dev/null | tr '\t' ':')

# 3. Format to JSON using Python
python3 << 'EOF'
import json
import os

pkg_exists = os.environ.get('PKG_EXISTS') == 'true'
mod_exists = os.environ.get('MOD_EXISTS') == 'true'
db_data = os.environ.get('DB_DATA', '')

columns = {}
for line in db_data.split('\n'):
    if ':' in line:
        col, dtype = line.split(':', 1)
        # Store column and its data type mapping (lowercase to avoid case sensitivity issues)
        columns[col.strip().lower()] = dtype.strip().lower()

result = {
    'package_dir_exists': pkg_exists,
    'module_dir_exists': mod_exists,
    'table_exists': len(columns) > 0,
    'columns': columns
}

with open('/tmp/build_custom_module_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure correct permissions for the verifier
chmod 666 /tmp/build_custom_module_result.json 2>/dev/null || sudo chmod 666 /tmp/build_custom_module_result.json 2>/dev/null || true

echo "Result saved to /tmp/build_custom_module_result.json"
cat /tmp/build_custom_module_result.json
echo "=== build_custom_module export complete ==="