#!/bin/bash
# Setup script for stateful_network_identity_migration task
# Creates a data-grid namespace, deploys a mock clustered application as a standard 
# Deployment (which intentionally fails), and requires the agent to migrate it to a 
# StatefulSet with a Headless Service.

echo "=== Setting up stateful_network_identity_migration task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-grid --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating data-grid namespace..."
docker exec rancher kubectl create namespace data-grid 2>/dev/null || true

# ── Deploy the INCORRECT architecture (Deployment + Standard Service) ─────────
echo "Deploying incorrect architecture (Deployment instead of StatefulSet)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: hazelcast-config
  namespace: data-grid
data:
  # This script acts as the active anti-gaming runtime constraint.
  # It enforces that the pod has a StatefulSet-style sequential hostname.
  entrypoint.sh: |
    #!/bin/sh
    echo "Initializing mock clustering node..."
    
    # Check if the hostname follows StatefulSet naming convention (name-ordinal)
    if ! hostname | grep -Eq "^hazelcast-mock-[0-9]+$"; then
        echo "FATAL: Invalid hostname format for clustering: $(hostname)"
        echo "Nodes require stable, sequential network identities to form a quorum."
        echo "Re-architect this workload as a StatefulSet."
        exit 1
    fi
    
    echo "Hostname check passed. Identity is valid."
    echo "Starting node. Waiting for cluster peers..."
    while true; do sleep 60; done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hazelcast-mock
  namespace: data-grid
  labels:
    app: hazelcast
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hazelcast
  template:
    metadata:
      labels:
        app: hazelcast
    spec:
      containers:
      - name: hazelcast
        image: busybox:1.36
        command: ["/bin/sh", "/config/entrypoint.sh"]
        ports:
        - containerPort: 5701
          name: discovery
        volumeMounts:
        - name: config-volume
          mountPath: /config
      volumes:
      - name: config-volume
        configMap:
          name: hazelcast-config
          defaultMode: 0755
---
# INCORRECT: Standard ClusterIP Service instead of Headless
apiVersion: v1
kind: Service
metadata:
  name: hazelcast-discovery
  namespace: data-grid
spec:
  type: ClusterIP
  selector:
    app: hazelcast
  ports:
  - port: 5701
    targetPort: 5701
MANIFEST

# ── Drop the architecture specification on the desktop ───────────────────────
echo "Writing architecture specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/grid_architecture.md << 'SPEC'
# Data Grid Architecture Specification
# Application: hazelcast-mock

## Issue Description
The cluster nodes are currently in a `CrashLoopBackOff` state. The entrypoint script is rejecting the pod environment because it lacks stable network identities, which are required for the peers to form a quorum. This happened because the workload was deployed as a stateless `Deployment`.

## Required Architecture
To fix this, you must migrate the application to a `StatefulSet`.

**1. Clean up existing objects**
- Delete the existing `hazelcast-mock` Deployment.
- Delete the existing `hazelcast-discovery` Service (ClusterIPs are immutable, so you cannot just patch it to become headless).

**2. Network Setup**
- Create a Headless Service named `hazelcast-discovery` targeting port `5701` and selecting pods with label `app: hazelcast`. (A headless service has `clusterIP: None`).

**3. Workload Setup**
- Create a `StatefulSet` named `hazelcast-mock` with `3` replicas.
- It MUST be explicitly linked to the headless service using `serviceName: "hazelcast-discovery"`.
- Use the image `busybox:1.36`.
- Set the container command to `["/bin/sh", "/config/entrypoint.sh"]`.
- Mount the existing ConfigMap `hazelcast-config` to `/config`.
SPEC

chmod 644 /home/ga/Desktop/grid_architecture.md

echo "=== Task setup complete ==="