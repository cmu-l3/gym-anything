#!/bin/bash
# Setup script for rancher_project_multitenancy_governance task

echo "=== Setting up Rancher Project Multi-Tenancy Governance task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace marketing-site marketing-analytics sales-api sales-db --wait=false 2>/dev/null || true
sleep 10

# Create namespaces
echo "Creating tenant namespaces..."
for ns in marketing-site marketing-analytics sales-api sales-db; do
    docker exec rancher kubectl create namespace "$ns" 2>/dev/null || true
done

# Deploy dummy workloads (these must be preserved)
echo "Deploying workloads to tenant namespaces..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: marketing-frontend
  namespace: marketing-site
spec:
  replicas: 1
  selector:
    matchLabels:
      app: marketing-frontend
  template:
    metadata:
      labels:
        app: marketing-frontend
    spec:
      containers:
      - name: web
        image: nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-worker
  namespace: marketing-analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: analytics-worker
  template:
    metadata:
      labels:
        app: analytics-worker
    spec:
      containers:
      - name: worker
        image: nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sales-gateway
  namespace: sales-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sales-gateway
  template:
    metadata:
      labels:
        app: sales-gateway
    spec:
      containers:
      - name: api
        image: nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sales-postgres
  namespace: sales-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sales-postgres
  template:
    metadata:
      labels:
        app: sales-postgres
    spec:
      containers:
      - name: db
        image: nginx:alpine
MANIFEST

# Write the governance spec to desktop
echo "Writing governance spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/tenant_governance_spec.md << 'SPEC'
# Tenant Governance Specification

## Tenant: Marketing
- **Project Name**: Marketing Hub
- **Namespaces to include**: `marketing-site`, `marketing-analytics`
- **Project Resource Quota**:
  - CPU Limit: 4
  - Memory Limit: 8Gi

## Tenant: Sales
- **Project Name**: Sales Core
- **Namespaces to include**: `sales-api`, `sales-db`
- **Project Resource Quota**:
  - CPU Limit: 8
  - Memory Limit: 16Gi
SPEC

chmod 644 /home/ga/Desktop/tenant_governance_spec.md

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "=== Setup Complete ==="