#!/bin/bash
# Setup script for service_account_token_projection_security task

echo "=== Setting up service_account_token_projection_security task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up any previous state ──────────────────────────────────────────────
echo "Cleaning up previous auth-system namespace..."
docker exec rancher kubectl delete namespace auth-system --wait=false 2>/dev/null || true
sleep 5

# ── Create the auth-system namespace ─────────────────────────────────────────
echo "Creating auth-system namespace..."
docker exec rancher kubectl create namespace auth-system 2>/dev/null || true

# ── Deploy the insecure microservices ────────────────────────────────────────
# These implicitly mount the default SA token (K8s default behavior)
echo "Deploying microservices without token security..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: public-api
  namespace: auth-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: public-api
  template:
    metadata:
      labels:
        app: public-api
    spec:
      containers:
      - name: api
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-sync-worker
  namespace: auth-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: k8s-sync-worker
  template:
    metadata:
      labels:
        app: k8s-sync-worker
    spec:
      containers:
      - name: worker
        image: nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-auth-proxy
  namespace: auth-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault-auth-proxy
  template:
    metadata:
      labels:
        app: vault-auth-proxy
    spec:
      containers:
      - name: proxy
        image: nginx:alpine
MANIFEST

# ── Drop the security specification on the desktop ───────────────────────────
echo "Writing identity security spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/identity_security_spec.yaml << 'SPEC'
# Identity & Token Security Specification
# Target Namespace: auth-system

deployments:
  public-api:
    serviceAccount: "default"
    automountServiceAccountToken: false
    reason: "Public facing API requires no Kubernetes cluster access."

  k8s-sync-worker:
    serviceAccount: "sync-worker-sa"  # Must be created
    automountServiceAccountToken: true
    reason: "Needs K8s API access to sync resources, but must use dedicated SA, not default."

  vault-auth-proxy:
    serviceAccount: "default"
    automountServiceAccountToken: false
    projectedToken:
      volumeName: "vault-token-vol"
      mountPath: "/var/run/secrets/kubernetes.io/vault"
      audience: "vault"
      expirationSeconds: 7200
    reason: "Authenticates to external Vault via K8s OIDC. Requires bound token, not generic API token."
SPEC
chmod 644 /home/ga/Desktop/identity_security_spec.yaml
chown ga:ga /home/ga/Desktop/identity_security_spec.yaml

# ── Ensure workloads are running ─────────────────────────────────────────────
echo "Waiting for pods to start..."
sleep 10
docker exec rancher kubectl wait --for=condition=ready pod -l app=public-api -n auth-system --timeout=30s || true

# ── Take Initial Screenshot ──────────────────────────────────────────────────
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="