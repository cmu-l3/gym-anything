#!/bin/bash
echo "=== Setting up rancher_custom_role_delegation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace production-apps --wait=false 2>/dev/null || true
# Delete user if exists
docker exec rancher kubectl delete users.management.cattle.io -l authz.cluster.cattle.io/user-principal-name=local://support-user 2>/dev/null || true
sleep 5

# ── Create namespace and workload ─────────────────────────────────────────────
echo "Creating production-apps namespace..."
docker exec rancher kubectl create namespace production-apps 2>/dev/null || true

echo "Deploying production workloads..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-gateway
  namespace: production-apps
  labels:
    app: payment-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-gateway
  template:
    metadata:
      labels:
        app: payment-gateway
    spec:
      containers:
      - name: payment-gateway
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Secret
metadata:
  name: payment-api-keys
  namespace: production-apps
type: Opaque
data:
  api-key: c3VwZXItc2VjcmV0LWtleS0xMjM0NQ==
MANIFEST

# ── Drop the specification file on the desktop ────────────────────────────────
echo "Writing IAM specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/support_rbac_spec.md << 'SPEC'
# IAM Support Role Specification

Please create the following access structure for the new L1 Support team using the Rancher UI.

## 1. User Account
- Username: `support-user`
- Password: `SupportUser123!`
- Global Role: Standard User

## 2. Custom Cluster Role
- Name: `Node Health Monitor`
- Context: Cluster
- Permissions: strictly `get`, `list`, `watch` on `nodes` and `events`.
- **Requirement**: Absolutely no wildcard (*) permissions.

## 3. Custom Project Role
- Name: `L1 App Viewer`
- Context: Project
- Permissions: view-only (`get`, `list`, `watch`) for `pods`, `pods/log`, `deployments`, `statefulsets`, `services`, and `configmaps`.
- **Requirement**: Explicitly EXCLUDE `secrets` and `pods/exec`. This is a strict HIPAA compliance requirement. Do not use wildcards.

## 4. Project Isolation
- Create a new Project named `Support Access Project` in the `local` cluster.
- Move the existing `production-apps` namespace into this new project.

## 5. Role Binding
- Bind `support-user` to the `Node Health Monitor` cluster role in the `local` cluster.
- Bind `support-user` to the `L1 App Viewer` project role within the `Support Access Project`.
SPEC

chmod 644 /home/ga/Desktop/support_rbac_spec.md

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="