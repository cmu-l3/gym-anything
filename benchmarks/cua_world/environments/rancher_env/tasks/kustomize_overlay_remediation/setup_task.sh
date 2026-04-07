#!/bin/bash
# Setup script for kustomize_overlay_remediation task
echo "=== Setting up kustomize_overlay_remediation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Install and Configure Local Kubectl ───────────────────────────────────────
echo "Getting Rancher API token for local kubectl access..."
TOKEN=$(get_rancher_token)

if [ -n "$TOKEN" ]; then
    echo "Installing local kubectl..."
    if ! command -v kubectl &> /dev/null; then
        curl -sLO "https://dl.k8s.io/release/v1.28.2/bin/linux/amd64/kubectl"
        chmod +x kubectl
        mv kubectl /usr/local/bin/
    fi

    echo "Configuring local kubeconfig..."
    mkdir -p /home/ga/.kube
    cat > /home/ga/.kube/config <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://localhost/k8s/clusters/local
  name: local
contexts:
- context:
    cluster: local
    user: admin
  name: local
current-context: local
users:
- name: admin
  user:
    token: ${TOKEN}
EOF
    chown -R ga:ga /home/ga/.kube
else
    echo "WARNING: Could not get token, local kubeconfig not generated."
fi

# ── Clean up any previous state ───────────────────────────────────────────────
docker exec rancher kubectl delete namespace payment-staging --wait=false 2>/dev/null || true
rm -rf /home/ga/Desktop/payment-gateway 2>/dev/null || true

# ── Generate the broken Kustomize project on Desktop ──────────────────────────
echo "Creating GitOps repository structure on Desktop..."
PROJECT_DIR="/home/ga/Desktop/payment-gateway"
mkdir -p "$PROJECT_DIR/base" "$PROJECT_DIR/overlays/staging"

# 1. Base - Deployment
cat > "$PROJECT_DIR/base/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-gateway
  template:
    metadata:
      labels:
        app: payment-gateway
    spec:
      containers:
      - name: gateway
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# 2. Base - Service
cat > "$PROJECT_DIR/base/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: payment-gateway
spec:
  selector:
    app: payment-gateway
  ports:
  - port: 80
    targetPort: 80
EOF

# 3. Base - ConfigMap
cat > "$PROJECT_DIR/base/configmap.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: payment-config
data:
  LOG_LEVEL: "INFO"
EOF

# 4. Base - Kustomization
cat > "$PROJECT_DIR/base/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
- configmap.yaml
EOF

# 5. Overlay - ConfigMap Patch (BROKEN: wrong target name)
cat > "$PROJECT_DIR/overlays/staging/cm-patch.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: payment-config-wrong
data:
  LOG_LEVEL: "DEBUG"
EOF

# 6. Overlay - Kustomization (BROKEN: 3 distinct errors)
cat > "$PROJECT_DIR/overlays/staging/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: payment-staging

commonLabels:
  environment: staging

resources:
- ../base

patches:
- path: cm-patch.yaml

images:
- name: nginx
  newTag 1.24-alpine

replicas:
- name: payment-gw
  count: 3
EOF

chown -R ga:ga /home/ga/Desktop/payment-gateway

# Take initial screenshot showing environment setup
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="