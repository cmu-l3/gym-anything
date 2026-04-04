#!/bin/bash
set -e
echo "=== Setting up Fix .htaccess Syntax Error Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

DOMAIN="debug-practice.test"
PASS="Debug!2024"
USER="debug-practice"
ROOT_DIR="/home/$USER/public_html"

# 1. Create the virtual server if it doesn't exist
if ! virtualmin list-domains --name-only | grep -q "^${DOMAIN}$"; then
    echo "Creating virtual server $DOMAIN..."
    virtualmin create-domain \
        --domain "$DOMAIN" \
        --pass "$PASS" \
        --unix --dir --web --dns \
        --desc "Production Site - Debugging Practice"
    sleep 5
fi

# 2. Create the website content
# index.php (The working site)
cat > "$ROOT_DIR/index.php" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>System Status</title></head>
<body>
    <h1>System Operational</h1>
    <p>The application has loaded successfully.</p>
</body>
</html>
EOF

# new-page.php (The redirect target)
cat > "$ROOT_DIR/new-page.php" << 'EOF'
<?php echo "This is the new page."; ?>
EOF

# 3. Create the BROKEN .htaccess file
# We inject a syntax error: "RewritRule" instead of "RewriteRule"
cat > "$ROOT_DIR/.htaccess" << 'EOF'
# Main configuration for debug-practice application
Options +FollowSymLinks
RewriteEngine On

# Redirect legacy traffic
# TODO: Ensure this redirects old-page to new-page.php
RewritRule ^old-page$ new-page.php [R=301,L]

# Prevent directory listing
Options -Indexes
EOF

# 4. Set correct permissions
chown -R "$USER:$USER" "$ROOT_DIR"
chmod 644 "$ROOT_DIR/.htaccess"
chmod 644 "$ROOT_DIR/index.php"
chmod 644 "$ROOT_DIR/new-page.php"

# 5. Ensure Apache reads the .htaccess
# Virtualmin defaults usually allow override, but restarting ensures clean state
systemctl reload apache2

# 6. Verify initial broken state (for debugging logs)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}/")
echo "Initial HTTP Status: $HTTP_CODE (Expected: 500)"

# 7. Setup GUI state
ensure_virtualmin_ready

# Navigate to the domain list to make it easy to start
navigate_to "https://localhost:10000/virtual-server/index.cgi"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete: $DOMAIN is now broken (500 Error) ==="