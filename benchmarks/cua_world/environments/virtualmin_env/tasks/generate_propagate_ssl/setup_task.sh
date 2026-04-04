#!/bin/bash
set -e
echo "=== Setting up generate_propagate_ssl task ==="

# Load helper functions
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure acmecorp.test exists with SSL enabled
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "GymAnything123!" --unix --dir --web --dns --mail --mysql
fi

echo "Ensuring SSL feature is enabled..."
virtualmin enable-feature --domain acmecorp.test --ssl 2>/dev/null || true

# 2. Generate a "Wrong" certificate initially
# This ensures we can distinguish the agent's work from the initial state.
# We set Organization to "Old Default Inc"
echo "Generating initial placeholder certificate..."
virtualmin generate-cert --domain acmecorp.test --self --o "Old Default Inc" --cn "acmecorp.test" --dest /home/acmecorp/ssl.cert

# 3. Reset System Services to use generic snakeoil certs
# This ensures they are NOT using the acmecorp cert at start
echo "Resetting Webmin/Postfix/Dovecot to system defaults..."

# Generate a generic system cert
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -keyout /tmp/system.key -out /tmp/system.cert \
    -subj "/C=US/ST=System/L=System/O=System Default/CN=virtualmin.gym-anything.local" 2>/dev/null

# Apply to Webmin
cat /tmp/system.key /tmp/system.cert > /etc/webmin/miniserv.pem
systemctl restart webmin

# Apply to Postfix (standard locations on Debian/Ubuntu)
cp /tmp/system.cert /etc/ssl/certs/ssl-cert-snakeoil.pem
cp /tmp/system.key /etc/ssl/private/ssl-cert-snakeoil.key
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
systemctl reload postfix

# Apply to Dovecot
# Dovecot config usually points to snakeoil by default on install
# We force it just in case
sed -i 's|^ssl_cert = <.*|ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem|' /etc/dovecot/conf.d/10-ssl.conf 2>/dev/null || true
sed -i 's|^ssl_key = <.*|ssl_key = </etc/ssl/private/ssl-cert-snakeoil.key|' /etc/dovecot/conf.d/10-ssl.conf 2>/dev/null || true
systemctl reload dovecot

# 4. Prepare Browser
ensure_virtualmin_ready

# Navigate to the domain summary page to start
DOMAIN_ID=$(get_domain_id "acmecorp.test")
navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi?dom=${DOMAIN_ID}"
sleep 5

# 5. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="