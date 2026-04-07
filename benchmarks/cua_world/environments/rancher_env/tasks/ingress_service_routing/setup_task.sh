#!/bin/bash
# Setup script for ingress_service_routing task
# Deploys 3 applications without Services or Ingress.
# Creates the routing specification on the desktop.

echo "=== Setting up ingress_service_routing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace web-apps --wait=false 2>/dev/null || true
sleep 8

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating web-apps namespace..."
docker exec rancher kubectl create namespace web-apps 2>/dev/null || true

# ── Deploy applications WITHOUT services or ingress ───────────────────────────
echo "Deploying applications..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-frontend
  namespace: web-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-api
  namespace: web-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        command: ["/bin/sh", "-c"]
        args:
        - |
          cat > /etc/nginx/conf.d/default.conf << 'EOF'
          server {
              listen 8080;
              location / {
                  return 200 '{"service":"api","status":"ok"}';
                  add_header Content-Type application/json;
              }
          }
          EOF
          nginx -g 'daemon off;'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-docs
  namespace: web-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docs
  template:
    metadata:
      labels:
        app: docs
    spec:
      containers:
      - name: docs
        image: nginx:1.25-alpine
        ports:
        - containerPort: 3000
        command: ["/bin/sh", "-c"]
        args:
        - |
          cat > /etc/nginx/conf.d/default.conf << 'EOF'
          server {
              listen 3000;
              location / {
                  return 200 '<html><body><h1>Documentation Portal</h1></body></html>';
                  add_header Content-Type text/html;
              }
          }
          EOF
          nginx -g 'daemon off;'
MANIFEST

# Wait for deployments to roll out
echo "Waiting for deployments to be ready..."
docker exec rancher kubectl rollout status deployment/app-frontend -n web-apps --timeout=60s || true
docker exec rancher kubectl rollout status deployment/app-api -n web-apps --timeout=60s || true
docker exec rancher kubectl rollout status deployment/app-docs -n web-apps --timeout=60s || true

# ── Write routing specification to desktop ────────────────────────────────────
echo "Writing routing spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/routing_spec.md << 'SPEC'
# Web Platform Routing Specification

## Overview
The web-apps namespace contains three application deployments that need
external access via the cluster's ingress controller.

## Service Definitions

| Service Name   | Selector Label | Target Port | Type      |
|---------------|---------------|-------------|-----------|
| frontend-svc  | app=frontend  | 80          | ClusterIP |
| api-svc       | app=api       | 8080        | ClusterIP |
| docs-svc      | app=docs      | 3000        | ClusterIP |

## Ingress Routing Rules

Create a single Ingress resource named `web-apps-ingress` in the
`web-apps` namespace with the following path-based routing:

| Path   | Path Type | Backend Service | Backend Port |
|--------|-----------|----------------|-------------|
| /      | Prefix    | frontend-svc   | 80          |
| /api   | Prefix    | api-svc        | 8080        |
| /docs  | Prefix    | docs-svc       | 3000        |

## Notes
- Use the `networking.k8s.io/v1` Ingress API version
- The ingressClassName should be `traefik` (default K3s ingress controller)
- All resources must be created in the `web-apps` namespace
SPEC

chmod 644 /home/ga/Desktop/routing_spec.md

# Focus Firefox (Rancher dashboard should be open from environment post_start)
echo "Focusing Rancher dashboard..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="