#!/bin/bash
# Setup script for resource_governance_implementation task
# Creates 3 fintech namespaces with workloads but NO resource quotas or limit ranges.
# Drops a governance specification file on the desktop for the agent to implement.

echo "=== Setting up resource_governance_implementation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
for ns in fintech-prod fintech-staging fintech-dev; do
    docker exec rancher kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
done

# Wait for namespace deletion
sleep 8

# ── Create namespaces ─────────────────────────────────────────────────────────
echo "Creating fintech namespaces..."
for ns in fintech-prod fintech-staging fintech-dev; do
    docker exec rancher kubectl create namespace "$ns" 2>/dev/null || true
done

# ── Deploy workloads WITHOUT resource limits (this is the problem) ────────────
echo "Deploying workloads without resource governance..."

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: fintech-prod
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payment-api
  template:
    metadata:
      labels:
        app: payment-api
    spec:
      containers:
      - name: payment-api
        image: nginx:alpine
        # No resource requests or limits - governance violation
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fraud-detection
  namespace: fintech-prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fraud-detection
  template:
    metadata:
      labels:
        app: fraud-detection
    spec:
      containers:
      - name: fraud-detection
        image: nginx:alpine
        # No resource requests or limits - governance violation
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api-staging
  namespace: fintech-staging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-api-staging
  template:
    metadata:
      labels:
        app: payment-api-staging
    spec:
      containers:
      - name: payment-api-staging
        image: nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: developer-tools
  namespace: fintech-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: developer-tools
  template:
    metadata:
      labels:
        app: developer-tools
    spec:
      containers:
      - name: developer-tools
        image: nginx:alpine
MANIFEST

# ── Drop the governance specification file on the desktop ────────────────────
echo "Writing governance specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/resource_governance_spec.yaml << 'SPEC'
# Fintech Platform Resource Governance Specification
# Version: 2.1
# Owner: Platform Engineering Team
# Effective Date: 2024-Q1
#
# All namespaces must have ResourceQuota and LimitRange objects applied.
# Non-compliance blocks namespace promotion to production.

namespaces:

  fintech-prod:
    tier: production
    resourcequota:
      name: fintech-prod-quota
      hard:
        requests.cpu: "16"
        requests.memory: "32Gi"
        limits.cpu: "32"
        limits.memory: "64Gi"
        pods: "50"
        services: "20"
        persistentvolumeclaims: "10"
    limitrange:
      name: fintech-prod-limits
      limits:
        - type: Container
          default:
            cpu: "500m"
            memory: "512Mi"
          defaultRequest:
            cpu: "250m"
            memory: "256Mi"
          max:
            cpu: "4"
            memory: "8Gi"
          min:
            cpu: "50m"
            memory: "64Mi"
        - type: Pod
          max:
            cpu: "8"
            memory: "16Gi"

  fintech-staging:
    tier: staging
    resourcequota:
      name: fintech-staging-quota
      hard:
        requests.cpu: "8"
        requests.memory: "16Gi"
        limits.cpu: "16"
        limits.memory: "32Gi"
        pods: "30"
        services: "15"
        persistentvolumeclaims: "5"
    limitrange:
      name: fintech-staging-limits
      limits:
        - type: Container
          default:
            cpu: "250m"
            memory: "256Mi"
          defaultRequest:
            cpu: "100m"
            memory: "128Mi"
          max:
            cpu: "2"
            memory: "4Gi"
          min:
            cpu: "25m"
            memory: "32Mi"

  fintech-dev:
    tier: development
    # No ResourceQuota for dev (developers need flexibility)
    limitrange:
      name: fintech-dev-limits
      limits:
        - type: Container
          default:
            cpu: "200m"
            memory: "256Mi"
          defaultRequest:
            cpu: "100m"
            memory: "128Mi"
          max:
            cpu: "1"
            memory: "2Gi"
          min:
            cpu: "10m"
            memory: "16Mi"
SPEC

chown ga:ga /home/ga/Desktop/resource_governance_spec.yaml

# ── Record baseline (no quotas exist yet) ────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/resource_governance_implementation_start_ts

PROD_QUOTA=$(docker exec rancher kubectl get resourcequota -n fintech-prod --no-headers 2>/dev/null | wc -l | tr -d ' ')
STAGING_QUOTA=$(docker exec rancher kubectl get resourcequota -n fintech-staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
PROD_LR=$(docker exec rancher kubectl get limitrange -n fintech-prod --no-headers 2>/dev/null | wc -l | tr -d ' ')
STAGING_LR=$(docker exec rancher kubectl get limitrange -n fintech-staging --no-headers 2>/dev/null | wc -l | tr -d ' ')
DEV_LR=$(docker exec rancher kubectl get limitrange -n fintech-dev --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "Baseline quotas - prod:$PROD_QUOTA staging:$STAGING_QUOTA"
echo "Baseline limitranges - prod:$PROD_LR staging:$STAGING_LR dev:$DEV_LR"

# ── Navigate Firefox to Rancher namespace view ────────────────────────────────
echo "Navigating Firefox to Rancher..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/namespace" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/namespace' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

if ! wait_for_window "firefox\|mozilla\|rancher" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/resource_governance_implementation_start.png

echo "=== resource_governance_implementation setup complete ==="
echo ""
echo "3 fintech namespaces created WITHOUT resource governance."
echo "Governance specification is at: /home/ga/Desktop/resource_governance_spec.yaml"
echo ""
