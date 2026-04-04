#!/bin/bash
echo "=== Setting up switch_php_fpm task ==="

source /workspace/scripts/task_utils.sh

# 1. Install PHP-FPM if not present (idempotent)
if ! dpkg -l | grep -q php.*-fpm; then
    echo "Installing PHP-FPM..."
    apt-get update && apt-get install -y php-fpm
fi

# 2. Ensure greenleaf.test exists
if ! virtualmin_domain_exists "greenleaf.test"; then
    echo "Creating greenleaf.test..."
    # Create with default settings using a helper or raw command
    virtualmin create-domain --domain greenleaf.test --pass "GreenLeaf123!" --unix --dir --webmin --web --dns --mysql
fi

# 3. Reset PHP mode to CGI (FCGID or CGI wrapper) to ensure task is meaningful
echo "Resetting PHP mode to CGI/FCGID..."
# We try to set it to 'fcgid' or 'cgi' depending on what's available, 
# ensuring it is NOT fpm.
virtualmin modify-web --domain greenleaf.test --mode fcgid 2>/dev/null || \
virtualmin modify-web --domain greenleaf.test --mode cgi 2>/dev/null || true

# 4. Create a PHP info file for verification
echo "Creating phpinfo.php..."
cat > /home/greenleaf/public_html/phpinfo.php <<EOF
<?php
phpinfo();
?>
EOF
chown greenleaf:greenleaf /home/greenleaf/public_html/phpinfo.php
chmod 644 /home/greenleaf/public_html/phpinfo.php

# 5. Record initial state
INITIAL_MODE=$(virtualmin list-domains --domain greenleaf.test --multiline | grep "PHP execution mode" | awk '{print $NF}')
echo "Initial PHP mode: $INITIAL_MODE"
echo "$INITIAL_MODE" > /tmp/initial_php_mode.txt
date +%s > /tmp/task_start_time.txt

# 6. Prepare Browser
ensure_virtualmin_ready
sleep 2

# Navigate to "Website Options" for greenleaf.test
# finding the specific URL for "Website Options" can vary, but usually involves the domain ID
DOM_ID=$(get_domain_id "greenleaf.test")
navigate_to "https://localhost:10000/virtual-server/edit_phpmode.cgi?dom=${DOM_ID}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="