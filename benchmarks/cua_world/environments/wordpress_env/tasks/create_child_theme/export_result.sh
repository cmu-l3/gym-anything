#!/bin/bash
# Export script for create_child_theme task (post_task hook)

echo "=== Exporting create_child_theme result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
THEME_DIR="/var/www/html/wordpress/wp-content/themes/flavor-starter"
PARENT_THEME_DIR="/var/www/html/wordpress/wp-content/themes/twentytwentyfour"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# Check File System
# ============================================================
CHILD_THEME_EXISTS="false"
PARENT_THEME_EXISTS="false"
STYLE_CSS_EXISTS="false"
FUNCTIONS_PHP_EXISTS="false"
STYLE_CSS_CONTENT=""
FUNCTIONS_PHP_CONTENT=""
FILES_CREATED_DURING_TASK="false"

if [ -d "$PARENT_THEME_DIR" ]; then
    PARENT_THEME_EXISTS="true"
fi

if [ -d "$THEME_DIR" ]; then
    CHILD_THEME_EXISTS="true"
    
    if [ -f "$THEME_DIR/style.css" ]; then
        STYLE_CSS_EXISTS="true"
        # Read content and escape for JSON (up to 5000 chars)
        STYLE_CSS_CONTENT=$(head -c 5000 "$THEME_DIR/style.css" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ' | tr -d '\r')
        
        # Timestamp check
        MTIME=$(stat -c %Y "$THEME_DIR/style.css" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK="true"
        fi
    fi
    
    if [ -f "$THEME_DIR/functions.php" ]; then
        FUNCTIONS_PHP_EXISTS="true"
        # Read content and escape for JSON (up to 5000 chars)
        FUNCTIONS_PHP_CONTENT=$(head -c 5000 "$THEME_DIR/functions.php" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ' | tr -d '\r')
    fi
fi

# ============================================================
# Check Database & WordPress State
# ============================================================
ACTIVE_STYLESHEET=$(wp_cli option get stylesheet 2>/dev/null || echo "")
ACTIVE_TEMPLATE=$(wp_cli option get template 2>/dev/null || echo "")

# Get Customizer CSS for the child theme (if agent used Customizer instead of style.css)
DB_CUSTOM_CSS=""
if [ "$ACTIVE_STYLESHEET" = "flavor-starter" ]; then
    DB_CUSTOM_CSS=$(wp_db_query "SELECT post_content FROM wp_posts WHERE post_type='custom_css' AND post_name='flavor-starter' ORDER BY ID DESC LIMIT 1" 2>/dev/null)
    DB_CUSTOM_CSS=$(echo "$DB_CUSTOM_CSS" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ' | tr -d '\r')
fi

# ============================================================
# Check Site Health (HTTP 200)
# ============================================================
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "child_theme_exists": $CHILD_THEME_EXISTS,
    "parent_theme_exists": $PARENT_THEME_EXISTS,
    "style_css_exists": $STYLE_CSS_EXISTS,
    "functions_php_exists": $FUNCTIONS_PHP_EXISTS,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "style_css_content": "$STYLE_CSS_CONTENT",
    "functions_php_content": "$FUNCTIONS_PHP_CONTENT",
    "active_stylesheet": "$ACTIVE_STYLESHEET",
    "active_template": "$ACTIVE_TEMPLATE",
    "db_custom_css": "$DB_CUSTOM_CSS",
    "http_status": "$HTTP_STATUS",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/create_child_theme_result.json 2>/dev/null || sudo rm -f /tmp/create_child_theme_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_child_theme_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_child_theme_result.json
chmod 666 /tmp/create_child_theme_result.json 2>/dev/null || sudo chmod 666 /tmp/create_child_theme_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/create_child_theme_result.json"
echo "=== Export complete ==="