#!/bin/bash
# Setup script for container_security_hardening task
# Injects 4 security context violations into deployments

echo "=== Setting up container_security_hardening task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace compliance-apps --wait=false 2>/dev/null || true
sleep 8

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating compliance-apps namespace..."
docker exec rancher kubectl create namespace compliance-apps 2>/dev/null || true

# ── Deploy vulnerable workloads ───────────────────────────────────────────────
echo "Deploying vulnerable workloads..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-api
  namespace: compliance-apps
  labels:
    app: web-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-api
  template:
    metadata:
      labels:
        app: web-api
    spec:
      containers:
      - name: web-api
        image: busybox:1.36
        command: ["sleep", "infinity"]
        securityContext:
          runAsUser: 0
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-processor
  namespace: compliance-apps
  labels:
    app: data-processor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-processor
  template:
    metadata:
      labels:
        app: data-processor
    spec:
      containers:
      - name: data-processor
        image: busybox:1.36
        command: ["sleep", "infinity"]
        securityContext:
          privileged: true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-collector
  namespace: compliance-apps
  labels:
    app: log-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - name: log-collector
        image: busybox:1.36
        command: ["sleep", "infinity"]
        securityContext:
          allowPrivilegeEscalation: true
          capabilities:
            add: ["ALL"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: file-handler
  namespace: compliance-apps
  labels:
    app: file-handler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: file-handler
  template:
    metadata:
      labels:
        app: file-handler
    spec:
      containers:
      - name: file-handler
        image: busybox:1.36
        command: ["sleep", "infinity"]
MANIFEST

# ── Drop security baseline specification ──────────────────────────────────────
echo "Writing security baseline specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/container_security_baseline.md << 'SPEC'
# Container Security Baseline - CIS Kubernetes Benchmark Compliance

## Effective Date: Immediate

All container workloads MUST comply with the following security context requirements:

### 1. Non-Root Execution (CIS 5.2.6)
- `securityContext.runAsNonRoot: true`
- `securityContext.runAsUser` must be >= 1000
- `securityContext.runAsGroup` should be >= 1000

### 2. Privileged Mode (CIS 5.2.1)
- `securityContext.privileged` MUST be `false` or absent
- No container may run in privileged mode

### 3. Privilege Escalation (CIS 5.2.5)
- `securityContext.allowPrivilegeEscalation: false`
- `securityContext.capabilities.drop: ["ALL"]`
- Only explicitly approved capabilities may be added
- Approved additions by workload:
  - log-collector: NET_BIND_SERVICE

### 4. Root Filesystem (CIS 5.2.4)
- `securityContext.readOnlyRootFilesystem: true`
- Writable directories must use emptyDir volumes
- Standard writable path: /tmp

## Namespace Scope
These requirements apply to ALL deployments in the `compliance-apps` namespace.
SPEC
chmod 644 /home/ga/Desktop/container_security_baseline.md

# ── Record start time and initial screenshot ──────────────────────────────────
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="