#!/bin/bash
# Setup script for platform_capacity_governance_implementation
# Creates payments-prod namespace with 4 workloads but no capacity governance controls.
# Agent must read the spec doc and implement ResourceQuota, LimitRange, HPA, and PDB
# exactly as specified.

echo "=== Setting up platform_capacity_governance_implementation ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready, proceeding anyway"
fi

# ── Clean up any previous run ────────────────────────────────────────────────
echo "Cleaning up previous payments-prod namespace..."
docker exec rancher kubectl delete namespace payments-prod --timeout=60s 2>/dev/null || true
sleep 5

# ── Create namespace ─────────────────────────────────────────────────────────
echo "Creating payments-prod namespace..."
docker exec rancher kubectl create namespace payments-prod 2>/dev/null || true

# Label namespace for network policies
docker exec rancher kubectl label namespace payments-prod environment=production tier=payments 2>/dev/null || true

# ── Deploy Workload 1: payment-gateway (2 replicas) ──────────────────────────
echo "Deploying payment-gateway..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-gateway
  namespace: payments-prod
  labels:
    app: payment-gateway
    tier: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-gateway
  template:
    metadata:
      labels:
        app: payment-gateway
        tier: frontend
    spec:
      containers:
      - name: payment-gateway
        image: nginx:1.25-alpine
        ports:
        - containerPort: 443
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
MANIFEST

# ── Deploy Workload 2: transaction-processor (3 replicas) ────────────────────
echo "Deploying transaction-processor..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transaction-processor
  namespace: payments-prod
  labels:
    app: transaction-processor
    tier: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: transaction-processor
  template:
    metadata:
      labels:
        app: transaction-processor
        tier: backend
    spec:
      containers:
      - name: transaction-processor
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "300m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
MANIFEST

# ── Deploy Workload 3: fraud-detector (1 replica) ────────────────────────────
echo "Deploying fraud-detector..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fraud-detector
  namespace: payments-prod
  labels:
    app: fraud-detector
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fraud-detector
  template:
    metadata:
      labels:
        app: fraud-detector
        tier: backend
    spec:
      containers:
      - name: fraud-detector
        image: nginx:1.25-alpine
        ports:
        - containerPort: 9090
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
MANIFEST

# ── Deploy Workload 4: audit-logger (2 replicas) ─────────────────────────────
echo "Deploying audit-logger..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: audit-logger
  namespace: payments-prod
  labels:
    app: audit-logger
    tier: observability
spec:
  replicas: 2
  selector:
    matchLabels:
      app: audit-logger
  template:
    metadata:
      labels:
        app: audit-logger
        tier: observability
    spec:
      containers:
      - name: audit-logger
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8081
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
MANIFEST

# NOTE: No ResourceQuota, LimitRange, HPA, or PDB are created — agent must implement them.

# ── Write the capacity governance specification document ──────────────────────
echo "Writing capacity governance specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/capacity_governance_spec.md << 'DOC'
# Payments Production Namespace — Capacity Governance Specification

## Namespace

`payments-prod`

## Overview

Following three resource-exhaustion incidents in Q4, the Platform Engineering team
has approved the following mandatory capacity governance controls for the `payments-prod`
namespace. All controls must be implemented before the next release window.

This document is the authoritative specification. Implement each control exactly
as described — names, values, and target workloads are prescriptive.

---

## Control 1: Namespace ResourceQuota

**Resource Name**: `payments-quota`
**Kind**: ResourceQuota
**Namespace**: `payments-prod`

Hard limits to enforce:

| Resource | Hard Limit |
|----------|-----------|
| `requests.cpu` | `4` |
| `requests.memory` | `8Gi` |
| `limits.cpu` | `8` |
| `limits.memory` | `16Gi` |
| `pods` | `20` |
| `services` | `10` |

These limits prevent any single namespace from exhausting cluster-wide resources.

---

## Control 2: Container Default LimitRange

**Resource Name**: `payments-limits`
**Kind**: LimitRange
**Namespace**: `payments-prod`

Default values applied to containers that do not specify resources:

| Type | Default CPU Limit | Default Memory Limit | Default CPU Request | Default Memory Request |
|------|-------------------|---------------------|--------------------|-----------------------|
| Container | `500m` | `512Mi` | `100m` | `128Mi` |

This prevents unbounded containers from consuming unlimited resources when
developers forget to set resource limits.

---

## Control 3: HorizontalPodAutoscaler for transaction-processor

**Resource Name**: `transaction-processor-hpa`
**Kind**: HorizontalPodAutoscaler
**Namespace**: `payments-prod`
**Target**: Deployment `transaction-processor`

Autoscaling parameters:

| Parameter | Value |
|-----------|-------|
| `minReplicas` | `2` |
| `maxReplicas` | `10` |
| CPU utilization target | `70%` |

The HPA must use `autoscaling/v2` API with a `Resource` metric type targeting
`cpu` with `AverageUtilization: 70`.

---

## Control 4: PodDisruptionBudget for payment-gateway

**Resource Name**: `payment-gateway-pdb`
**Kind**: PodDisruptionBudget
**Namespace**: `payments-prod`
**Target**: pods with label `app: payment-gateway`

Disruption budget:

| Parameter | Value |
|-----------|-------|
| `minAvailable` | `1` |

This ensures at least 1 payment-gateway replica remains available during
voluntary disruptions (node drains, rolling upgrades).

---

## Implementation Notes

- All resource names are prescriptive — use exactly the names specified above
- Do not modify or delete existing Deployments
- ResourceQuota and LimitRange take effect immediately upon creation
- The HPA requires the metrics-server to be running (already installed in the cluster)
- Verify each control using `kubectl describe` after creation
DOC

chown ga:ga /home/ga/Desktop/capacity_governance_spec.md

# ── Record baseline state ─────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/platform_capacity_governance_implementation_start_ts

# ── Navigate Firefox to the payments-prod namespace ───────────────────────────
echo "Navigating Firefox to payments-prod namespace..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=payments-prod" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=payments-prod' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/platform_capacity_governance_implementation_start.png

echo "=== platform_capacity_governance_implementation setup complete ==="
echo ""
echo "The payments-prod namespace has been created with 4 workloads but NO governance controls."
echo "Specification: /home/ga/Desktop/capacity_governance_spec.md"
echo "Agent must implement: ResourceQuota, LimitRange, HPA, and PodDisruptionBudget."
