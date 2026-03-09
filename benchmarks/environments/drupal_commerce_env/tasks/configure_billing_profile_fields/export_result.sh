#!/bin/bash
# Export script for configure_billing_profile_fields task
echo "=== Exporting configure_billing_profile_fields Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

cd /var/www/html/drupal

# ==============================================================================
# 1. Inspect Profile Type Configuration (Label)
# ==============================================================================
# Config object: profile.type.customer
echo "Checking profile label..."
PROFILE_CONFIG=$($DRUSH config:get profile.type.customer --format=json 2>/dev/null || echo "{}")

# ==============================================================================
# 2. Inspect Address Field Configuration (Organization Override)
# ==============================================================================
# Config object: field.field.profile.customer.address
echo "Checking address field configuration..."
ADDRESS_CONFIG=$($DRUSH config:get field.field.profile.customer.address --format=json 2>/dev/null || echo "{}")

# ==============================================================================
# 3. Inspect New Phone Field Storage
# ==============================================================================
# Config object: field.storage.profile.field_contact_phone
echo "Checking new field storage..."
FIELD_STORAGE_CONFIG=$($DRUSH config:get field.storage.profile.field_contact_phone --format=json 2>/dev/null || echo "{}")

# ==============================================================================
# 4. Inspect New Phone Field Instance
# ==============================================================================
# Config object: field.field.profile.customer.field_contact_phone
echo "Checking new field instance..."
FIELD_INSTANCE_CONFIG=$($DRUSH config:get field.field.profile.customer.field_contact_phone --format=json 2>/dev/null || echo "{}")

# ==============================================================================
# 5. Construct Result JSON
# ==============================================================================
# We use Python to merge these JSON objects safely into one result file
# because doing complex JSON manipulation in Bash is error-prone.

python3 -c "
import json
import sys

try:
    profile = json.loads('''$PROFILE_CONFIG''')
except:
    profile = {}

try:
    address = json.loads('''$ADDRESS_CONFIG''')
except:
    address = {}

try:
    storage = json.loads('''$FIELD_STORAGE_CONFIG''')
except:
    storage = {}

try:
    instance = json.loads('''$FIELD_INSTANCE_CONFIG''')
except:
    instance = {}

result = {
    'profile_label': profile.get('label', ''),
    'profile_id': profile.get('id', ''),
    
    # Check field overrides inside settings
    # Structure: settings -> field_overrides -> organization
    'address_settings': address.get('settings', {}),
    
    # Check new field storage
    'field_storage_exists': bool(storage),
    'field_type': storage.get('type', ''),
    'field_storage_status': storage.get('status', False),
    
    # Check new field instance
    'field_instance_exists': bool(instance),
    'field_required': instance.get('required', False),
    'field_label': instance.get('label', '')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions so verify.py (running as ga or root) can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json

echo "=== Export Complete ==="