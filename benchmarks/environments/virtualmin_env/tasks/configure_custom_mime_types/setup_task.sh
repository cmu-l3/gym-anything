#!/bin/bash
echo "=== Setting up configure_custom_mime_types task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous configuration for these types
# We want to ensure the agent actually adds them
echo "Cleaning up previous MIME configurations..."
sed -i '/text\/x-gcode/d' /etc/apache2/sites-available/*.conf /etc/apache2/sites-enabled/*.conf /etc/mime.types 2>/dev/null || true
sed -i '/text\/x-lua/d' /etc/apache2/sites-available/*.conf /etc/apache2/sites-enabled/*.conf /etc/mime.types 2>/dev/null || true

# Reload Apache to ensure clean state
systemctl reload apache2 2>/dev/null || true

# 3. Create test files for verification
# These files will be used by export_result.sh to test headers via curl
echo "Creating test files..."
mkdir -p /home/acmecorp/public_html
echo "G1 X0 Y0" > /home/acmecorp/public_html/verification_test.gcode
echo "print('Hello World')" > /home/acmecorp/public_html/verification_test.lua

# Fix permissions
chown -R acmecorp:acmecorp /home/acmecorp/public_html
chmod 644 /home/acmecorp/public_html/verification_test.*

# 4. Record initial Apache config state
# We'll use this to verify the file was actually modified
APACHE_CONFIG="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$APACHE_CONFIG" ]; then
    cp "$APACHE_CONFIG" /tmp/initial_apache_config.conf
else
    echo "WARNING: Apache config for acmecorp.test not found at expected path"
fi

# 5. Ensure Virtualmin is ready and open in Firefox
ensure_virtualmin_ready

# Navigate to the acmecorp.test domain page to save the agent some clicks
# and ensure they start in the right context
ACMECORP_ID=$(get_domain_id "acmecorp.test")
if [ -n "$ACMECORP_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=${ACMECORP_ID}"
fi

# 6. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="