#!/bin/bash
# Export script for Store Operations Config task

echo "=== Exporting Store Operations Config Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the core_config_data table for the specific paths
# We look for scope='default' (scope_id=0)

# Function to get config value
get_config() {
    local path="$1"
    # Returns value or empty string if not found
    magento_query "SELECT value FROM core_config_data WHERE path='$path' AND scope='default' LIMIT 1" 2>/dev/null | tail -1
}

echo "Querying configuration values..."

# 1. Persistent Cart
PERSISTENT_ENABLED=$(get_config "persistent/options/enabled")
PERSISTENT_LIFETIME=$(get_config "persistent/options/lifetime")
REMEMBER_ENABLED=$(get_config "persistent/options/remember_enabled")
LOGOUT_CLEAR=$(get_config "persistent/options/logout_clear")
PERSIST_SHOPPING_CART=$(get_config "persistent/options/shopping_cart") # Usually 'persistent/options/shopping_cart' stores 'Persist Shopping Cart' (0/1)

# 2. Newsletter
GUEST_SUBSCRIBE=$(get_config "newsletter/subscription/allow_guest_subscribe")

# 3. Contact Us
CONTACT_EMAIL=$(get_config "contact/email/recipient_email")

# 4. Wishlist
WISHLIST_ACTIVE=$(get_config "wishlist/general/active")

echo "Values retrieved:"
echo "  persistent_enabled: $PERSISTENT_ENABLED"
echo "  persistent_lifetime: $PERSISTENT_LIFETIME"
echo "  remember_enabled: $REMEMBER_ENABLED"
echo "  logout_clear: $LOGOUT_CLEAR"
echo "  persist_cart: $PERSIST_SHOPPING_CART"
echo "  guest_subscribe: $GUEST_SUBSCRIBE"
echo "  contact_email: $CONTACT_EMAIL"
echo "  wishlist_active: $WISHLIST_ACTIVE"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/store_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "persistent_enabled": "${PERSISTENT_ENABLED:-0}",
    "persistent_lifetime": "${PERSISTENT_LIFETIME:-0}",
    "remember_enabled": "${REMEMBER_ENABLED:-0}",
    "logout_clear": "${LOGOUT_CLEAR:-1}",
    "persist_shopping_cart": "${PERSIST_SHOPPING_CART:-0}",
    "allow_guest_subscribe": "${GUEST_SUBSCRIBE:-0}",
    "contact_email": "${CONTACT_EMAIL:-}",
    "wishlist_active": "${WISHLIST_ACTIVE:-1}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/store_config_result.json

echo ""
cat /tmp/store_config_result.json
echo ""
echo "=== Export Complete ==="