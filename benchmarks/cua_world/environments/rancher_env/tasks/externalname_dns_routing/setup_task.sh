#!/bin/bash
# Setup script for externalname_dns_routing task
# Creates core-data, legacy-apps, and rogue-ns namespaces.
# Deploys a postgres DB in core-data with a default-deny network policy.
# Deploys frontend in legacy-apps trying to reach "database-svc".

echo "=== Setting up externalname_dns_routing task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
for ns in core-data legacy-apps rogue-ns; do
    docker exec rancher kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
done
sleep 8

# ── Create namespaces with explicit labels for NetworkPolicy targeting ─────────
echo "Creating namespaces..."
docker exec rancher kubectl create namespace core-data
docker exec rancher kubectl create namespace legacy-apps
docker exec rancher kubectl create namespace rogue-ns

# Add labels so namespaceSelector can work easily (though kubernetes.io/metadata.name also works)
docker exec rancher kubectl label namespace legacy-apps environment=legacy kubernetes.io/metadata.name=legacy-apps --overwrite
docker exec rancher kubectl label namespace rogue-ns environment=rogue kubernetes.io/metadata.name=rogue-ns --overwrite
docker exec rancher kubectl label namespace core-data environment=core kubernetes.io/metadata.name=core-data --overwrite

# ── Deploy core-data components (Postgres + Deny-All NetworkPolicy) ───────────
echo "Deploying core-data components..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-primary
  namespace: core-data
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: db
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          value: "securepass"
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "postgres"]
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-primary
  namespace: core-data
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-protection
  namespace: core-data
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress: [] # Empty ingress means DENY ALL by default
MANIFEST

# ── Deploy legacy-apps components (Frontend app) ──────────────────────────────
echo "Deploying legacy-apps components..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-frontend
  namespace: legacy-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-frontend
  template:
    metadata:
      labels:
        app: inventory-frontend
    spec:
      containers:
      - name: app
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          while true; do
            echo "Attempting to connect to database-svc:5432..."
            nc -z -w 2 database-svc 5432 && echo "Connected!" || echo "Connection failed!"
            sleep 5
          done
MANIFEST

# ── Deploy rogue-ns components (to test isolation) ────────────────────────────
echo "Deploying rogue-ns components..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rogue-client
  namespace: rogue-ns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rogue-client
  template:
    metadata:
      labels:
        app: rogue-client
    spec:
      containers:
      - name: client
        image: alpine:latest
        command: ["/bin/sh", "-c", "sleep infinity"]
MANIFEST

# ── Wait for Pods to be ready ─────────────────────────────────────────────────
echo "Waiting for pods to initialize..."
docker exec rancher kubectl wait --for=condition=Ready pod -l app=postgres -n core-data --timeout=90s || true
docker exec rancher kubectl wait --for=condition=Ready pod -l app=inventory-frontend -n legacy-apps --timeout=60s || true
docker exec rancher kubectl wait --for=condition=Ready pod -l app=rogue-client -n rogue-ns --timeout=60s || true

# ── Save baseline state of the inventory-frontend container spec ──────────────
echo "Saving baseline deployment spec..."
docker exec rancher kubectl get deployment inventory-frontend -n legacy-apps \
    -o jsonpath='{.spec.template.spec.containers[0]}' > /tmp/baseline_container.json

echo "=== Setup complete ==="