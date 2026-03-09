#!/bin/bash
echo "=== Setting up configure_directory_alias task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare the external directory and data
DATA_DIR="/var/acme_marketing"
echo "Creating data directory at $DATA_DIR..."
mkdir -p "$DATA_DIR"

# Create the test file with specific content
cat > "$DATA_DIR/press_kit_v1.txt" << 'EOF'
AcmeCorp Official Press Kit - Q3 2024
-------------------------------------
This document contains confidential branding assets.
Copyright 2024 AcmeCorp.
EOF

# Set permissions so Apache can read it (755 for dir, 644 for file)
# Owned by root to simulate a system mount/shared folder
chown -R root:root "$DATA_DIR"
chmod 755 "$DATA_DIR"
chmod 644 "$DATA_DIR/press_kit_v1.txt"

echo "Data prepared: $DATA_DIR/press_kit_v1.txt"

# 2. Ensure acmecorp.test exists (it should from env setup, but verify)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test domain..."
    # Create with default password if missing
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --web --dns --unix --dir
fi

# 3. Clean up any previous aliases/redirects for /marketing
echo "Cleaning up existing configuration..."
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$CONF_FILE" ]; then
    # Remove lines containing "Alias /marketing" or "Redirect .* /marketing"
    # Using a temporary file to avoid complex sed escaping issues
    grep -v "/marketing" "$CONF_FILE" > "$CONF_FILE.tmp"
    mv "$CONF_FILE.tmp" "$CONF_FILE"
    
    # Reload Apache to apply clean state
    systemctl reload apache2
fi

# 4. Record start time and initial config state
date +%s > /tmp/task_start_time.txt
stat -c %Y "$CONF_FILE" > /tmp/initial_config_mtime.txt

# 5. Launch Firefox and log in
ensure_virtualmin_ready

# Navigate to the acmecorp.test virtual server dashboard
# Get domain ID for direct navigation
DOM_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOM_ID" ]; then
    # Navigate to "Aliases and Redirects" page to be helpful
    # URL structure for Virtualmin 7/8
    navigate_to "https://localhost:10000/virtual-server/list_redirects.cgi?dom=$DOM_ID"
else
    # Fallback to main page
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi

# 6. Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="