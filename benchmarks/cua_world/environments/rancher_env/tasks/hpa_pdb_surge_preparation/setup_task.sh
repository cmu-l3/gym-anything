#!/bin/bash
# Setup script for hpa_pdb_surge_preparation task

echo "=== Setting up hpa_pdb_surge_preparation task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
wait_for_rancher_api 60 || true

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace ecommerce-prod --wait=false 2>/dev/null || true
sleep 8

# Create namespace
echo "Creating ecommerce-prod namespace..."
docker exec rancher kubectl create namespace ecommerce-prod 2>/dev/null || true

# Deploy base microservices WITHOUT autoscaling or availability budgets
echo "Deploying base microservices..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  namespace: ecommerce-prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout-api
  template:
    metadata:
      labels:
        app: checkout-api
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: 100m
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-catalog
  namespace: ecommerce-prod
spec:
  replicas: 3
  selector:
    matchLabels:
      app: product-catalog
  template:
    metadata:
      labels:
        app: product-catalog
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: 150m
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-service
  namespace: ecommerce-prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: search-service
  template:
    metadata:
      labels:
        app: search-service
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: 200m
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-gateway
  namespace: ecommerce-prod
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
      - name: app
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: 250m
EOF

# Drop the scaling specification file on the desktop
echo "Writing scaling specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/scaling_spec.md << 'SPEC'
# High-Traffic Event: Scaling & Availability Specification

**Target Namespace**: `ecommerce-prod`

All listed microservices must have Horizontal Pod Autoscalers (HPAs) and Pod Disruption Budgets (PDBs) configured with the exact parameters below.

## 1. checkout-api
- **HPA**: minReplicas=2, maxReplicas=10, Target CPU Utilization=70%
- **PDB**: minAvailable=1

## 2. product-catalog
- **HPA**: minReplicas=3, maxReplicas=15, Target CPU Utilization=60%
- **PDB**: minAvailable=2

## 3. search-service
- **HPA**: minReplicas=2, maxReplicas=12, Target CPU Utilization=65%
- **PDB**: maxUnavailable=1  *(Note: Must use maxUnavailable, not minAvailable)*

## 4. payment-gateway
- **HPA**: minReplicas=2, maxReplicas=6, Target CPU Utilization=50%
- **PDB**: minAvailable=2

---
*Instructions:*
* Create an HPA for each deployment targeting the CPU utilization specified.
* Create a PDB for each deployment selecting its pods (match label `app: <service-name>`) and applying the specified availability constraint.
SPEC

chown ga:ga /home/ga/Desktop/scaling_spec.md

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="