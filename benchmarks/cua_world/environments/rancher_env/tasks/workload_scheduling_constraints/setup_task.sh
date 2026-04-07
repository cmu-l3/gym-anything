#!/bin/bash
echo "=== Setting up workload_scheduling_constraints task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up any previous state to ensure idempotency ────────────────────────
echo "Cleaning up previous state..."
NODE_NAME=$(docker exec rancher kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "localhost")

# Remove labels if they exist
docker exec rancher kubectl label node "$NODE_NAME" workload-type- environment- disk-type- 2>/dev/null || true

# Remove taints if they exist
docker exec rancher kubectl taint node "$NODE_NAME" dedicated- 2>/dev/null || true

# Delete any existing priority classes
docker exec rancher kubectl delete priorityclass critical-platform standard-workload 2>/dev/null || true

# Delete existing monitoring namespace and recreate it
docker exec rancher kubectl delete namespace monitoring --wait=false 2>/dev/null || true
sleep 5
docker exec rancher kubectl create namespace monitoring 2>/dev/null || true

# ── Write the scheduling specification file to the desktop ───────────────────
echo "Writing scheduling specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/scheduling_spec.yaml << 'SPEC'
# Cluster Scheduling Specification
# Platform Engineering Team — Q4 Implementation
# ================================================

node_configuration:
  # Apply to ALL nodes in the cluster
  labels:
    workload-type: "general-purpose"
    environment: "production"
    disk-type: "ssd"
  taints:
    - key: "dedicated"
      value: "platform"
      effect: "NoSchedule"

priority_classes:
  - name: "critical-platform"
    value: 1000000
    globalDefault: false
    preemptionPolicy: "Never"
    description: "For platform-critical DaemonSets (monitoring, logging, security agents)"
  - name: "standard-workload"
    value: 100000
    globalDefault: true
    preemptionPolicy: "PreemptLowerPriority"
    description: "Default priority for standard application workloads"

daemonsets:
  - name: "log-collector"
    namespace: "monitoring"
    container:
      image: "busybox:1.36"
      command: ["/bin/sh", "-c", "while true; do echo collecting logs; sleep 60; done"]
      resources:
        requests:
          cpu: "50m"
          memory: "64Mi"
        limits:
          cpu: "100m"
          memory: "128Mi"
    scheduling:
      nodeSelector:
        workload-type: "general-purpose"
      tolerations:
        - key: "dedicated"
          operator: "Equal"
          value: "platform"
          effect: "NoSchedule"
      priorityClassName: "critical-platform"
SPEC
chmod 644 /home/ga/Desktop/scheduling_spec.yaml

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "=== Setup complete ==="