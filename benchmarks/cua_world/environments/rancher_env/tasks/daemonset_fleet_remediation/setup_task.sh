#!/bin/bash
# Setup script for daemonset_fleet_remediation task
# Injects 4 failures into monitoring DaemonSets

echo "=== Setting up daemonset_fleet_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace monitoring --wait=false 2>/dev/null || true
sleep 10

# Create monitoring namespace
echo "Creating monitoring namespace..."
docker exec rancher kubectl create namespace monitoring 2>/dev/null || true

# Deploy broken DaemonSets
echo "Deploying broken DaemonSets..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      nodeSelector:
        kubernetes.io/os: windows   # FAILURE 1: Cluster nodes are linux
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.6.0
        ports:
        - containerPort: 9100
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
  namespace: monitoring
  labels:
    app: log-collector
spec:
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
        image: busybox:99.99.99     # FAILURE 2: Invalid image tag
        command: ["/bin/sh", "-c", "while true; do sleep 3600; done"]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: disk-monitor
  namespace: monitoring
  labels:
    app: disk-monitor
spec:
  selector:
    matchLabels:
      app: disk-monitor
  template:
    metadata:
      labels:
        app: disk-monitor
    spec:
      securityContext:
        runAsUser: 0                # FAILURE 3: Conflicting security context
        runAsNonRoot: true
      containers:
      - name: disk-monitor
        image: alpine:3.18
        command: ["/bin/sh", "-c", "while true; do df -h; sleep 60; done"]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: network-probe
  namespace: monitoring
  labels:
    app: network-probe
spec:
  selector:
    matchLabels:
      app: network-probe
  template:
    metadata:
      labels:
        app: network-probe
    spec:
      containers:
      - name: network-probe
        image: alpine:3.18
        command: ["/bin/sh", "-c", "while true; do ping -c 1 8.8.8.8; sleep 30; done"]
        resources:
          requests:
            cpu: "64"               # FAILURE 4: Excessive CPU request
            memory: "64Mi"
MANIFEST

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="