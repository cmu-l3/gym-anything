#!/bin/bash
# Setup script for legacy_service_abstraction task
# Creates a namespace with a hardcoded legacy configuration that needs refactoring.

echo "=== Setting up legacy_service_abstraction task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace retail-system --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating retail-system namespace..."
docker exec rancher kubectl create namespace retail-system 2>/dev/null || true

# ── Deploy the application with hardcoded values ──────────────────────────────
echo "Deploying inventory-api with hardcoded external dependencies..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: inventory-api-config
  namespace: retail-system
data:
  ORACLE_DB_URL: "jdbc:oracle:thin:@10.50.2.100:1521/ORCL"
  PAYMENT_API_URL: "https://api.stripe.com/v1/charges"
  LOG_LEVEL: "INFO"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-api
  namespace: retail-system
  labels:
    app: inventory-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-api
  template:
    metadata:
      labels:
        app: inventory-api
    spec:
      containers:
      - name: api
        image: nginx:alpine
        command: ["/bin/sh", "-c", "sleep 3600"]
        envFrom:
        - configMapRef:
            name: inventory-api-config
MANIFEST

# ── Drop the migration specification file on the desktop ─────────────────────
echo "Writing migration specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/migration_spec.md << 'SPEC'
# Phase 1: External Services Abstraction

All hardcoded external IPs and domains must be removed from the `retail-system` namespace configuration to support our upcoming datacenter failover tests.

## 1. Legacy Oracle Database
The `inventory-api` currently connects directly to the on-premise Oracle RAC nodes.
- **Current Config**: `ORACLE_DB_URL=jdbc:oracle:thin:@10.50.2.100:1521/ORCL`
- **Required Action**: 
  1. Create a Kubernetes `Service` named `legacy-oracle` in the `retail-system` namespace (TCP port 1521). **Do not assign a pod selector.**
  2. Create a corresponding `Endpoints` object named `legacy-oracle` that maps to both RAC nodes: `10.50.2.100` and `10.50.2.101` on port 1521.
  3. Update the `inventory-api-config` ConfigMap so `ORACLE_DB_URL` is exactly `jdbc:oracle:thin:@legacy-oracle:1521/ORCL`.

## 2. Stripe Payment Gateway
The application hardcodes the external SaaS endpoint.
- **Current Config**: `PAYMENT_API_URL=https://api.stripe.com/v1/charges`
- **Required Action**:
  1. Create an `ExternalName` service named `stripe-api` in the `retail-system` namespace pointing to `api.stripe.com`.
  2. Update the `inventory-api-config` ConfigMap so `PAYMENT_API_URL` is exactly `https://stripe-api/v1/charges`.

## 3. Configuration Rollout
The `inventory-api` deployment must be restarted so the running pods pick up the new configuration from the ConfigMap.
SPEC

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/legacy_service_abstraction_start_ts

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="