#!/bin/bash
# Export script for create_navigation_menu task (post_task hook)

echo "=== Exporting create_navigation_menu result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check if the menu exists
echo "Checking for menu 'Main Navigation'..."
MENU_TERM_ID=$(wp menu list --fields=term_id,name --format=csv --allow-root 2>/dev/null | grep -i "Main Navigation" | cut -d, -f1 | head -1)

MENU_EXISTS="false"
MENU_ITEMS_JSON="[]"

if [ -n "$MENU_TERM_ID" ]; then
    MENU_EXISTS="true"
    echo "Found menu with Term ID: $MENU_TERM_ID"
    
    # 2. Get all menu items as JSON
    # Fields returned by default: db_id, type, object_id, object, url, title, position, menu_item_parent
    MENU_ITEMS_JSON=$(wp menu item list "$MENU_TERM_ID" --format=json --allow-root 2>/dev/null || echo "[]")
else
    echo "Menu 'Main Navigation' not found."
fi

# 3. Get theme modifications (to check menu location assignment)
echo "Fetching theme modifications for location assignment..."
THEME_MODS_JSON=$(wp option get theme_mods_twentytwentyone --format=json --allow-root 2>/dev/null || echo "{}")

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "menu_exists": $MENU_EXISTS,
    "menu_term_id": "$MENU_TERM_ID",
    "menu_items": $MENU_ITEMS_JSON,
    "theme_mods": $THEME_MODS_JSON,
    "timestamp": "$(date +%s)"
}
EOF

# Move to final location safely
rm -f /tmp/create_navigation_menu_result.json 2>/dev/null || sudo rm -f /tmp/create_navigation_menu_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_navigation_menu_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_navigation_menu_result.json
chmod 666 /tmp/create_navigation_menu_result.json 2>/dev/null || sudo chmod 666 /tmp/create_navigation_menu_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/create_navigation_menu_result.json"
echo "=== Export complete ==="