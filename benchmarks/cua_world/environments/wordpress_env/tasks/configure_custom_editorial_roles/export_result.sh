#!/bin/bash
# Export script for configure_custom_editorial_roles task (post_task hook)

echo "=== Exporting configure_custom_editorial_roles result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check if the 'freelance_writer' role exists
ROLE_EXISTS="false"
if wp role exists freelance_writer --allow-root 2>/dev/null; then
    ROLE_EXISTS="true"
    echo "Role 'freelance_writer' exists."
else
    echo "Role 'freelance_writer' DOES NOT exist."
fi

# 2. Get capabilities of the role (if it exists)
CAPABILITIES="{}"
if [ "$ROLE_EXISTS" = "true" ]; then
    CAPABILITIES=$(wp role get freelance_writer --field=capabilities --format=json --allow-root 2>/dev/null || echo "{}")
fi

# 3. Get the roles for the three target users
SAM_ROLES=$(wp user get sam_taylor --field=roles --format=json --allow-root 2>/dev/null || echo "[]")
ALEX_ROLES=$(wp user get alex_rivera --field=roles --format=json --allow-root 2>/dev/null || echo "[]")
JORDAN_ROLES=$(wp user get jordan_lee --field=roles --format=json --allow-root 2>/dev/null || echo "[]")

# 4. Use Python to safely compile the verification data into JSON
python3 << EOF
import json
import os

try:
    capabilities_dict = json.loads('$CAPABILITIES')
except:
    capabilities_dict = {}

try:
    sam_roles_list = json.loads('$SAM_ROLES')
except:
    sam_roles_list = []

try:
    alex_roles_list = json.loads('$ALEX_ROLES')
except:
    alex_roles_list = []

try:
    jordan_roles_list = json.loads('$JORDAN_ROLES')
except:
    jordan_roles_list = []

result_data = {
    "role_exists": "$ROLE_EXISTS" == "true",
    "role_capabilities": capabilities_dict,
    "user_roles": {
        "sam_taylor": sam_roles_list,
        "alex_rivera": alex_roles_list,
        "jordan_lee": jordan_roles_list
    },
    "timestamp": "$(date -Iseconds)"
}

temp_path = '/tmp/custom_roles_result_temp.json'
final_path = '/tmp/configure_custom_editorial_roles_result.json'

with open(temp_path, 'w') as f:
    json.dump(result_data, f, indent=4)

# Move to final location securely
os.system(f"rm -f {final_path} 2>/dev/null || sudo rm -f {final_path} 2>/dev/null || true")
os.system(f"cp {temp_path} {final_path} 2>/dev/null || sudo cp {temp_path} {final_path}")
os.system(f"chmod 666 {final_path} 2>/dev/null || sudo chmod 666 {final_path} 2>/dev/null || true")
os.system(f"rm -f {temp_path}")
EOF

echo ""
echo "Result exported to /tmp/configure_custom_editorial_roles_result.json:"
cat /tmp/configure_custom_editorial_roles_result.json
echo ""
echo "=== Export complete ==="