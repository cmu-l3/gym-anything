#!/bin/bash
# Export script for docker_tls_mtls_setup task

echo "=== Exporting mTLS Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/tls-setup"
CERTS_DIR="$PROJECT_DIR/certs"

# 1. Check Project Structure & Files
HAS_PROJECT_DIR=0
[ -d "$PROJECT_DIR" ] && HAS_PROJECT_DIR=1

HAS_CA_KEY=0; HAS_CA_CRT=0
HAS_SERVER_KEY=0; HAS_SERVER_CRT=0
HAS_CLIENT_KEY=0; HAS_CLIENT_CRT=0

[ -f "$CERTS_DIR/ca.key" ] && HAS_CA_KEY=1
[ -f "$CERTS_DIR/ca.crt" ] && HAS_CA_CRT=1
[ -f "$CERTS_DIR/server.key" ] && HAS_SERVER_KEY=1
[ -f "$CERTS_DIR/server.crt" ] && HAS_SERVER_CRT=1
[ -f "$CERTS_DIR/client.key" ] && HAS_CLIENT_KEY=1
[ -f "$CERTS_DIR/client.crt" ] && HAS_CLIENT_CRT=1

# Check file timestamps (anti-gaming)
FILES_CREATED_DURING_TASK=1
for f in ca.crt server.crt client.crt; do
    if [ -f "$CERTS_DIR/$f" ]; then
        MTIME=$(stat -c %Y "$CERTS_DIR/$f")
        if [ "$MTIME" -lt "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK=0
        fi
    fi
done

# 2. OpenSSL Verification (Chain of Trust)
CA_VALID=0
SERVER_SIGNED_BY_CA=0
CLIENT_SIGNED_BY_CA=0
SERVER_HAS_SAN=0

if [ "$HAS_CA_CRT" -eq 1 ]; then
    # Verify CA subject
    if openssl x509 -in "$CERTS_DIR/ca.crt" -noout -subject | grep -q "AcmeCorp Internal CA"; then
        CA_VALID=1
    fi
fi

if [ "$HAS_CA_CRT" -eq 1 ] && [ "$HAS_SERVER_CRT" -eq 1 ]; then
    if openssl verify -CAfile "$CERTS_DIR/ca.crt" "$CERTS_DIR/server.crt" | grep -q "OK"; then
        SERVER_SIGNED_BY_CA=1
    fi
    # Check SAN
    if openssl x509 -in "$CERTS_DIR/server.crt" -noout -text | grep -q "DNS:acme-gateway"; then
        SERVER_HAS_SAN=1
    fi
fi

if [ "$HAS_CA_CRT" -eq 1 ] && [ "$HAS_CLIENT_CRT" -eq 1 ]; then
    if openssl verify -CAfile "$CERTS_DIR/ca.crt" "$CERTS_DIR/client.crt" | grep -q "OK"; then
        CLIENT_SIGNED_BY_CA=1
    fi
fi

# 3. Docker Infrastructure Check
NETWORK_EXISTS=0
if docker network inspect acme-tls-net >/dev/null 2>&1; then
    NETWORK_EXISTS=1
fi

CONTAINER_RUNNING=0
CONTAINER_IMAGE=""
if docker ps --format '{{.Names}}' | grep -q "^acme-gateway$"; then
    CONTAINER_RUNNING=1
    CONTAINER_IMAGE=$(docker inspect acme-gateway --format '{{.Config.Image}}')
fi

# 4. Functional mTLS Verification (The real test)
MTLS_REJECTS_NO_CERT=0
MTLS_ACCEPTS_CERT=0
CURL_OUTPUT=""

if [ "$CONTAINER_RUNNING" -eq 1 ] && [ "$NETWORK_EXISTS" -eq 1 ]; then
    # Launch a temporary client container attached to the same network
    # We mount the certs to it to perform the curl test
    
    # Test 1: No Cert (Should fail 400 or 403 or handshake fail)
    HTTP_CODE_NO_CERT=$(docker run --rm --net acme-tls-net \
        -v "$CERTS_DIR":/certs \
        alpine:3.19 sh -c "apk add --no-cache curl >/dev/null; \
        curl -k -s -o /dev/null -w '%{http_code}' https://acme-gateway" || echo "000")
    
    # We expect 400 (No required SSL certificate was sent) or 403 or 000 (if connection reset)
    # Nginx usually sends 400 Bad Request for missing cert if ssl_verify_client is on
    if [ "$HTTP_CODE_NO_CERT" = "400" ] || [ "$HTTP_CODE_NO_CERT" = "403" ] || [ "$HTTP_CODE_NO_CERT" = "000" ]; then
        MTLS_REJECTS_NO_CERT=1
    fi

    # Test 2: With Cert (Should succeed 200)
    # Note: We use -k (insecure) for the server cert verification here because we might not trust the CA in the alpine root store,
    # BUT we are testing if the SERVER accepts OUR client cert.
    # To be strictly correct, we should also verify the server cert, but the critical part of this task is mTLS (server authenticating client).
    HTTP_CODE_CERT=$(docker run --rm --net acme-tls-net \
        -v "$CERTS_DIR":/certs \
        alpine:3.19 sh -c "apk add --no-cache curl >/dev/null; \
        curl -s -o /dev/null -w '%{http_code}' --cert /certs/client.crt --key /certs/client.key -k https://acme-gateway" || echo "000")
        
    if [ "$HTTP_CODE_CERT" = "200" ]; then
        MTLS_ACCEPTS_CERT=1
    fi
fi

# 5. Documentation Checks
VERIFICATION_FILE="/home/ga/Desktop/tls_verification.txt"
DOC_FILE="/home/ga/Desktop/pki_documentation.txt"

VERIF_FILE_EXISTS=0
VERIF_CONTENT_VALID=0
if [ -f "$VERIFICATION_FILE" ]; then
    VERIF_FILE_EXISTS=1
    if grep -q "200" "$VERIFICATION_FILE" || grep -q "mTLS OK" "$VERIFICATION_FILE"; then
        VERIF_CONTENT_VALID=1
    fi
fi

DOC_FILE_EXISTS=0
DOC_CONTENT_VALID=0
if [ -f "$DOC_FILE" ]; then
    DOC_FILE_EXISTS=1
    # Check for keywords
    KEYWORDS=$(grep -Ei "CA|Authority|Certificate|Rotation|Expire" "$DOC_FILE" | wc -l)
    if [ "$KEYWORDS" -ge 2 ]; then
        DOC_CONTENT_VALID=1
    fi
fi

# Export to JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start_time": $TASK_START,
    "has_project_dir": $HAS_PROJECT_DIR,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "has_ca_pair": $((HAS_CA_KEY * HAS_CA_CRT)),
    "has_server_pair": $((HAS_SERVER_KEY * HAS_SERVER_CRT)),
    "has_client_pair": $((HAS_CLIENT_KEY * HAS_CLIENT_CRT)),
    "ca_valid": $CA_VALID,
    "server_signed_by_ca": $SERVER_SIGNED_BY_CA,
    "client_signed_by_ca": $CLIENT_SIGNED_BY_CA,
    "server_has_san": $SERVER_HAS_SAN,
    "network_exists": $NETWORK_EXISTS,
    "container_running": $CONTAINER_RUNNING,
    "mtls_rejects_no_cert": $MTLS_REJECTS_NO_CERT,
    "mtls_accepts_cert": $MTLS_ACCEPTS_CERT,
    "verif_file_exists": $VERIF_FILE_EXISTS,
    "verif_content_valid": $VERIF_CONTENT_VALID,
    "doc_file_exists": $DOC_FILE_EXISTS,
    "doc_content_valid": $DOC_CONTENT_VALID
}
EOF

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="