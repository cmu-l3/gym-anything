#!/bin/bash
# Setup script for api_version_deprecation_migration task
# Creates legacy manifests that use removed v1beta1 API versions.

echo "=== Setting up api_version_deprecation_migration task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace legacy-billing --wait=false 2>/dev/null || true
sleep 5

# ── Create the legacy manifests directory on desktop ──────────────────────────
MANIFEST_DIR="/home/ga/Desktop/legacy-billing-manifests"
mkdir -p "$MANIFEST_DIR"

# 1. Deployment (Valid API, needs no changes)
cat > "$MANIFEST_DIR/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: billing-app
  template:
    metadata:
      labels:
        app: billing-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: billing-svc
spec:
  selector:
    app: billing-app
  ports:
  - port: 8080
    targetPort: 80
EOF

# 2. Ingress (Removed API: networking.k8s.io/v1beta1)
# Structural differences: missing pathType, backend uses serviceName/servicePort
cat > "$MANIFEST_DIR/ingress.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: billing-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: billing.internal.company.com
    http:
      paths:
      - path: /
        backend:
          serviceName: billing-svc
          servicePort: 8080
EOF

# 3. HPA (Removed API: autoscaling/v2beta1)
# Structural differences: metrics array uses targetAverageUtilization instead of nested target object
cat > "$MANIFEST_DIR/hpa.yaml" << 'EOF'
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: billing-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: billing-app
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 75
EOF

# 4. PDB (Removed API: policy/v1beta1)
# Mostly just API version change, but required to apply successfully
cat > "$MANIFEST_DIR/pdb.yaml" << 'EOF'
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: billing-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: billing-app
EOF

# Set permissions
chown -R ga:ga "$MANIFEST_DIR"
chmod -R 644 "$MANIFEST_DIR"/*
chmod 755 "$MANIFEST_DIR"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "Legacy manifests created at $MANIFEST_DIR"
echo "=== Task setup complete ==="