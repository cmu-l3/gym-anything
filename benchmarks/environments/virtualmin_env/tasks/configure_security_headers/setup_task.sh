#!/bin/bash
echo "=== Setting up configure_security_headers task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure 'headers' module is enabled in Apache
echo "Enabling mod_headers..."
a2enmod headers > /dev/null 2>&1

# 2. Locate the config file for globex.test
# In Virtualmin/Ubuntu, typically /etc/apache2/sites-available/globex.test.conf
CONFIG_FILE=$(grep -l "ServerName globex.test" /etc/apache2/sites-available/*.conf | head -n 1)

if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: Config file for globex.test not found!"
    # Fallback: ensure domain exists (should be pre-seeded, but just in case)
    if ! virtualmin list-domains --name-only | grep -q "^globex.test$"; then
         virtualmin create-domain --domain globex.test --pass "Globex123!" --web --dns --mysql
    fi
    CONFIG_FILE=$(grep -l "ServerName globex.test" /etc/apache2/sites-available/*.conf | head -n 1)
fi

echo "Target config file: $CONFIG_FILE"

# 3. Clean state: Remove any existing security headers from the config
if [ -f "$CONFIG_FILE" ]; then
    echo "Cleaning existing headers from config..."
    # Remove lines containing our target headers (case insensitive)
    sed -i '/Header.*X-Content-Type-Options/Id' "$CONFIG_FILE"
    sed -i '/Header.*X-Frame-Options/Id' "$CONFIG_FILE"
    sed -i '/Header.*Strict-Transport-Security/Id' "$CONFIG_FILE"
fi

# 4. Restart Apache to apply clean state
systemctl restart apache2

# 5. Record initial state for anti-gaming
date +%s > /tmp/task_start_time.txt
md5sum "$CONFIG_FILE" > /tmp/initial_config_hash.txt

# Record initial headers (should be empty of our targets)
curl -sk -I --resolve "globex.test:443:127.0.0.1" https://globex.test/ > /tmp/initial_curl_headers.txt 2>&1

# 6. Prepare UI
ensure_virtualmin_ready
sleep 2

# Navigate to globex.test dashboard to save agent time
# Get domain ID for URL navigation
DOM_ID=$(get_domain_id "globex.test")
if [ -n "$DOM_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=${DOM_ID}"
else
    # Fallback to main page if ID look up fails
    navigate_to "https://localhost:10000/"
fi
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="