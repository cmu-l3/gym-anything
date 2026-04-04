#!/bin/bash
set -e
echo "=== Setting up configure_python_cgi task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure the target domain exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    create_vserver "acmecorp.test" "AcmeCorp123!"
fi

# 2. Reset CGI configuration (ensure .py is NOT executable)
# We modify the Apache config to ensure AddHandler cgi-script doesn't include .py
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$CONF_FILE" ]; then
    # Remove .py from any AddHandler cgi-script lines
    sed -i 's/\.py//g' "$CONF_FILE"
    # Ensure changes take effect
    systemctl reload apache2
fi

# 3. Create a test Python script
TEST_SCRIPT="/home/acmecorp/public_html/agent_test.py"
cat > "$TEST_SCRIPT" << 'EOF'
#!/usr/bin/python3
print("Content-type: text/plain\n\nVERIFICATION_SUCCESS_TOKEN_8392")
EOF

# Set permissions (chmod +x is usually needed for CGI, but we want the agent to handle config)
# We set it to 755 so permission isn't the blocker, just the server config
chmod 755 "$TEST_SCRIPT"
chown acmecorp:acmecorp "$TEST_SCRIPT"

# 4. Verify initial "broken" state
echo "Verifying initial state (should fail execution)..."
INITIAL_RESPONSE=$(curl -s "http://acmecorp.test/agent_test.py" || true)
if echo "$INITIAL_RESPONSE" | grep -q "VERIFICATION_SUCCESS_TOKEN_8392" && ! echo "$INITIAL_RESPONSE" | grep -q "print"; then
    echo "WARNING: Script executed unexpectedly in setup. Environment might be dirty."
else
    echo "Initial state confirmed: Script did not execute properly."
fi

# 5. Prepare the browser
ensure_virtualmin_ready

# Navigate to the target domain's dashboard to save the agent some clicks
# We need the domain ID for the URL
DOM_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOM_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=$DOM_ID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="