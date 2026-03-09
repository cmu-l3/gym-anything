#!/bin/bash
echo "=== Setting up fix_server_validation_errors task ==="

source /workspace/scripts/task_utils.sh

DOMAIN="broken-app.test"
USER="broken-app"
PASS="BrokenApp123!"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure the virtual server exists
if ! virtualmin_domain_exists "$DOMAIN"; then
    echo "Creating $DOMAIN..."
    virtualmin create-domain \
        --domain "$DOMAIN" \
        --pass "$PASS" \
        --unix \
        --dir \
        --webmin \
        --web \
        --dns \
        --mysql 2>&1 | tail -5
else
    echo "$DOMAIN already exists, ensuring clean state..."
    # Reset permissions if they were fixed previously
    chown -R "$USER:$USER" "/home/$USER/public_html" 2>/dev/null || true
    # Restore config if missing
    virtualmin enable-feature --domain "$DOMAIN" --web 2>/dev/null || true
fi

# 2. INTRODUCE CORRUPTIONS

echo "Corrupting server state..."

# Corruption A: Permission Error
# Change ownership of public_html to root (common mistake when using sudo manually)
if [ -d "/home/$USER/public_html" ]; then
    chown -R root:root "/home/$USER/public_html"
    echo "Corruption A applied: public_html owned by root"
fi

# Corruption B: Missing Web Config
# Delete the Apache configuration file
# Virtualmin stores the path in its config, but we'll remove the actual file
APACHE_CONFIG="/etc/apache2/sites-available/${DOMAIN}.conf"
APACHE_LINK="/etc/apache2/sites-enabled/${DOMAIN}.conf"

if [ -f "$APACHE_CONFIG" ]; then
    rm -f "$APACHE_CONFIG"
    rm -f "$APACHE_LINK"
    # Restart Apache so it stops serving the site
    systemctl reload apache2
    echo "Corruption B applied: Apache config deleted"
fi

# 3. Setup Environment for Agent

# Ensure Virtualmin is ready and logged in
ensure_virtualmin_ready

# Navigate to the "Validate Virtual Servers" page to hint at the solution
# validate_form.cgi is the page
navigate_to "https://localhost:10000/virtual-server/validate_form.cgi"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="