#!/bin/bash
# Setup script for sidecar_shutdown_sequencing_remediation task

echo "=== Setting up sidecar_shutdown_sequencing_remediation task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace finance --wait=false 2>/dev/null || true
sleep 5

# Create finance namespace
echo "Creating finance namespace..."
docker exec rancher kubectl create namespace finance 2>/dev/null || true

# Deploy the payment-processor without the necessary lifecycle hooks or probes
echo "Deploying payment-processor..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
  namespace: finance
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
    spec:
      containers:
      - name: processor
        image: nginx:alpine
        ports:
        - containerPort: 80
          name: http
      - name: network-proxy
        image: busybox:latest
        command: ["/bin/sh", "-c", "while true; do sleep 3600; done"]
MANIFEST

# Drop the remediation specification file on the desktop
echo "Writing remediation specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/shutdown_sequence_spec.md << 'SPEC'
# Shutdown Sequence Remediation Specification
# Incident: INC-8484
# Application: payment-processor (finance namespace)

To prevent dropped transactions during deployment rollouts, the payment-processor deployment must be updated with precise shutdown sequencing and liveness checks.

## 1. Pod Configuration
- `terminationGracePeriodSeconds`: 45

## 2. Main Container (`processor`)
- `preStop` exec command: `["/bin/sh", "-c", "wget -qO- http://localhost:80/flush || true; sleep 10"]`
- `livenessProbe`: HTTP GET to `/` on port `80` (initialDelaySeconds: 10, periodSeconds: 10)

## 3. Sidecar Container (`network-proxy`)
- `preStop` exec command: `["/bin/sh", "-c", "sleep 20"]`
SPEC

chmod 644 /home/ga/Desktop/shutdown_sequence_spec.md

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="