#!/bin/bash
# Setup script for secrets_lifecycle_management task
# Creates initial namespaces, broken secrets, misplaced secrets, and local files

echo "=== Setting up secrets_lifecycle_management task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
for ns in payment web; do
    docker exec rancher kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
done
docker exec rancher kubectl delete secret stripe-api-keys -n default 2>/dev/null || true
rm -rf /home/ga/Desktop/tls /home/ga/Desktop/secrets_spec.md
sleep 8

# ── Create namespaces ─────────────────────────────────────────────────────────
echo "Creating namespaces..."
for ns in payment web; do
    docker exec rancher kubectl create namespace "$ns" 2>/dev/null || true
done

# ── Create Broken Secret (wrong password) ─────────────────────────────────────
echo "Creating broken payment-db-credentials..."
docker exec rancher kubectl create secret generic payment-db-credentials \
    -n payment \
    --from-literal=username=payment_svc \
    --from-literal=password=changeme \
    --from-literal=host=postgres-primary.data.svc.cluster.local \
    --from-literal=port=5432 2>/dev/null || true

# ── Create Misplaced Secret (in default instead of payment) ───────────────────
echo "Creating misplaced stripe-api-keys in default namespace..."
docker exec rancher kubectl create secret generic stripe-api-keys \
    -n default \
    --from-literal=publishable_key=pk_test_51NxGPKJ2e1BxPmEabc123def456ghi789jkl012mno345 \
    --from-literal=secret_key=sk_test_51NxGPKJ2e1BxPmEzyx987wvu654tsr321qpo098nml765 2>/dev/null || true

# ── Generate TLS Certificates ─────────────────────────────────────────────────
echo "Generating TLS certificates on desktop..."
mkdir -p /home/ga/Desktop/tls
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /home/ga/Desktop/tls/frontend.key \
    -out /home/ga/Desktop/tls/frontend.crt \
    -days 365 \
    -subj "/CN=*.payment-platform.internal/O=Payment Platform Inc" 2>/dev/null
chown -R ga:ga /home/ga/Desktop/tls

# ── Create the Specification Document ─────────────────────────────────────────
echo "Writing secrets specification to desktop..."
cat > /home/ga/Desktop/secrets_spec.md << 'SPEC'
# Payment Platform — Secrets Specification
# Security Classification: CONFIDENTIAL
# Prepared by: InfoSec Team | Effective: Immediate
# All values shown in plaintext. Kubernetes stores them base64-encoded.

## 1. payment-db-credentials (Namespace: payment)
Type: Opaque
Required keys and values:
  - username: payment_svc
  - password: Kj8mP2vL9nQ4xR!#
  - host: postgres-primary.data.svc.cluster.local
  - port: 5432

## 2. stripe-api-keys (Namespace: payment)
Type: Opaque
Required keys and values:
  - publishable_key: pk_test_51NxGPKJ2e1BxPmEabc123def456ghi789jkl012mno345
  - secret_key: sk_test_51NxGPKJ2e1BxPmEzyx987wvu654tsr321qpo098nml765

## 3. frontend-tls (Namespace: web)
Type: kubernetes.io/tls
Source files provided on desktop:
  - tls.crt: /home/ga/Desktop/tls/frontend.crt
  - tls.key: /home/ga/Desktop/tls/frontend.key

## 4. inter-service-token (Namespaces: payment AND web)
Type: Opaque
Required keys and values:
  - token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwYXltZW50LXBsYXRmb3JtIiwic3ViIjoiaW50ZXItc2VydmljZSIsImF1ZCI6WyJwYXltZW50Iiwid2ViIl0sImV4cCI6MTczNTY4OTYwMH0.placeholder_signature_do_not_use_in_production

NOTE: This token must be identical in both namespaces for mutual
service authentication to work.
SPEC
chown ga:ga /home/ga/Desktop/secrets_spec.md

# Start Firefox pointing to Rancher if not running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard &"
    sleep 5
fi

# Focus and maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="