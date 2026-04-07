#!/bin/bash
# Setup script for pod_security_admission_enforcement task
# Creates secure-apps namespace with restricted PSA labels.
# Deploys 4 microservices, each with a specific Pod Security Standard violation.

echo "=== Setting up pod_security_admission_enforcement task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace secure-apps --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace with restricted enforcement ──────────────────────────────
echo "Creating secure-apps namespace with restricted PSA label..."
docker exec rancher kubectl create namespace secure-apps 2>/dev/null || true
docker exec rancher kubectl label namespace secure-apps \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest \
    --overwrite 2>/dev/null || true

# ── Deploy workloads WITH security violations ─────────────────────────────────
echo "Deploying workloads (these will fail to create pods due to PSA)..."

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: secure-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      # VIOLATION: Missing runAsNonRoot: true
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: secure-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        # VIOLATION: Missing seccompProfile: {type: RuntimeDefault}
      containers:
      - name: app
        image: busybox:1.36
        command: ["sleep", "3600"]
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: secure-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        securityContext:
          # VIOLATION: allowPrivilegeEscalation must be false
          allowPrivilegeEscalation: true
          capabilities:
            drop: ["ALL"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logger
  namespace: secure-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logger
  template:
    metadata:
      labels:
        app: logger
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: busybox:1.36
        command: ["sleep", "3600"]
        securityContext:
          allowPrivilegeEscalation: false
          # VIOLATION: Missing capabilities.drop: ["ALL"]
MANIFEST

# ── Drop the compliance reference document on the desktop ─────────────────────
echo "Writing compliance reference to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/psa_compliance_reference.md << 'SPEC'
# Pod Security Standards (PSS) Compliance Reference
# Classification: INTERNAL SECURITY DOCUMENT

## Overview
Our clusters enforce the **Restricted** Pod Security Standard using Kubernetes Pod Security Admission (PSA).
Namespaces enforcing this policy must have the label:
`pod-security.kubernetes.io/enforce: restricted`

## Requirements for Restricted Profile
When a namespace enforces the Restricted profile, ALL pods must explicitly define security configurations. If a deployment is failing to create pods, check the ReplicaSet events for admission webhook rejections.

Common fields that must be explicitly set:

1. **Privilege Escalation**
   - Must be explicitly disallowed.
   - `securityContext.allowPrivilegeEscalation: false`

2. **Root execution**
   - Containers must not run as root.
   - `securityContext.runAsNonRoot: true`
   - It is highly recommended to also set a non-zero `runAsUser` (e.g., `1000`).

3. **Seccomp Profile**
   - Must be set to RuntimeDefault or Localhost.
   - `securityContext.seccompProfile.type: RuntimeDefault`

4. **Capabilities**
   - All capabilities must be dropped.
   - `securityContext.capabilities.drop: ["ALL"]`

*Note: These fields can be set at the Pod level `spec.securityContext` OR the Container level `spec.containers[*].securityContext`, depending on the field.*
SPEC
chmod 644 /home/ga/Desktop/psa_compliance_reference.md
chown ga:ga /home/ga/Desktop/psa_compliance_reference.md

# ── Start Firefox ─────────────────────────────────────────────────────────────
echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard/c/local/explorer > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# ── Record initial state ──────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="