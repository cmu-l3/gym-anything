#!/bin/bash
echo "=== Exporting whitelabel_wp_login result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

MU_PLUGINS_DIR="/var/www/html/wordpress/wp-content/mu-plugins"
MU_PLUGINS_EXISTS="false"
PHP_FILE_EXISTS="false"
PHP_FILE_COUNT=0

if [ -d "$MU_PLUGINS_DIR" ]; then
    MU_PLUGINS_EXISTS="true"
    PHP_FILE_COUNT=$(find "$MU_PLUGINS_DIR" -maxdepth 1 -name "*.php" | wc -l)
    if [ "$PHP_FILE_COUNT" -gt 0 ]; then
        PHP_FILE_EXISTS="true"
    fi
fi

# Fetch the login page HTML
LOGIN_HTML=$(curl -s http://localhost/wp-login.php 2>/dev/null)
echo "$LOGIN_HTML" > /tmp/wp_login_html.txt
chmod 666 /tmp/wp_login_html.txt

LOGO_IN_HTML="false"
if echo "$LOGIN_HTML" | grep -qi "client-logo.png"; then
    LOGO_IN_HTML="true"
fi

BG_COLOR_IN_HTML="false"
if echo "$LOGIN_HTML" | grep -qi "1e293b"; then
    BG_COLOR_IN_HTML="true"
fi

LOGO_LINK_LOCALHOST="false"
if echo "$LOGIN_HTML" | grep -i "<div id=\"login\">" -A 10 | grep -i "<a href=" | grep -qi "http://localhost"; then
    LOGO_LINK_LOCALHOST="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mu_plugins_exists": $MU_PLUGINS_EXISTS,
    "php_file_exists": $PHP_FILE_EXISTS,
    "php_file_count": $PHP_FILE_COUNT,
    "logo_in_html": $LOGO_IN_HTML,
    "bg_color_in_html": $BG_COLOR_IN_HTML,
    "logo_link_localhost": $LOGO_LINK_LOCALHOST,
    "html_file_path": "/tmp/wp_login_html.txt",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/whitelabel_wp_login_result.json 2>/dev/null || sudo rm -f /tmp/whitelabel_wp_login_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/whitelabel_wp_login_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/whitelabel_wp_login_result.json
chmod 666 /tmp/whitelabel_wp_login_result.json 2>/dev/null || sudo chmod 666 /tmp/whitelabel_wp_login_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="