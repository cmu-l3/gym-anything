#!/bin/bash
echo "=== Setting up cicd_rbac_token_provisioning task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace webapp --wait=false 2>/dev/null || true
sleep 5

docker exec rancher kubectl delete clusterrolebinding github-actions-admin 2>/dev/null || true

# ── Create namespace and SA ───────────────────────────────────────────────────
echo "Creating webapp namespace and github-actions ServiceAccount..."
docker exec rancher kubectl create namespace webapp 2>/dev/null || true
docker exec rancher kubectl create serviceaccount github-actions -n webapp 2>/dev/null || true

# ── Inject Violation: Dangerous ClusterRoleBinding ────────────────────────────
echo "Injecting dangerous cluster-admin binding..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-actions-admin
subjects:
- kind: ServiceAccount
  name: github-actions
  namespace: webapp
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

# ── Inject Violation: Broken Opaque Secret ────────────────────────────────────
echo "Injecting broken Opaque secret..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: github-actions-token
  namespace: webapp
type: Opaque
stringData:
  token: "this-is-a-broken-fake-token-that-doesnt-work"
EOF

# ── Record baseline state ────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# Start Firefox and maximize it
echo "Ensuring Firefox is running and maximized..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard &"
    sleep 5
fi

DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take an initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="