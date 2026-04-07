#!/bin/bash
# Setup script for downward_api_telemetry_injection task

echo "=== Setting up downward_api_telemetry_injection task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous namespace..."
docker exec rancher kubectl delete namespace ecommerce --wait=false 2>/dev/null || true
sleep 5

# ── Create target namespace ───────────────────────────────────────────────────
echo "Creating ecommerce namespace..."
docker exec rancher kubectl create namespace ecommerce 2>/dev/null || true

# ── Deploy the hardcoded (broken) configuration ───────────────────────────────
echo "Deploying payment-gateway with hardcoded telemetry..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-gateway
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-gateway
  template:
    metadata:
      labels:
        app: payment-gateway
        tier: backend
      annotations:
        security-scan: "passed"
    spec:
      containers:
      - name: gateway-app
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: "500m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
      - name: audit-logger
        image: busybox:latest
        command: ["/bin/sh", "-c", "while true; do sleep 3600; done"]
        env:
        # THESE MUST BE REFACTORED TO USE DOWNWARD API fieldRef
        - name: APP_POD_NAME
          value: "static-name"
        - name: APP_POD_NAMESPACE
          value: "default"
        - name: HOST_IP
          value: "127.0.0.1"
        - name: POD_IP
          value: "10.0.0.1"
        # THIS MUST BE REFACTORED TO USE resourceFieldRef
        - name: MAIN_CPU_LIMIT
          value: "500"
MANIFEST

# ── Write specification to Desktop ────────────────────────────────────────────
echo "Writing telemetry specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/telemetry_injection_spec.md << 'SPEC'
# Telemetry Metadata Injection Spec

## Context
The `audit-logger` sidecar in the `payment-gateway` deployment is incorrectly using hardcoded environment variables. This breaks our observability pipelines.

## Required Refactoring
Target: `deployment/payment-gateway` in namespace `ecommerce`.

1. **Basic Metadata (FieldRefs)**
   Replace the hardcoded env vars in `audit-logger` with `valueFrom.fieldRef`:
   - `APP_POD_NAME` -> `metadata.name`
   - `APP_POD_NAMESPACE` -> `metadata.namespace`
   - `HOST_IP` -> `status.hostIP`
   - `POD_IP` -> `status.podIP`

2. **Resource Introspection (ResourceFieldRef)**
   Replace the hardcoded `MAIN_CPU_LIMIT` env var with `valueFrom.resourceFieldRef`:
   - Container Name: `gateway-app`
   - Resource: `limits.cpu`
   - Divisor: `1m`

3. **Label tracking (DownwardAPI Volume)**
   We need dynamic access to labels/annotations that env vars cannot provide.
   - Create a volume of type `downwardAPI` named `pod-metadata`.
   - Map `metadata.labels` to the path `labels`.
   - Map `metadata.annotations` to the path `annotations`.
   - Mount this volume strictly into the `audit-logger` container at `/etc/podinfo`.
SPEC

chmod 644 /home/ga/Desktop/telemetry_injection_spec.md

echo "=== Task setup complete ==="