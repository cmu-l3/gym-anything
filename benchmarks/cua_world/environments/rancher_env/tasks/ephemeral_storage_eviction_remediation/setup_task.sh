#!/bin/bash
# Setup script for ephemeral_storage_eviction_remediation
# Injects a deployment that gets evicted due to 3 layers of ephemeral storage limits:
# 1. emptyDir sizeLimit (50Mi) vs 200Mi workload
# 2. container limits.ephemeral-storage (100Mi) vs 200Mi workload
# 3. ResourceQuota (400Mi) blocks scaling 2 replicas of >= 250Mi

echo "=== Setting up ephemeral_storage_eviction_remediation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for Rancher API..."
for i in {1..20}; do
    if docker exec rancher kubectl get nodes >/dev/null 2>&1; then
        break
    fi
    sleep 3
done

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace ml-workloads --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating ml-workloads namespace..."
docker exec rancher kubectl create namespace ml-workloads 2>/dev/null || true

# ── 1. Create LimitRange (forces default limits if agent deletes them) ────────
echo "Applying LimitRange..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: ml-limit-range
  namespace: ml-workloads
spec:
  limits:
  - default:
      ephemeral-storage: 100Mi
    defaultRequest:
      ephemeral-storage: 100Mi
    type: Container
EOF

# ── 2. Create ResourceQuota (blocks scaling up once container limits are fixed) 
echo "Applying ResourceQuota..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ml-storage-quota
  namespace: ml-workloads
spec:
  hard:
    limits.ephemeral-storage: "400Mi"
EOF

# ── 3. Create Deployment with storage constraint failures ─────────────────────
echo "Deploying ml-inference with storage constraints..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference
  namespace: ml-workloads
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ml-inference
  template:
    metadata:
      labels:
        app: ml-inference
    spec:
      initContainers:
      - name: model-loader
        image: busybox:1.36.1
        # Writes 200MB, then sleeps 15s so Kubelet has time to measure and Evict
        command: ["/bin/sh", "-c", "dd if=/dev/zero of=/cache/model.bin bs=1M count=200 && sleep 15"]
        volumeMounts:
        - name: model-cache
          mountPath: /cache
        resources:
          limits:
            ephemeral-storage: "100Mi"
          requests:
            ephemeral-storage: "100Mi"
      containers:
      - name: inference-server
        image: nginx:alpine
        volumeMounts:
        - name: model-cache
          mountPath: /usr/share/nginx/html/model
      volumes:
      - name: model-cache
        emptyDir:
          sizeLimit: "50Mi"
EOF

echo "Recording task start time..."
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="