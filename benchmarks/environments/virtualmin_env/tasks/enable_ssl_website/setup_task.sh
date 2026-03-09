#!/bin/bash
set -e
echo "=== Setting up enable_ssl_website task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure acmecorp.test exists (create if missing for some reason)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "AcmeCorp123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# Ensure SSL is NOT currently enabled (disable if it somehow is)
# We check via CLI to be sure
SSL_ENABLED=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep -ci "ssl website" || echo "0")
if [ "$SSL_ENABLED" -gt 0 ]; then
    echo "SSL is currently enabled, disabling for clean task state..."
    virtualmin disable-feature --domain acmecorp.test --ssl 2>/dev/null || true
    sleep 3
fi

# Ensure any previous certificates are removed or backed up to avoid confusion
rm -f /home/acmecorp/ssl.cert /home/acmecorp/ssl.key 2>/dev/null || true

# Record initial state
virtualmin list-domains --domain acmecorp.test --multiline > /tmp/initial_domain_state.txt 2>/dev/null || true
echo "Initial SSL state: NOT enabled" >> /tmp/initial_domain_state.txt

# Ensure services are running
for svc in apache2 webmin; do
    systemctl is-active --quiet "$svc" || systemctl start "$svc" || true
done
sleep 3

# Ensure Firefox is open and logged in to Virtualmin
ensure_virtualmin_ready

# Navigate to the Virtualmin dashboard showing acmecorp.test
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "${VIRTUALMIN_URL}/virtual-server/summary.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
fi
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="