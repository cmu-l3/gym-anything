#!/bin/bash
set -e
echo "=== Setting up install_custom_ssl_cert task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure acmecorp.test exists and has SSL enabled
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --unix --dir --webmin --web --dns --ssl
else
    # Ensure SSL feature is enabled
    virtualmin enable-feature --domain acmecorp.test --ssl || true
fi

# 2. Generate Custom SSL Chain (Root -> Intermediate -> Leaf)
CERT_DIR="/home/ga/Documents/ssl_certs"
mkdir -p "$CERT_DIR"
rm -f "$CERT_DIR"/*

echo "Generating Mock CA Hierarchy..."

# A. Generate Root CA
openssl req -x509 -new -nodes -keyout "$CERT_DIR/root.key" -sha256 -days 1024 \
    -out "$CERT_DIR/root.crt" \
    -subj "/C=US/ST=State/L=City/O=Mock Auth/CN=Global Trusted Mock CA Root"

# B. Generate Intermediate CA
openssl req -new -nodes -keyout "$CERT_DIR/intermediate.key" \
    -out "$CERT_DIR/intermediate.csr" \
    -subj "/C=US/ST=State/L=City/O=Mock Auth/CN=Global Trusted Mock CA Intermediate"

# Sign Intermediate with Root
cat > "$CERT_DIR/v3_ca.ext" <<EOF
basicConstraints = CA:TRUE
keyUsage = digitalSignature, keyCertSign, cRLSign
EOF

openssl x509 -req -in "$CERT_DIR/intermediate.csr" \
    -CA "$CERT_DIR/root.crt" -CAkey "$CERT_DIR/root.key" -CAcreateserial \
    -out "$CERT_DIR/intermediate.crt" -days 500 -sha256 -extfile "$CERT_DIR/v3_ca.ext"

# C. Generate Leaf Certificate (acmecorp.test)
openssl req -new -nodes -keyout "$CERT_DIR/acmecorp.key" \
    -out "$CERT_DIR/acmecorp.csr" \
    -subj "/C=US/ST=State/L=City/O=Acme Corp/CN=acmecorp.test"

# Sign Leaf with Intermediate
openssl x509 -req -in "$CERT_DIR/acmecorp.csr" \
    -CA "$CERT_DIR/intermediate.crt" -CAkey "$CERT_DIR/intermediate.key" -CAcreateserial \
    -out "$CERT_DIR/acmecorp.crt" -days 365 -sha256

# D. Create CA Bundle (Intermediate + Root) - This is what the agent needs to upload as the chain
cat "$CERT_DIR/intermediate.crt" "$CERT_DIR/root.crt" > "$CERT_DIR/ca_bundle.crt"

# Clean up private CA keys so agent can't find them (only leave what they need)
rm "$CERT_DIR/root.key" "$CERT_DIR/intermediate.key" "$CERT_DIR/intermediate.csr" "$CERT_DIR/acmecorp.csr" "$CERT_DIR/v3_ca.ext" "$CERT_DIR/root.srl" "$CERT_DIR/intermediate.srl" "$CERT_DIR/root.crt" "$CERT_DIR/intermediate.crt"

# Set permissions
chown -R ga:ga "$CERT_DIR"
chmod 644 "$CERT_DIR"/*
echo "Certificates prepared in $CERT_DIR"

# 3. Ensure Virtualmin is ready in Firefox
ensure_virtualmin_ready

# 4. Navigate to the SSL page for acmecorp.test
DOM_ID=$(get_domain_id "acmecorp.test")
# Note: In newer Virtualmin, the page is typically reached via the menu.
# We'll land them on the main virtual server page to make them navigate a bit,
# or the specific SSL page if we want to be nice. Let's send them to the SSL page.
navigate_to "https://localhost:10000/virtual-server/edit_ssl.cgi?dom=${DOM_ID}"

# 5. Record start state
date +%s > /tmp/task_start_time.txt
# Capture the initial cert issuer (should be Virtualmin/Self-signed default)
echo | openssl s_client -connect localhost:443 -servername acmecorp.test 2>/dev/null | openssl x509 -noout -issuer > /tmp/initial_issuer.txt || echo "No SSL" > /tmp/initial_issuer.txt

take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="