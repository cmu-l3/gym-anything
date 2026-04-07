#!/bin/bash
# Setup script for pvc_data_migration_workflow
# Sets up the legacy PVC, deployment, and injects real data into the volume.

echo "=== Setting up pvc_data_migration_workflow task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace catalog --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating catalog namespace..."
docker exec rancher kubectl create namespace catalog 2>/dev/null || true

# ── Deploy Legacy PVC and Deployment ──────────────────────────────────────────
echo "Deploying legacy PVC and catalog-service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: catalog-data-legacy
  namespace: catalog
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-service
  namespace: catalog
  labels:
    app: catalog-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog-service
  template:
    metadata:
      labels:
        app: catalog-service
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: catalog-storage
          mountPath: /usr/share/nginx/html/data
      volumes:
      - name: catalog-storage
        persistentVolumeClaim:
          claimName: catalog-data-legacy
MANIFEST

# ── Wait for pod to be running ────────────────────────────────────────────────
echo "Waiting for catalog-service pod to start..."
for i in {1..60}; do
    PHASE=$(docker exec rancher kubectl get pods -n catalog -l app=catalog-service -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Running" ]; then
        echo "catalog-service pod is Running."
        break
    fi
    sleep 2
done

# ── Download and Inject Real Data ─────────────────────────────────────────────
echo "Preparing real dataset for migration..."

# Download Chinook SQLite database (public sample DB)
docker exec rancher sh -c 'curl -sL -o /tmp/chinook.db https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite'

# Fallback in case of network issues inside container
if ! docker exec rancher test -s /tmp/chinook.db; then
    echo "Fallback: creating synthetic binary data..."
    docker exec rancher sh -c 'dd if=/dev/urandom of=/tmp/chinook.db bs=1024 count=884 2>/dev/null'
fi

# Generate metadata with a unique ID to prevent gaming
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "123e4567-e89b-12d3-a456-426614174000")
docker exec rancher sh -c "cat > /tmp/catalog-metadata.json <<EOF
{
  \"version\": \"1.0\",
  \"migration_id\": \"$UUID\",
  \"description\": \"Product catalog metadata\",
  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}
EOF"

# Compute ground-truth checksums
MD5_CHINOOK=$(docker exec rancher md5sum /tmp/chinook.db | awk '{print $1}')
MD5_META=$(docker exec rancher md5sum /tmp/catalog-metadata.json | awk '{print $1}')

# Save ground truth locally on the host (hidden from agent)
cat > /tmp/ground_truth_checksums.json <<EOF
{
  "chinook": "$MD5_CHINOOK",
  "metadata": "$MD5_META"
}
EOF

# Copy data into the running pod's PVC
POD_NAME=$(docker exec rancher kubectl get pod -n catalog -l app=catalog-service -o jsonpath='{.items[0].metadata.name}')
echo "Copying data into pod: $POD_NAME"

docker exec rancher kubectl cp /tmp/chinook.db catalog/${POD_NAME}:/usr/share/nginx/html/data/chinook.db
docker exec rancher kubectl cp /tmp/catalog-metadata.json catalog/${POD_NAME}:/usr/share/nginx/html/data/catalog-metadata.json

# Cleanup temp files in rancher container
docker exec rancher rm -f /tmp/chinook.db /tmp/catalog-metadata.json

# Take an initial screenshot
take_screenshot /tmp/pvc_data_migration_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="