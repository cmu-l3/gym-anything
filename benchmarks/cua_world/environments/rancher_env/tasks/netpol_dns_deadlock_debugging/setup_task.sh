#!/bin/bash
# Setup script for netpol_dns_deadlock_debugging task
# Creates a scenario where strict NetworkPolicies block DNS resolution and cross-namespace traffic

echo "=== Setting up netpol_dns_deadlock_debugging task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace app-tier cache-tier --wait=false 2>/dev/null || true
sleep 8

# ── Create namespaces and add standard metadata labels for selectors ──────────
echo "Creating namespaces..."
docker exec rancher kubectl create namespace app-tier 2>/dev/null || true
docker exec rancher kubectl create namespace cache-tier 2>/dev/null || true

docker exec rancher kubectl label namespace kube-system kubernetes.io/metadata.name=kube-system --overwrite 2>/dev/null || true
docker exec rancher kubectl label namespace app-tier kubernetes.io/metadata.name=app-tier --overwrite 2>/dev/null || true
docker exec rancher kubectl label namespace cache-tier kubernetes.io/metadata.name=cache-tier --overwrite 2>/dev/null || true

# ── Deploy Redis cache in cache-tier ──────────────────────────────────────────
echo "Deploying Redis cache in cache-tier..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cache
  namespace: cache-tier
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-cache
  template:
    metadata:
      labels:
        app: redis-cache
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cache
  namespace: cache-tier
spec:
  selector:
    app: redis-cache
  ports:
  - port: 6379
    targetPort: 6379
MANIFEST

# ── Deploy data-fetcher in app-tier (missing the access: cache label) ─────────
echo "Deploying data-fetcher in app-tier..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-fetcher
  namespace: app-tier
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-fetcher
  template:
    metadata:
      labels:
        app: data-fetcher
        # INTENTIONAL FAILURE: Missing label `access: cache` required by cache-tier
    spec:
      containers:
      - name: fetcher
        image: alpine:3.18
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Starting data fetcher..."
          echo "Testing external DNS and connectivity..."
          wget -qO- --timeout=5 https://api.github.com > /dev/null
          if [ $? -ne 0 ]; then
            echo "Error: Could not resolve host: api.github.com (DNS or Egress blocked)"
            exit 1
          fi
          echo "Testing Redis connectivity..."
          nc -w 3 -z redis-cache.cache-tier.svc.cluster.local 6379
          if [ $? -ne 0 ]; then
            echo "Error: Connection to Redis cache timed out or refused"
            exit 1
          fi
          echo "All checks passed. Service is running."
          sleep 86400
MANIFEST

# ── Apply strict NetworkPolicies ──────────────────────────────────────────────
echo "Applying Zero-Trust NetworkPolicies..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
# cache-tier strictly allows ONLY from pods labeled `access: cache` in `app-tier`
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cache-tier-ingress
  namespace: cache-tier
spec:
  podSelector: {} 
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: app-tier
      podSelector:
        matchLabels:
          access: cache
    ports:
    - protocol: TCP
      port: 6379
---
# app-tier denies ALL egress by default (blocking DNS and cache)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-tier-egress
  namespace: app-tier
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress: []
MANIFEST

echo "=== Task setup complete ==="