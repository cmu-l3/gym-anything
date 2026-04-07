#!/bin/bash
# Setup script for health_probe_remediation task
# Injects 4 health probe misconfigurations into the 'services' namespace

echo "=== Setting up health_probe_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up any previous run ───────────────────────────────────────────────
echo "Cleaning up previous services namespace..."
docker exec rancher kubectl delete namespace services --timeout=60s 2>/dev/null || true
sleep 5

# ── Create the services namespace ──────────────────────────────────────────
echo "Creating services namespace..."
docker exec rancher kubectl create namespace services 2>/dev/null || true

# ── Write the health check specification to the desktop ─────────────────────
echo "Writing health check specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/health_check_spec.yaml << 'EOF'
# Health Check Specification for services namespace
# All deployments must have liveness and readiness probes configured.
# Probes must match the specifications below.

api-server:
  image: nginx:1.25
  container_port: 80
  notes: "Health endpoint is at root path (/). The /healthz path does NOT exist."
  liveness:
    type: httpGet
    path: /
    port: 80
    initialDelaySeconds: 15
    periodSeconds: 20
    timeoutSeconds: 5
    failureThreshold: 3
  readiness:
    type: httpGet
    path: /
    port: 80
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 3

worker-service:
  image: redis:7-alpine
  container_port: 6379
  notes: "Redis health is verified via TCP socket connectivity."
  liveness:
    type: tcpSocket
    port: 6379
    initialDelaySeconds: 15
    periodSeconds: 20
    timeoutSeconds: 5
    failureThreshold: 3
  readiness:
    type: tcpSocket
    port: 6379
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 3

auth-service:
  image: nginx:1.25
  container_port: 80
  notes: "Previous probe timing was too aggressive causing unnecessary restarts."
  liveness:
    type: httpGet
    path: /
    port: 80
    initialDelaySeconds: 15
    periodSeconds: 20
    timeoutSeconds: 5
    failureThreshold: 3
  readiness:
    type: httpGet
    path: /
    port: 80
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 3

notification-service:
  image: nginx:1.25
  container_port: 80
  notes: "Currently has NO probes. Both must be added."
  liveness:
    type: httpGet
    path: /
    port: 80
    initialDelaySeconds: 15
    periodSeconds: 20
    timeoutSeconds: 5
    failureThreshold: 3
  readiness:
    type: httpGet
    path: /
    port: 80
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 3
EOF
chown ga:ga /home/ga/Desktop/health_check_spec.yaml

# ── Deploy the broken microservices ──────────────────────────────────────────
echo "Deploying microservices with injected probe failures..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
---
# Failure 1: api-server probes /healthz (nginx returns 404, causes CrashLoopBackOff)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: services
  labels:
    app: api-server
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
      containers:
      - name: api-server
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
---
# Failure 2: worker-service has NO readiness probe
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-service
  namespace: services
  labels:
    app: worker-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: worker-service
  template:
    metadata:
      labels:
        app: worker-service
    spec:
      containers:
      - name: worker-service
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        livenessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 15
          periodSeconds: 20
          failureThreshold: 3
---
# Failure 3: auth-service has overly aggressive probe timings.
# Simulated slow start using 'sleep 5' before nginx so it consistently fails liveness.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: services
  labels:
    app: auth-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
      - name: auth-service
        image: nginx:1.25-alpine
        command: ["/bin/sh", "-c", "sleep 5 && nginx -g 'daemon off;'"]
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 1
          periodSeconds: 2
          failureThreshold: 1
          timeoutSeconds: 1
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
---
# Failure 4: notification-service has NO probes at all
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service
  namespace: services
  labels:
    app: notification-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notification-service
  template:
    metadata:
      labels:
        app: notification-service
    spec:
      containers:
      - name: notification-service
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
MANIFEST

# Record baseline state timestamp
date +%s > /tmp/health_probe_remediation_start_ts

echo "=== Task Setup Complete ==="