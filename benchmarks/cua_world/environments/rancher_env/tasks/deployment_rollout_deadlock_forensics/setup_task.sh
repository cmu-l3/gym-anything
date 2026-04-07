#!/bin/bash
# Setup script for deployment_rollout_deadlock_forensics task
# Injects 3 deadlocked deployments in the financial-ops namespace

echo "=== Setting up deployment_rollout_deadlock_forensics task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace financial-ops --wait=false 2>/dev/null || true
docker exec rancher rm -rf /tmp/ledger-lock 2>/dev/null || true
sleep 10

# ── Create namespace and infrastructure ───────────────────────────────────────
echo "Creating financial-ops namespace and infrastructure..."
docker exec rancher kubectl create namespace financial-ops 2>/dev/null || true
docker exec rancher mkdir -p /tmp/ledger-lock
docker exec rancher chmod 777 /tmp/ledger-lock

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: financial-ops
spec:
  hard:
    requests.cpu: "2"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secret-reader
  namespace: financial-ops
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader-role
  namespace: financial-ops
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-reader-binding
  namespace: financial-ops
subjects:
- kind: ServiceAccount
  name: secret-reader
roleRef:
  kind: Role
  name: secret-reader-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ledger-script
  namespace: financial-ops
data:
  lock.py: |
    import fcntl, time, sys, os
    os.makedirs('/mnt/lock', exist_ok=True)
    lockfile = '/mnt/lock/ledger.lock'
    with open(lockfile, 'w') as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print("Lock acquired. Running " + os.environ.get('VERSION', 'unknown'), flush=True)
            while True:
                time.sleep(10)
        except BlockingIOError:
            print("FATAL: Could not acquire database lock. Another instance is running.", file=sys.stderr, flush=True)
            sys.exit(1)
MANIFEST

# ── Deploy v1 of all services ─────────────────────────────────────────────────
echo "Deploying v1 services..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-writer
  namespace: financial-ops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger-writer
  template:
    metadata:
      labels:
        app: ledger-writer
    spec:
      containers:
      - name: writer
        image: python:3.9-alpine
        command: ["python3", "/scripts/lock.py"]
        env:
        - name: VERSION
          value: "v1"
        volumeMounts:
        - name: lock-dir
          mountPath: /mnt/lock
        - name: script-dir
          mountPath: /scripts
      volumes:
      - name: lock-dir
        hostPath:
          path: /tmp/ledger-lock
          type: DirectoryOrCreate
      - name: script-dir
        configMap:
          name: ledger-script
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: risk-analyzer
  namespace: financial-ops
spec:
  replicas: 4
  selector:
    matchLabels:
      app: risk-analyzer
  template:
    metadata:
      labels:
        app: risk-analyzer
    spec:
      containers:
      - name: analyzer
        image: nginx:alpine
        env:
        - name: VERSION
          value: "v1"
        resources:
          requests:
            cpu: "500m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compliance-api
  namespace: financial-ops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: compliance-api
  template:
    metadata:
      labels:
        app: compliance-api
    spec:
      containers:
      - name: api
        image: bitnami/kubectl:latest
        command: ["/bin/sh", "-c", "echo 'v1 running'; sleep infinity"]
        env:
        - name: VERSION
          value: "v1"
MANIFEST

echo "Waiting for v1 pods to become healthy..."
docker exec rancher kubectl rollout status deploy/ledger-writer -n financial-ops --timeout=60s || true
docker exec rancher kubectl rollout status deploy/risk-analyzer -n financial-ops --timeout=60s || true
docker exec rancher kubectl rollout status deploy/compliance-api -n financial-ops --timeout=60s || true
sleep 3

# ── Trigger v2 rollouts (injecting deadlocks) ─────────────────────────────────
echo "Triggering v2 updates (creating deadlocks)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-writer
  namespace: financial-ops
spec:
  template:
    spec:
      containers:
      - name: writer
        env:
        - name: VERSION
          value: "v2"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: risk-analyzer
  namespace: financial-ops
spec:
  template:
    spec:
      containers:
      - name: analyzer
        env:
        - name: VERSION
          value: "v2"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compliance-api
  namespace: financial-ops
spec:
  template:
    spec:
      containers:
      - name: api
        command: ["/bin/sh", "-c", "echo 'v2 starting'; kubectl get secrets -n financial-ops || { echo 'RBAC Denial: Cannot read secrets'; exit 1; }; echo 'Success'; sleep infinity"]
        env:
        - name: VERSION
          value: "v2"
MANIFEST

# Give k8s a moment to start the rollouts and get stuck
sleep 10

# Maximize Firefox for the agent
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="