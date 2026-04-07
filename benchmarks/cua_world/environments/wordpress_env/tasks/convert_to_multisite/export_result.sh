#!/bin/bash
# Export script for convert_to_multisite task (post_task hook)

echo "=== Exporting convert_to_multisite result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Configuration files
WP_CONFIG_FILE="/var/www/html/wordpress/wp-config.php"
HTACCESS_FILE="/var/www/html/wordpress/.htaccess"

# ============================================================
# 1. Check wp-config.php directives
# ============================================================
WP_ALLOW_MULTISITE="false"
MULTISITE_CONSTANT="false"
SUBDOMAIN_INSTALL_CORRECT="false"

if grep -iqE "define.*\(.*'WP_ALLOW_MULTISITE'.*,.*true.*\)" "$WP_CONFIG_FILE"; then
    WP_ALLOW_MULTISITE="true"
fi

if grep -iqE "define.*\(.*'MULTISITE'.*,.*true.*\)" "$WP_CONFIG_FILE"; then
    MULTISITE_CONSTANT="true"
fi

# Sub-directory install means SUBDOMAIN_INSTALL is false
if grep -iqE "define.*\(.*'SUBDOMAIN_INSTALL'.*,.*false.*\)" "$WP_CONFIG_FILE"; then
    SUBDOMAIN_INSTALL_CORRECT="true"
fi

echo "WP_ALLOW_MULTISITE: $WP_ALLOW_MULTISITE"
echo "MULTISITE_CONSTANT: $MULTISITE_CONSTANT"
echo "SUBDOMAIN_INSTALL (false): $SUBDOMAIN_INSTALL_CORRECT"

# ============================================================
# 2. Check .htaccess routing rules
# ============================================================
HTACCESS_MULTISITE="false"
# WordPress sub-directory multisite includes specific rules mapping wp-content/admin/includes via a prefix
if grep -iqE "RewriteRule.*\^.*\/?\(?wp-\(content\|admin\|includes\)" "$HTACCESS_FILE" || \
   grep -iqE "RewriteRule.*wp-(content|admin|includes)" "$HTACCESS_FILE"; then
    HTACCESS_MULTISITE="true"
fi
echo "HTACCESS_MULTISITE rules found: $HTACCESS_MULTISITE"

# ============================================================
# 3. Check Database Architecture
# ============================================================
HAS_WP_BLOGS="false"
TABLE_CHECK=$(wp_db_query "SHOW TABLES LIKE 'wp_blogs'")
if [ -n "$TABLE_CHECK" ]; then
    HAS_WP_BLOGS="true"
fi
echo "wp_blogs table exists: $HAS_WP_BLOGS"

# ============================================================
# 4. Check Sub-site Registration & Configuration
# ============================================================
BIOLOGY_EXISTS="false"
BIOLOGY_TITLE=""
BIOLOGY_BLOG_ID=""

if [ "$HAS_WP_BLOGS" = "true" ]; then
    # Look for the biology subsite (path usually starts with /biology/ or biology/)
    BIOLOGY_BLOG_ID=$(wp_db_query "SELECT blog_id FROM wp_blogs WHERE path = '/biology/' OR path = 'biology/' LIMIT 1")
    
    if [ -n "$BIOLOGY_BLOG_ID" ]; then
        BIOLOGY_EXISTS="true"
        echo "Found Biology sub-site with ID: $BIOLOGY_BLOG_ID"
        
        # Determine options table name (usually wp_{id}_options, except for main site which is just wp_options)
        OPTIONS_TABLE="wp_${BIOLOGY_BLOG_ID}_options"
        
        # Get the sub-site title
        BIOLOGY_TITLE=$(wp_db_query "SELECT option_value FROM $OPTIONS_TABLE WHERE option_name='blogname' LIMIT 1")
        echo "Biology sub-site title: $BIOLOGY_TITLE"
    else
        echo "Biology sub-site NOT found in wp_blogs"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "wp_allow_multisite": $WP_ALLOW_MULTISITE,
    "multisite_constant": $MULTISITE_CONSTANT,
    "subdomain_install_correct": $SUBDOMAIN_INSTALL_CORRECT,
    "htaccess_multisite": $HTACCESS_MULTISITE,
    "has_wp_blogs": $HAS_WP_BLOGS,
    "biology_exists": $BIOLOGY_EXISTS,
    "biology_title": "$(echo "$BIOLOGY_TITLE" | sed 's/"/\\"/g' | tr -d '\n')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/multisite_result.json 2>/dev/null || sudo rm -f /tmp/multisite_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multisite_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/multisite_result.json
chmod 666 /tmp/multisite_result.json 2>/dev/null || sudo chmod 666 /tmp/multisite_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/multisite_result.json"
cat /tmp/multisite_result.json
echo ""
echo "=== Export complete ==="