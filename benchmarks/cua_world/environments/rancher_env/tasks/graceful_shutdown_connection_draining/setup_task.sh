#!/bin/bash
# Setup script for graceful_shutdown_connection_draining task

echo "=== Setting up graceful_shutdown_connection_draining task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 120; then
    echo "WARNING: Rancher API not ready"
fi

# Pre-pull image to speed up rollouts
echo "Pre-pulling nginx:1.25-alpine image in local cluster..."
docker exec rancher crictl pull docker.io/library/nginx:1.25-alpine 2>/dev/null || true

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace ecommerce --wait=false 2>/dev/null || true
sleep 10

# Create namespace
echo "Creating ecommerce namespace..."
docker exec rancher kubectl create namespace ecommerce 2>/dev/null || true

# Deploy initial state with poor shutdown configurations
echo "Deploying workloads with poor shutdown configurations..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
    spec:
      terminationGracePeriodSeconds: 5
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart-service
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart-service
  template:
    metadata:
      labels:
        app: cart-service
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-worker
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: order-worker
  template:
    metadata:
      labels:
        app: order-worker
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
MANIFEST

# Drop the spec file on Desktop
echo "Writing drain specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/drain_spec.md << 'SPEC'
# Graceful Shutdown Requirements
# Issue: 502 Bad Gateway during rollouts
# Action Required: Implement preStop hooks and terminationGracePeriodSeconds (TGPS) for ecommerce deployments.

## 1. payment-processor
- **Strategy**: Wait for load balancer deregistration.
- **TGPS**: 60 seconds
- **preStop Hook**: Execute a shell command to sleep for 15 seconds (`sleep 15`).

## 2. cart-service
- **Strategy**: Trigger internal application offline routine.
- **TGPS**: 45 seconds
- **preStop Hook**: HTTP GET request to path `/offline` on port `80`.

## 3. order-worker
- **Strategy**: Save worker state to persistent volume before exit.
- **TGPS**: 120 seconds
- **preStop Hook**: Execute the checkpoint script at `/usr/local/bin/checkpoint.sh`.

Note: Apply these changes directly to the Deployments in the `ecommerce` namespace.
SPEC

# Record baseline state
echo "Recording baseline state..."
date +%s > /tmp/graceful_shutdown_start_ts

# Take screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="