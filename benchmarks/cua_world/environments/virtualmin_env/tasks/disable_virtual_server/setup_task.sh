#!/bin/bash
echo "=== Setting up disable_virtual_server task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure greenfield-consulting.test exists and is ENABLED
# ---------------------------------------------------------------
echo "--- Ensuring greenfield-consulting.test is active ---"

if ! virtualmin_domain_exists "greenfield-consulting.test"; then
    echo "Creating greenfield-consulting.test..."
    virtualmin create-domain \
        --domain "greenfield-consulting.test" \
        --pass "GreenField2024!" \
        --unix --dir --webmin --web --dns --mail --mysql 2>&1 | tail -5
    sleep 5
fi

# Re-enable the domain if it was previously disabled (idempotency)
virtualmin enable-domain --domain greenfield-consulting.test 2>/dev/null || true
sleep 3

# ---------------------------------------------------------------
# 2. Record initial state (domain should be enabled)
# ---------------------------------------------------------------
echo "--- Recording initial state ---"
virtualmin list-domains --domain greenfield-consulting.test --multiline 2>/dev/null > /tmp/initial_domain_state.txt

# Record that home directory exists
DOMAIN_HOME=$(grep -i "Home directory" /tmp/initial_domain_state.txt | awk '{print $NF}' || echo "/home/greenfield-consulting")
echo "$DOMAIN_HOME" > /tmp/initial_domain_home.txt

# Record initial domain count
virtualmin list-domains --name-only 2>/dev/null | wc -l > /tmp/initial_domain_count.txt

# ---------------------------------------------------------------
# 3. Add realistic content to the domain's website
# ---------------------------------------------------------------
echo "--- Adding web content to domain ---"
# We need to find the home dir dynamically
DOMAIN_HOME_DIR=$(virtualmin list-domains --domain greenfield-consulting.test --multiline | grep "Home directory" | awk '{print $NF}')
if [ -z "$DOMAIN_HOME_DIR" ]; then DOMAIN_HOME_DIR="/home/greenfield-consulting"; fi

PUBLIC_HTML="${DOMAIN_HOME_DIR}/public_html"

if [ -d "$PUBLIC_HTML" ]; then
    cat > "${PUBLIC_HTML}/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Greenfield Consulting</title></head>
<body>
<h1>Welcome to Greenfield Consulting</h1>
<p>Strategic business consulting for the modern enterprise.</p>
<!-- Unique marker for verification -->
<!-- MARKER: ACTIVE_CONTENT_4781 -->
</body>
</html>
HTMLEOF
    
    # Set ownership
    USER_ID=$(stat -c '%U' "$PUBLIC_HTML" 2>/dev/null || echo "root")
    GROUP_ID=$(stat -c '%G' "$PUBLIC_HTML" 2>/dev/null || echo "root")
    chown "$USER_ID:$GROUP_ID" "${PUBLIC_HTML}/index.html" 2>/dev/null || true
fi

# ---------------------------------------------------------------
# 4. Ensure Virtualmin is ready in Firefox
# ---------------------------------------------------------------
echo "--- Ensuring Firefox and Virtualmin are ready ---"

ensure_virtualmin_ready
sleep 3

# Navigate to Virtualmin main page
navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Domain greenfield-consulting.test is ACTIVE and ready to be disabled."