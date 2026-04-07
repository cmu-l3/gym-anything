#!/bin/bash
echo "=== Exporting corporate_rebranding_policy_rollout results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Extract Settings
echo "Querying settings table..."
SITE_NAME=$(snipeit_db_query "SELECT COALESCE(site_name, '') FROM settings WHERE id=1" | tr -d '\n')
CURRENCY=$(snipeit_db_query "SELECT COALESCE(default_currency, '') FROM settings WHERE id=1" | tr -d '\n')
EMAIL=$(snipeit_db_query "SELECT COALESCE(support_email, '') FROM settings WHERE id=1" | tr -d '\n')
COLOR=$(snipeit_db_query "SELECT COALESCE(header_color, '') FROM settings WHERE id=1" | tr -d '\n')

# 2. Extract Category Policies
echo "Querying category policies..."
LAPTOP_ACC=$(snipeit_db_query "SELECT COALESCE(require_acceptance, 0) FROM categories WHERE name='Laptops'" | tr -d '\n')
LAPTOP_EMAIL=$(snipeit_db_query "SELECT COALESCE(checkin_email, 0) FROM categories WHERE name='Laptops'" | tr -d '\n')

TABLET_ACC=$(snipeit_db_query "SELECT COALESCE(require_acceptance, 0) FROM categories WHERE name='Tablets'" | tr -d '\n')
TABLET_EMAIL=$(snipeit_db_query "SELECT COALESCE(checkin_email, 0) FROM categories WHERE name='Tablets'" | tr -d '\n')

DESKTOP_ACC=$(snipeit_db_query "SELECT COALESCE(require_acceptance, 0) FROM categories WHERE name='Desktops'" | tr -d '\n')
DESKTOP_EMAIL=$(snipeit_db_query "SELECT COALESCE(checkin_email, 0) FROM categories WHERE name='Desktops'" | tr -d '\n')

# Provide defaults if queries failed
LAPTOP_ACC=${LAPTOP_ACC:-0}
LAPTOP_EMAIL=${LAPTOP_EMAIL:-0}
TABLET_ACC=${TABLET_ACC:-0}
TABLET_EMAIL=${TABLET_EMAIL:-0}
DESKTOP_ACC=${DESKTOP_ACC:-0}
DESKTOP_EMAIL=${DESKTOP_EMAIL:-0}

# 3. Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "settings": {
    "site_name": "$(json_escape "$SITE_NAME")",
    "currency": "$(json_escape "$CURRENCY")",
    "email": "$(json_escape "$EMAIL")",
    "color": "$(json_escape "$COLOR")"
  },
  "categories": {
    "laptops": {
      "require_acceptance": "$LAPTOP_ACC",
      "checkin_email": "$LAPTOP_EMAIL"
    },
    "tablets": {
      "require_acceptance": "$TABLET_ACC",
      "checkin_email": "$TABLET_EMAIL"
    },
    "desktops": {
      "require_acceptance": "$DESKTOP_ACC",
      "checkin_email": "$DESKTOP_EMAIL"
    }
  }
}
JSONEOF
)

safe_write_result "/tmp/corporate_rebranding_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/corporate_rebranding_result.json"
echo "$RESULT_JSON"
echo "=== corporate_rebranding_policy_rollout export complete ==="