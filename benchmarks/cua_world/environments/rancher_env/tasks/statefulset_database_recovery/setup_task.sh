#!/bin/bash
# Setup script for statefulset_database_recovery task
# Injects 4 failures into a PostgreSQL StatefulSet:
#   1. Wrong StorageClass (premium-ssd vs available local-path)
#   2. Wrong volume mount path (/var/lib/psql vs /var/lib/postgresql/data)
#   3. Excessive memory request (32Gi - causes Pending)
#   4. Missing Secret reference (references non-existent secret)

echo "=== Setting up statefulset_database_recovery task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-platform --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating data-platform namespace..."
docker exec rancher kubectl create namespace data-platform 2>/dev/null || true

# ── Create the CORRECT secret (exists but with wrong name referenced by StatefulSet) ─
# The correct secret should be named 'postgres-credentials'
# The StatefulSet will reference 'postgres-db-secret' which does NOT exist
echo "Creating postgres-credentials secret..."
docker exec rancher kubectl create secret generic postgres-credentials \
    -n data-platform \
    --from-literal=POSTGRES_USER=pgadmin \
    --from-literal=POSTGRES_PASSWORD=SecureP@ss2024 \
    --from-literal=POSTGRES_DB=appdb \
    2>/dev/null || true

# ── Deploy the broken StatefulSet with 4 injected failures ───────────────────
echo "Deploying broken PostgreSQL StatefulSet with injected failures..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
# ── Broken StorageClass for PVC ──────────────────────────────────────────────
# Failure 1: StorageClass 'premium-ssd' does not exist in this cluster
# The available StorageClass is 'local-path'
# Failure 2: Volume mount path is wrong (/var/lib/psql instead of /var/lib/postgresql/data)
# Failure 3: Memory request of 32Gi will cause pods to be Pending (node has ~8GB)
# Failure 4: Env secret references 'postgres-db-secret' which does not exist
#            (correct name is 'postgres-credentials')
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-primary
  namespace: data-platform
  labels:
    app: postgres-primary
    component: database
    environment: production
spec:
  serviceName: postgres-primary-headless
  replicas: 1
  selector:
    matchLabels:
      app: postgres-primary
  template:
    metadata:
      labels:
        app: postgres-primary
        component: database
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-db-secret    # FAILURE 4: wrong secret name (should be postgres-credentials)
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-db-secret    # FAILURE 4: wrong secret name
              key: POSTGRES_PASSWORD
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: postgres-db-secret    # FAILURE 4: wrong secret name
              key: POSTGRES_DB
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            memory: "32Gi"              # FAILURE 3: excessive (should be ~512Mi or similar)
            cpu: "500m"
          limits:
            memory: "64Gi"
            cpu: "2"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/psql      # FAILURE 2: wrong path (should be /var/lib/postgresql/data)
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - pgadmin
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - pgadmin
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: premium-ssd    # FAILURE 1: StorageClass doesn't exist (should be local-path)
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-primary-headless
  namespace: data-platform
  labels:
    app: postgres-primary
spec:
  clusterIP: None
  selector:
    app: postgres-primary
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-primary
  namespace: data-platform
spec:
  selector:
    app: postgres-primary
  ports:
  - port: 5432
    targetPort: 5432
MANIFEST

# ── Record baseline state ─────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/statefulset_database_recovery_start_ts

sleep 5

PODS_RUNNING=$(docker exec rancher kubectl get pods -n data-platform \
    -l app=postgres-primary --field-selector status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')

STS_REPLICAS=$(docker exec rancher kubectl get statefulset postgres-primary \
    -n data-platform -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

echo "Baseline: pods_running=$PODS_RUNNING, replicas=$STS_REPLICAS"
echo "Expected: pods_running=0 (all failures prevent scheduling/running)"

# ── Navigate Firefox ──────────────────────────────────────────────────────────
echo "Navigating Firefox to StatefulSet view..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.statefulset/data-platform/postgres-primary" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.statefulset/data-platform/postgres-primary' > /tmp/firefox_task.log 2>&1 &"
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
take_screenshot /tmp/statefulset_database_recovery_start.png

echo "=== statefulset_database_recovery setup complete ==="
echo ""
echo "postgres-primary StatefulSet in data-platform namespace has been set up with failures."
echo "The StatefulSet should have 0 pods running."
echo ""
