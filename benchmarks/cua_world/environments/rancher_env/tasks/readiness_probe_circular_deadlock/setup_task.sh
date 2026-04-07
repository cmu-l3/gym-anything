#!/bin/bash
# Setup script for readiness_probe_circular_deadlock task
# Injects a circular dependency between two services' readiness probes

echo "=== Setting up readiness_probe_circular_deadlock task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace ecommerce-core --wait=false 2>/dev/null || true
sleep 8

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating ecommerce-core namespace..."
docker exec rancher kubectl create namespace ecommerce-core 2>/dev/null || true

# ── Deploy the deadlocked services ────────────────────────────────────────────
echo "Deploying deadlocked services..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: health-config
  namespace: ecommerce-core
data:
  default.conf: |
    server {
        listen 8080;
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-service
  namespace: ecommerce-core
  labels:
    app: checkout
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d/
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            # CIRCULAR DEPENDENCY: Checks inventory-service before marking itself ready
            - "wget -qO- http://inventory-service.ecommerce-core.svc.cluster.local:8080/health && wget -qO- http://localhost:8080/health"
          initialDelaySeconds: 2
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: health-config
---
apiVersion: v1
kind: Service
metadata:
  name: checkout-service
  namespace: ecommerce-core
spec:
  selector:
    app: checkout
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-service
  namespace: ecommerce-core
  labels:
    app: inventory
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory
  template:
    metadata:
      labels:
        app: inventory
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d/
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            # CIRCULAR DEPENDENCY: Checks checkout-service before marking itself ready
            - "wget -qO- http://checkout-service.ecommerce-core.svc.cluster.local:8080/health && wget -qO- http://localhost:8080/health"
          initialDelaySeconds: 2
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: health-config
---
apiVersion: v1
kind: Service
metadata:
  name: inventory-service
  namespace: ecommerce-core
spec:
  selector:
    app: inventory
  ports:
  - port: 8080
    targetPort: 8080
MANIFEST

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait to allow pods to reach running (but unready) state
echo "Waiting for pods to enter 0/1 state..."
sleep 15

# Focus Firefox and maximize if UI is available
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="