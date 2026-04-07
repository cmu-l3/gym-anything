#!/bin/bash
echo "=== Setting up deployment_rollback_recovery task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for Rancher API..."
# Wait up to 60s for the Rancher API to become responsive
for i in {1..20}; do
    if curl -sk -o /dev/null -w "%{http_code}" "https://localhost/v3" 2>/dev/null | grep -q "200\|401"; then
        break
    fi
    sleep 3
done

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace release-management --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating release-management namespace..."
docker exec rancher kubectl create namespace release-management 2>/dev/null || true

# ── Deploy frontend-web with revisions ────────────────────────────────────────
echo "Injecting Failure 1: frontend-web (ImagePullBackOff)..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-web
  namespace: release-management
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend-web
  template:
    metadata:
      labels:
        app: frontend-web
    spec:
      containers:
      - name: nginx
        image: nginx:1.24-alpine
EOF
sleep 2
docker exec rancher kubectl set image deployment/frontend-web nginx=nginx:1.25-alpine -n release-management
sleep 2
docker exec rancher kubectl set image deployment/frontend-web nginx=nginx:1.26-alpine -n release-management
sleep 2
docker exec rancher kubectl set image deployment/frontend-web nginx=nginx:1.99.0 -n release-management

# ── Deploy api-backend with bad strategy ──────────────────────────────────────
echo "Injecting Failure 2: api-backend (Recreate strategy)..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
  namespace: release-management
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: api-backend
  template:
    metadata:
      labels:
        app: api-backend
    spec:
      containers:
      - name: api
        image: nginx:1.26-alpine
EOF

# ── Deploy data-processor and pause rollout ───────────────────────────────────
echo "Injecting Failure 3: data-processor (Paused rollout)..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-processor
  namespace: release-management
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
      - name: processor
        image: busybox:1.35
        command: ["sleep", "3600"]
EOF
sleep 2
docker exec rancher kubectl set image deployment/data-processor processor=busybox:1.36 -n release-management
docker exec rancher kubectl rollout pause deployment/data-processor -n release-management

# ── Deploy notification-service with broken command ───────────────────────────
echo "Injecting Failure 4: notification-service (CrashLoopBackOff)..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service
  namespace: release-management
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
      - name: worker
        image: busybox:1.36
        command: ["sleep", "3600"]
EOF
sleep 2
docker exec rancher kubectl patch deployment notification-service -n release-management --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["/bin/sh", "-c", "exit 1"]}]'

# ── Launch Firefox ────────────────────────────────────────────────────────────
echo "Ensuring Firefox is running and focused on Rancher..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="