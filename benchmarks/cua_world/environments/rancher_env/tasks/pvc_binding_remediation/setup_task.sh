#!/bin/bash
echo "=== Setting up pvc_binding_remediation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
# Simple wait loop if task_utils isn't loaded
for i in {1..30}; do
    if curl -sk -o /dev/null -w "%{http_code}" "https://localhost/v3" 2>/dev/null | grep -q "200\|401"; then
        break
    fi
    sleep 2
done

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-pipeline --wait=false 2>/dev/null || true
docker exec rancher kubectl delete pv analytics-pv --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating data-pipeline namespace..."
docker exec rancher kubectl create namespace data-pipeline 2>/dev/null || true

# ── Deploy broken PV, PVCs, and Deployments ───────────────────────────────────
echo "Deploying workloads with injected PVC failures..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
# ==========================================
# Failure 4 setup: Broken PV for analytics
# ==========================================
apiVersion: v1
kind: PersistentVolume
metadata:
  name: analytics-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /opt/local-path-provisioner/analytics
  claimRef:
    name: analytics-data
    namespace: default    # FAILURE: Wrong namespace (should be data-pipeline)
  storageClassName: ""
---
# ==========================================
# Workload 1: kafka-broker
# FAILURE: non-existent StorageClass 'premium-ssd'
# ==========================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kafka-data
  namespace: data-pipeline
spec:
  storageClassName: premium-ssd
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-broker
  namespace: data-pipeline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-broker
  template:
    metadata:
      labels:
        app: kafka-broker
    spec:
      containers:
      - name: kafka
        image: nginx:alpine
        volumeMounts:
        - name: data
          mountPath: /bitnami/kafka
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: kafka-data
---
# ==========================================
# Workload 2: minio-store
# FAILURE: Wrong access mode (ReadWriteMany not supported by local-path)
# ==========================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
  namespace: data-pipeline
spec:
  storageClassName: local-path
  accessModes: ["ReadWriteMany"]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio-store
  namespace: data-pipeline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio-store
  template:
    metadata:
      labels:
        app: minio-store
    spec:
      containers:
      - name: minio
        image: nginx:alpine
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: minio-data
---
# ==========================================
# Workload 3: elastic-search
# FAILURE: Excessive capacity request (500Gi)
# ==========================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: elastic-logs
  namespace: data-pipeline
spec:
  storageClassName: local-path
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 500Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elastic-search
  namespace: data-pipeline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elastic-search
  template:
    metadata:
      labels:
        app: elastic-search
    spec:
      containers:
      - name: elasticsearch
        image: nginx:alpine
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: elastic-logs
---
# ==========================================
# Workload 4: analytics-db
# FAILURE: PV claimRef namespace mismatch
# ==========================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: analytics-data
  namespace: data-pipeline
spec:
  storageClassName: ""
  volumeName: analytics-pv
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-db
  namespace: data-pipeline
spec:
  replicas: 1
  selector:
    matchLabels:
      app: analytics-db
  template:
    metadata:
      labels:
        app: analytics-db
    spec:
      containers:
      - name: db
        image: nginx:alpine
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: analytics-data
MANIFEST

echo "Waiting for pods to reach Pending state..."
sleep 5

# ── Set up Firefox UI ─────────────────────────────────────────────────────────
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard/c/local/explorer/persistentvolumeclaim &"
    sleep 5
fi

# Maximize and focus Firefox window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot showing the broken PVCs
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="