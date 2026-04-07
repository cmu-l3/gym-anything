#!/bin/bash
# Setup script for blue_green_cutover_remediation task
# Creates a blue/green deployment scenario where the green deployment is failing
# readiness checks due to a misconfigured port, preventing cutover.

echo "=== Setting up blue_green_cutover_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace production --wait=false 2>/dev/null || true
sleep 5

# ── Create production namespace ───────────────────────────────────────────────
echo "Creating production namespace..."
docker exec rancher kubectl create namespace production 2>/dev/null || true

# ── Deploy Blue/Green workloads and Service ───────────────────────────────────
echo "Deploying frontend-blue, frontend-green (broken), and frontend-service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-blue
  namespace: production
  labels:
    app: frontend
    color: blue
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      color: blue
  template:
    metadata:
      labels:
        app: frontend
        color: blue
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 5
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-green
  namespace: production
  labels:
    app: frontend
    color: green
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      color: green
  template:
    metadata:
      labels:
        app: frontend
        color: green
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 8080    # FAILURE INJECTED: Should be port 80
          initialDelaySeconds: 2
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: production
spec:
  selector:
    app: frontend
    color: blue         # Currently pointing to blue
  ports:
  - port: 80
    targetPort: 80
MANIFEST

# ── Wait for blue pods to be ready (green will stay unready) ──────────────────
echo "Waiting for frontend-blue pods to become ready..."
for i in {1..30}; do
    READY=$(docker exec rancher kubectl get deployment frontend-blue -n production -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$READY" = "2" ]; then
        echo "frontend-blue is fully ready."
        break
    fi
    sleep 2
done

# ── Record start time and baseline ────────────────────────────────────────────
date +%s > /tmp/blue_green_task_start_ts
echo "=== Task setup complete ==="