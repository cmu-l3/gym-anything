#!/bin/bash
set -e
echo "=== Setting up task: configure_browser_caching ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Domain Exists
# (The environment setup creates acmecorp.test, but we wait to be sure)
echo "Waiting for Virtualmin domain acmecorp.test..."
for i in {1..30}; do
    if virtualmin_domain_exists "acmecorp.test"; then
        echo "Domain found."
        break
    fi
    sleep 2
done

if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test not found. Attempting to create..."
    # Fallback creation if env didn't do it
    virtualmin create-domain --domain acmecorp.test --pass GymAnything123! --unix --dir --webmin --web --dns --mysql
fi

# 2. Disable mod_expires if it is enabled (to force agent to enable it)
echo "Ensuring mod_expires is disabled..."
if apache2ctl -M 2>/dev/null | grep -q "expires_module"; then
    a2dismod -f expires > /dev/null || true
    systemctl restart apache2
    echo "mod_expires disabled."
fi

# 3. Clear any existing Expires configuration in the virtual host
echo "Cleaning existing config..."
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$CONF_FILE" ]; then
    # Remove lines containing Expires
    sed -i '/Expires/d' "$CONF_FILE"
    systemctl reload apache2 || true
fi

# 4. Create a test CSS file
echo "Creating test asset..."
cat > /home/acmecorp/public_html/cache_test.css <<EOF
/* Test CSS for Browser Caching Task */
body { background-color: #f0f0f0; }
h1 { color: #333; }
EOF
chown acmecorp:acmecorp /home/acmecorp/public_html/cache_test.css
chmod 644 /home/acmecorp/public_html/cache_test.css

# 5. GUI Setup: Launch Firefox and log in
ensure_virtualmin_ready

# Navigate to the acmecorp.test summary page to start
# (Need numeric ID for Virtualmin 8 URLs usually, but let's try to land on the domain list or summary)
# Using the search/list page is safer if ID is unknown, but we have a helper.
DOM_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOM_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=${DOM_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/"
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="