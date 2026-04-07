#!/bin/bash
echo "=== Exporting corporate_rebranding_system_config results ==="
source /workspace/scripts/task_utils.sh

# Capture final visual state for debugging and record
take_screenshot /tmp/rebrand_final.png

# 1. Query Settings Table
echo "  Querying settings..."
SITE_NAME=$(snipeit_db_query "SELECT site_name FROM settings WHERE id=1" | tr -d '\n')
DEFAULT_CURRENCY=$(snipeit_db_query "SELECT default_currency FROM settings WHERE id=1" | tr -d '\n')
EMAIL_DOMAIN=$(snipeit_db_query "SELECT email_domain FROM settings WHERE id=1" | tr -d '\n')
DEFAULT_EULA_TEXT=$(snipeit_db_query "SELECT default_eula_text FROM settings WHERE id=1")
SUPPORT_EMAIL=$(snipeit_db_query "SELECT support_email FROM settings WHERE id=1" | tr -d '\n')
SUPPORT_PHONE=$(snipeit_db_query "SELECT support_phone FROM settings WHERE id=1" | tr -d '\n')
SUPPORT_URL=$(snipeit_db_query "SELECT support_url FROM settings WHERE id=1" | tr -d '\n')
AUTO_INCREMENT_PREFIX=$(snipeit_db_query "SELECT auto_increment_prefix FROM settings WHERE id=1" | tr -d '\n')
ALERT_EMAIL=$(snipeit_db_query "SELECT alert_email FROM settings WHERE id=1" | tr -d '\n')

# 2. Query User Table
echo "  Querying user identity..."
JANE_EMAIL=$(snipeit_db_query "SELECT email FROM users WHERE username='jsmith' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# 3. Query Asset Table
# Prefer a NEX- asset that is actually assigned to someone, fallback to unassigned NEX- asset.
echo "  Querying provisioned assets..."
ASSET_DATA=$(snipeit_db_query "SELECT a.asset_tag, u.username FROM assets a LEFT JOIN users u ON a.assigned_to = u.id WHERE a.asset_tag LIKE 'NEX-%' AND a.deleted_at IS NULL ORDER BY (a.assigned_to IS NOT NULL) DESC LIMIT 1")

ASSET_EXISTS="false"
ASSET_TAG=""
ASSET_ASSIGNED_TO_USERNAME=""

if [ -n "$ASSET_DATA" ]; then
    ASSET_EXISTS="true"
    ASSET_TAG=$(echo "$ASSET_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    ASSET_ASSIGNED_TO_USERNAME=$(echo "$ASSET_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
fi

# 4. Construct output JSON safely
echo "  Compiling JSON..."
RESULT_JSON=$(cat << JSONEOF
{
  "settings": {
    "site_name": "$(json_escape "$SITE_NAME")",
    "default_currency": "$(json_escape "$DEFAULT_CURRENCY")",
    "email_domain": "$(json_escape "$EMAIL_DOMAIN")",
    "default_eula_text": "$(json_escape "$DEFAULT_EULA_TEXT")",
    "support_email": "$(json_escape "$SUPPORT_EMAIL")",
    "support_phone": "$(json_escape "$SUPPORT_PHONE")",
    "support_url": "$(json_escape "$SUPPORT_URL")",
    "auto_increment_prefix": "$(json_escape "$AUTO_INCREMENT_PREFIX")",
    "alert_email": "$(json_escape "$ALERT_EMAIL")"
  },
  "jane_email": "$(json_escape "$JANE_EMAIL")",
  "asset_exists": $ASSET_EXISTS,
  "asset_tag": "$(json_escape "$ASSET_TAG")",
  "asset_assigned_username": "$(json_escape "$ASSET_ASSIGNED_TO_USERNAME")"
}
JSONEOF
)

# Use task_utils function to write safely avoiding permission constraints
safe_write_result "/tmp/corporate_rebranding_result.json" "$RESULT_JSON"

echo "Result JSON saved:"
echo "$RESULT_JSON"
echo "=== Export complete ==="