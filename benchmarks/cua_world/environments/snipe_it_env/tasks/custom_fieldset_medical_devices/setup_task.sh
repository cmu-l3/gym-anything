#!/bin/bash
echo "=== Setting up custom_fieldset_medical_devices task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing records from previous runs to ensure idempotency
echo "Cleaning up any existing target entities..."

# Remove Asset
snipeit_db_query "DELETE FROM assets WHERE asset_tag='MED-001'"
# Remove Model
snipeit_db_query "DELETE FROM models WHERE name='GE Carescape B650'"
# Remove Manufacturer
snipeit_db_query "DELETE FROM manufacturers WHERE name='GE Healthcare'"
# Remove Category
snipeit_db_query "DELETE FROM categories WHERE name='Medical Devices'"
# Remove Custom Fieldset Associations
snipeit_db_query "DELETE FROM custom_field_custom_fieldset WHERE custom_fieldset_id IN (SELECT id FROM custom_fieldsets WHERE name='Medical Device Compliance')"
snipeit_db_query "DELETE FROM custom_field_custom_fieldset WHERE custom_field_id IN (SELECT id FROM custom_fields WHERE name IN ('FDA 510(k) Number', 'Next Calibration Due', 'Patient Contact Class', 'Biomedical Cert Expiry'))"
# Remove Fieldset
snipeit_db_query "DELETE FROM custom_fieldsets WHERE name='Medical Device Compliance'"
# Remove Fields
snipeit_db_query "DELETE FROM custom_fields WHERE name IN ('FDA 510(k) Number', 'Next Calibration Due', 'Patient Contact Class', 'Biomedical Cert Expiry')"

# 2. Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2

# Navigate to the Snipe-IT dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="