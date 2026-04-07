#!/bin/bash
# Setup script for production_incident_response task
# Injects 4 realistic failures into the 'ecommerce' namespace

echo "=== Setting up production_incident_response task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up any previous run ───────────────────────────────────────────────
echo "Cleaning up previous ecommerce namespace..."
docker exec rancher kubectl delete namespace ecommerce --timeout=60s 2>/dev/null || true
sleep 5

# ── Create the ecommerce namespace ──────────────────────────────────────────
echo "Creating ecommerce namespace..."
docker exec rancher kubectl create namespace ecommerce 2>/dev/null || true

# ── Inject Failure 1: api-gateway with non-existent image ──────────────────
# Real nginx images exist; nginx:broken-tag-xyz-nonexistent does not
echo "Deploying api-gateway..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: ecommerce
  labels:
    app: api-gateway
    tier: gateway
    environment: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        tier: gateway
    spec:
      containers:
      - name: api-gateway
        image: nginx:broken-tag-xyz-nonexistent
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: ecommerce
spec:
  selector:
    app: api-gateway
  ports:
  - port: 80
    targetPort: 80
MANIFEST

# ── Inject Failure 2: web-frontend with Service selector mismatch ──────────
# Pods have label app=frontend-app, Service selects app=web-frontend (mismatch)
echo "Deploying web-frontend with Service selector mismatch..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  namespace: ecommerce
  labels:
    app: web-frontend
    tier: frontend
    environment: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend-app
  template:
    metadata:
      labels:
        app: frontend-app
        tier: frontend
    spec:
      containers:
      - name: web-frontend
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: web-frontend
  namespace: ecommerce
spec:
  selector:
    app: web-frontend
  ports:
  - port: 80
    targetPort: 80
MANIFEST

# ── Inject Failure 3: cache-layer with wrong Redis port in ConfigMap ────────
# REDIS_PORT should be 6379 but is set to 6380 (wrong)
echo "Deploying cache-layer..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cache-config
  namespace: ecommerce
data:
  REDIS_HOST: "redis-primary.staging.svc.cluster.local"
  REDIS_PORT: "6380"
  REDIS_MAX_CONNECTIONS: "50"
  REDIS_TIMEOUT: "5000"
  CACHE_TTL: "3600"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-layer
  namespace: ecommerce
  labels:
    app: cache-layer
    tier: cache
    environment: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache-layer
  template:
    metadata:
      labels:
        app: cache-layer
        tier: cache
    spec:
      containers:
      - name: cache-layer
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: cache-config
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
MANIFEST

# ── Inject Failure 4: batch-processor with excessive memory request ─────────
# Requesting 32Gi memory will keep pod in Pending state (no node has that much)
echo "Deploying batch-processor with excessive memory request (Pending)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
  namespace: ecommerce
  labels:
    app: batch-processor
    tier: worker
    environment: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: batch-processor
  template:
    metadata:
      labels:
        app: batch-processor
        tier: worker
    spec:
      containers:
      - name: batch-processor
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "500m"
            memory: "32Gi"
          limits:
            cpu: "2"
            memory: "64Gi"
MANIFEST

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/production_incident_response_start_ts

INITIAL_API_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce -l app=api-gateway --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
INITIAL_FRONTEND_ENDPOINTS=$(docker exec rancher kubectl get endpoints web-frontend -n ecommerce -o jsonpath='{.subsets}' 2>/dev/null)
INITIAL_REDIS_PORT=$(docker exec rancher kubectl get configmap cache-config -n ecommerce -o jsonpath='{.data.REDIS_PORT}' 2>/dev/null)
INITIAL_BATCH_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce -l app=batch-processor --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

cat > /tmp/production_incident_response_baseline.json <<EOF
{
  "api_gateway_running": ${INITIAL_API_RUNNING:-0},
  "frontend_has_endpoints": false,
  "cache_redis_port": "${INITIAL_REDIS_PORT:-6380}",
  "batch_processor_running": ${INITIAL_BATCH_RUNNING:-0}
}
EOF

echo "Baseline: api_running=${INITIAL_API_RUNNING}, cache_port=${INITIAL_REDIS_PORT}, batch_running=${INITIAL_BATCH_RUNNING}"

# ── Navigate Firefox to ecommerce namespace workloads ───────────────────────
echo "Navigating Firefox to ecommerce namespace..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=ecommerce" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=ecommerce' > /tmp/firefox_task.log 2>&1 &"
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
take_screenshot /tmp/production_incident_response_start.png

echo "=== production_incident_response setup complete ==="
echo ""
echo "The ecommerce namespace has been created with 4 broken microservices."
echo "The agent must diagnose and fix all failures."
echo ""
