#!/bin/bash
# Export script for B2B Net 30 Payment task
echo "=== Exporting B2B Net 30 Payment Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper for Drush
run_drush() {
    cd /var/www/html/drupal
    /var/www/html/drupal/vendor/bin/drush "$@"
}

# --- 1. Verify User Role ---
echo "Checking for Wholesale Buyer role..."
# List all roles
ROLES_JSON=$(run_drush role:list --format=json 2>/dev/null)
# Check for a role with label "Wholesale Buyer" or machine name "wholesale_buyer"
ROLE_FOUND="false"
ROLE_ID=""

# We'll use python to parse the JSON output from drush role:list
ROLE_INFO=$(python3 -c "
import sys, json
try:
    roles = json.load(sys.stdin)
    # roles is a dict: {machine_name: {label: ...}, ...}
    found_id = ''
    for rid, rdata in roles.items():
        label = rdata.get('label', '')
        if 'wholesale' in rid.lower() or 'wholesale' in label.lower():
            found_id = rid
            print(json.dumps({'found': True, 'id': rid, 'label': label}))
            break
    if not found_id:
        print(json.dumps({'found': False}))
except:
    print(json.dumps({'found': False}))
" <<< "$ROLES_JSON")

ROLE_FOUND=$(echo "$ROLE_INFO" | jq -r .found)
ROLE_ID=$(echo "$ROLE_INFO" | jq -r .id)

# --- 2. Verify User ---
echo "Checking for corporate_buyer user..."
USER_CHECK=$(drupal_db_query "SELECT uid, name, mail FROM users_field_data WHERE name='corporate_buyer'")
USER_FOUND="false"
USER_UID=""
USER_HAS_ROLE="false"

if [ -n "$USER_CHECK" ]; then
    USER_FOUND="true"
    USER_UID=$(echo "$USER_CHECK" | cut -f1)
    
    # Check if user has the role
    if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "null" ]; then
        # Check user__roles table
        HAS_ROLE_DB=$(drupal_db_query "SELECT COUNT(*) FROM user__roles WHERE entity_id=$USER_UID AND roles_target_id='$ROLE_ID'")
        if [ "$HAS_ROLE_DB" -gt 0 ]; then
            USER_HAS_ROLE="true"
        fi
    fi
fi

# --- 3. Verify Payment Gateway ---
echo "Checking for Net 30 Payment Gateway..."
# Get all payment gateways
GW_CONFIGS=$(run_drush config:list --prefix=commerce_payment.commerce_payment_gateway --format=json 2>/dev/null)

GW_FOUND="false"
GW_ID=""
GW_LABEL=""
GW_PLUGIN=""
GW_STATUS=""
GW_INSTRUCTIONS=""
GW_HAS_CONDITION="false"

# Iterate through configs to find the right one
# We use a python script to inspect the configs one by one via drush config:get
# This is safer than parsing raw DB blobs for complex nested structures like conditions
export GW_CONFIGS
export ROLE_ID

PYTHON_CHECK_SCRIPT=$(cat <<EOF
import sys, json, subprocess, os

role_id = os.environ.get('ROLE_ID', '')
configs = json.loads(os.environ.get('GW_CONFIGS', '[]'))
best_match = None

for config_name in configs:
    # Get full config
    try:
        cmd = ['/var/www/html/drupal/vendor/bin/drush', 'config:get', config_name, '--format=json']
        res = subprocess.check_output(cmd, cwd='/var/www/html/drupal')
        data = json.loads(res)
        
        # The key in data is the config name
        gw = data.get(config_name, {})
        label = gw.get('label', '')
        
        if 'Net 30' in label or 'net_30' in config_name:
            best_match = gw
            break
    except Exception as e:
        continue

result = {
    'found': False,
    'label': '',
    'plugin': '',
    'status': False,
    'instructions_match': False,
    'condition_match': False
}

if best_match:
    result['found'] = True
    result['label'] = best_match.get('label', '')
    result['plugin'] = best_match.get('plugin', '')
    result['status'] = best_match.get('status', False)
    
    # Check instructions
    config_data = best_match.get('configuration', {})
    instructions = config_data.get('instructions', {}).get('value', '')
    if 'Payment due within 30 days' in instructions:
        result['instructions_match'] = True
        
    # Check conditions
    # Conditions are stored in 'conditions' array/dict
    conditions = best_match.get('conditions', [])
    # In config export, conditions might be a dict or list
    if isinstance(conditions, dict):
        conditions = conditions.values()
        
    for cond in conditions:
        if cond.get('plugin') == 'customer_role':
            conf = cond.get('configuration', {})
            roles = conf.get('roles', {})
            # roles might be a list or dict depending on storage
            if isinstance(roles, dict):
                roles = list(roles.values())
            
            if role_id and role_id in roles:
                result['condition_match'] = True
            elif not role_id:
                # If we didn't find the role ID earlier, just check if ANY role condition is set
                # (Partial credit logic handled in python verifier)
                result['condition_match'] = True

print(json.dumps(result))
EOF
)

GW_RESULT=$(python3 -c "$PYTHON_CHECK_SCRIPT")

# Create result JSON
cat > /tmp/task_result.json <<EOF
{
    "role_found": $ROLE_FOUND,
    "role_id": "$ROLE_ID",
    "user_found": $USER_FOUND,
    "user_uid": "${USER_UID:-0}",
    "user_has_role": $USER_HAS_ROLE,
    "gateway_found": $(echo "$GW_RESULT" | jq .found),
    "gateway_label": $(echo "$GW_RESULT" | jq .label),
    "gateway_plugin": $(echo "$GW_RESULT" | jq .plugin),
    "gateway_status": $(echo "$GW_RESULT" | jq .status),
    "instructions_correct": $(echo "$GW_RESULT" | jq .instructions_match),
    "condition_correct": $(echo "$GW_RESULT" | jq .condition_match),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Exported result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="