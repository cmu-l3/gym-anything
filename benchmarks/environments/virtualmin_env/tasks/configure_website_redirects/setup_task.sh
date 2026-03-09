#!/bin/bash
set -e
echo "=== Setting up configure_website_redirects task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure acmecorp.test exists (it should be pre-seeded)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test domain not found. Creating it..."
    virtualmin create-domain --domain acmecorp.test --pass GymAnything123! --unix --dir --webmin --web --dns --mail --mysql
fi

# 3. Clean up any existing redirects for the target paths
echo "Cleaning up existing redirects..."
# We use a loop to ensure we catch them if they exist
for path in "/old-products" "/survey"; do
    if virtualmin list-redirects --domain acmecorp.test --multiline | grep -q "Path: $path"; then
        virtualmin delete-redirect --domain acmecorp.test --path "$path" 2>/dev/null || true
    fi
done

# 4. Ensure local resolution for verification
if ! grep -q "acmecorp.test" /etc/hosts; then
    echo "127.0.0.1 acmecorp.test" >> /etc/hosts
fi

# 5. Record initial Apache config state
APACHE_CONF="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$APACHE_CONF" ]; then
    md5sum "$APACHE_CONF" | awk '{print $1}' > /tmp/initial_apache_config_hash.txt
else
    echo "none" > /tmp/initial_apache_config_hash.txt
fi

# 6. Prepare Browser
ensure_virtualmin_ready
sleep 2

# Navigate specifically to the Website Redirects page for acmecorp.test
# In Virtualmin 7/8, this is usually under Server Configuration -> Website Redirects
# The URL typically involves the domain ID.
ACME_ID=$(get_domain_id "acmecorp.test")

# Note: The exact URL endpoint for redirects might vary by theme, but navigating 
# to the domain's main page is a safe starting point if the specific URL is tricky.
# However, we'll try to get closer. 'redirects.cgi' is common.
URL="${VIRTUALMIN_URL}/virtual-server/redirects.cgi?dom=${ACME_ID}"

echo "Navigating to Redirects page: $URL"
navigate_to "$URL"
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="