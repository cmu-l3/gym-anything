#!/bin/bash
echo "=== Setting up qos_class_guarantee_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
docker exec rancher kubectl delete namespace critical-path --wait=false 2>/dev/null || true
docker exec rancher kubectl delete namespace background-tasks --wait=false 2>/dev/null || true
sleep 5

# Create target namespaces
docker exec rancher kubectl create namespace critical-path 2>/dev/null || true
docker exec rancher kubectl create namespace background-tasks 2>/dev/null || true

# Deploy auth-service (Burstable - needs to be Guaranteed)
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: critical-path
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
      - name: auth-service
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Deploy payment-api (Burstable because init container has no resources - needs to be Guaranteed)
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: critical-path
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-api
  template:
    metadata:
      labels:
        app: payment-api
    spec:
      initContainers:
      - name: config-loader
        image: busybox:1.36
        command: ['sh', '-c', 'echo "loading config" && sleep 1']
      containers:
      - name: payment-api
        image: nginx:alpine
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 250m
            memory: 256Mi
EOF

# Deploy data-warehouse-sync (Guaranteed - needs to be Burstable/BestEffort)
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-warehouse-sync
  namespace: background-tasks
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-warehouse-sync
  template:
    metadata:
      labels:
        app: data-warehouse-sync
    spec:
      containers:
      - name: sync-worker
        image: nginx:alpine
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Write QoS Policy to desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/qos_policy.md << 'EOF'
# Infrastructure Quality of Service (QoS) Policy

**Scope:** All Kubernetes Clusters

## Policy Rules
To ensure cluster stability during node memory/CPU pressure, we enforce strict QoS tiering:

1. **Critical Path Services (`critical-path` namespace)**
   - MUST be configured as `Guaranteed` QoS class.
   - *Requirement:* All containers (including init-containers) must have identical CPU requests and limits, and identical Memory requests and limits.

2. **Background Tasks (`background-tasks` namespace)**
   - MUST NOT be `Guaranteed`. They should be `Burstable` or `BestEffort` so they are preempted first during resource pressure.
   - *Requirement:* Resource requests must be set lower than limits (or omit requests/limits altogether).

## Incident Remediation
Please review `auth-service`, `payment-api`, and `data-warehouse-sync` and reconfigure their resources so they comply with this policy. Ensure all pods successfully restart and reach the `Running` state.
EOF

# Timestamp for anti-gaming verification
date +%s > /tmp/qos_task_start_ts

echo "=== Setup complete ==="