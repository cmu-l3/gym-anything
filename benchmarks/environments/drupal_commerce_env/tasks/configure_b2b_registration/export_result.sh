#!/bin/bash
# Export script for configure_b2b_registration task
echo "=== Exporting configure_b2b_registration Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Configuration
DRUPAL_ROOT="/var/www/html/drupal"
DRUSH="$DRUPAL_ROOT/vendor/bin/drush"
cd "$DRUPAL_ROOT"

# 1. Check Registration Setting (using Drush)
# Expected: 'visitors'
REGISTER_ACCESS=$($DRUSH config:get user.settings register --format=string 2>/dev/null || echo "unknown")
echo "Registration setting: $REGISTER_ACCESS"

# 2. Check for Field Existence (using Database Schema)
# We check if the data tables have been created
HAS_COMPANY_TABLE="false"
HAS_TAX_TABLE="false"

# Drupal creates tables like user__field_company_name
if drupal_db_query "DESCRIBE user__field_company_name" >/dev/null 2>&1; then
    HAS_COMPANY_TABLE="true"
fi
if drupal_db_query "DESCRIBE user__field_tax_id" >/dev/null 2>&1; then
    HAS_TAX_TABLE="true"
fi
echo "Tables found: Company=$HAS_COMPANY_TABLE, Tax=$HAS_TAX_TABLE"

# 3. Check Form Display Configuration (using Drush)
# We need to verify if the fields are enabled in the 'register' form mode
# We get the full config object and check for the fields in the content array
FORM_DISPLAY_JSON=$($DRUSH config:get core.entity_form_display.user.user.register content --format=json 2>/dev/null || echo "{}")
# Save to temp file for python parsing
echo "$FORM_DISPLAY_JSON" > /tmp/form_display.json

# Parse JSON to check fields
FIELDS_ON_FORM=$(python3 -c "
import json
try:
    data = json.load(open('/tmp/form_display.json'))
    has_company = 'field_company_name' in data
    has_tax = 'field_tax_id' in data
    print(f'{has_company},{has_tax}')
except:
    print('false,false')
")
COMPANY_ON_FORM=$(echo "$FIELDS_ON_FORM" | cut -d',' -f1)
TAX_ON_FORM=$(echo "$FIELDS_ON_FORM" | cut -d',' -f2)
echo "Fields on form: Company=$COMPANY_ON_FORM, Tax=$TAX_ON_FORM"

# 4. Check Test User Data (using Database)
# Look for user 'b2b_user'
TEST_USER_UID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='b2b_user' LIMIT 1")
TEST_USER_EXISTS="false"
USER_COMPANY_VALUE=""
USER_TAX_VALUE=""

if [ -n "$TEST_USER_UID" ]; then
    TEST_USER_EXISTS="true"
    
    # Get Company Name value
    if [ "$HAS_COMPANY_TABLE" = "true" ]; then
        USER_COMPANY_VALUE=$(drupal_db_query "SELECT field_company_name_value FROM user__field_company_name WHERE entity_id=$TEST_USER_UID")
    fi
    
    # Get Tax ID value
    if [ "$HAS_TAX_TABLE" = "true" ]; then
        USER_TAX_VALUE=$(drupal_db_query "SELECT field_tax_id_value FROM user__field_tax_id WHERE entity_id=$TEST_USER_UID")
    fi
fi
echo "Test User: Exists=$TEST_USER_EXISTS, Company='$USER_COMPANY_VALUE', Tax='$USER_TAX_VALUE'"

# 5. Create Result JSON
create_result_json /tmp/task_result.json \
    "register_access=$(json_escape "$REGISTER_ACCESS")" \
    "has_company_table=$HAS_COMPANY_TABLE" \
    "has_tax_table=$HAS_TAX_TABLE" \
    "company_on_form=$COMPANY_ON_FORM" \
    "tax_on_form=$TAX_ON_FORM" \
    "test_user_exists=$TEST_USER_EXISTS" \
    "user_company_value=$(json_escape "$USER_COMPANY_VALUE")" \
    "user_tax_value=$(json_escape "$USER_TAX_VALUE")"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="