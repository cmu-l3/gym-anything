#!/bin/bash
# Setup script for statefulset_database_cluster_restoration
# Creates data-platform namespace with a PostgreSQL StatefulSet containing 4 injected misconfigurations.
# Agent must read the runbook and fix all failures.

echo "=== Setting up statefulset_database_cluster_restoration ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready, proceeding anyway"
fi

# ── Clean up any previous run ────────────────────────────────────────────────
echo "Cleaning up previous data-platform namespace..."
docker exec rancher kubectl delete namespace data-platform --timeout=60s 2>/dev/null || true
sleep 8

# ── Create namespace ─────────────────────────────────────────────────────────
echo "Creating data-platform namespace..."
docker exec rancher kubectl create namespace data-platform 2>/dev/null || true
docker exec rancher kubectl label namespace data-platform team=data-engineering environment=production 2>/dev/null || true

# ── INJECTED FAILURE 2: Secret has wrong key name 'DB_PASSWORD' ──────────────
# Correct key should be 'POSTGRES_PASSWORD' (required by postgres image)
echo "Creating postgres-credentials Secret (with injected wrong key name)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: data-platform
  labels:
    app: postgres-cluster
type: Opaque
stringData:
  DB_PASSWORD: "Sup3rS3cur3DBPass!"
  POSTGRES_USER: "pgadmin"
  POSTGRES_DB: "healthdata"
MANIFEST

# ── Create StorageClass (use local-path which K3s provides) ──────────────────
echo "Verifying local-path StorageClass exists..."
docker exec rancher kubectl get storageclass local-path 2>/dev/null || true

# ── INJECTED FAILURE 4: Headless Service missing clusterIP: None ─────────────
# clusterIP should be None for StatefulSet DNS to work
echo "Creating postgres-cluster Service (with injected: non-headless)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: postgres-cluster
  namespace: data-platform
  labels:
    app: postgres-cluster
spec:
  selector:
    app: postgres-cluster
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
  type: ClusterIP
MANIFEST

# ── Create read Service (correct — for external access) ──────────────────────
echo "Creating postgres-cluster-read Service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: postgres-cluster-read
  namespace: data-platform
  labels:
    app: postgres-cluster
spec:
  selector:
    app: postgres-cluster
  ports:
  - name: postgres
    port: 5432
    targetPort: 5432
  type: ClusterIP
MANIFEST

# ── INJECTED FAILURES 1 and 3: StatefulSet with wrong image tag and missing resource requests ──
echo "Deploying postgres-cluster StatefulSet (with injected failures: wrong image tag, missing resource requests)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-cluster
  namespace: data-platform
  labels:
    app: postgres-cluster
    tier: database
spec:
  serviceName: postgres-cluster
  replicas: 3
  selector:
    matchLabels:
      app: postgres-cluster
  template:
    metadata:
      labels:
        app: postgres-cluster
        tier: database
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: postgres
        image: postgres:14-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: DB_PASSWORD
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_USER
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: POSTGRES_DB
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - pgadmin
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 6
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - pgadmin
          initialDelaySeconds: 10
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: local-path
      resources:
        requests:
          storage: 1Gi
MANIFEST

# ── Deploy a pgbouncer connection pooler ─────────────────────────────────────
echo "Deploying pgbouncer connection pooler..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
  namespace: data-platform
  labels:
    app: pgbouncer
    tier: middleware
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgbouncer
  template:
    metadata:
      labels:
        app: pgbouncer
        tier: middleware
    spec:
      containers:
      - name: pgbouncer
        image: bitnami/pgbouncer:1.21.0
        ports:
        - containerPort: 6432
        env:
        - name: POSTGRESQL_HOST
          value: "postgres-cluster.data-platform.svc.cluster.local"
        - name: POSTGRESQL_PORT
          value: "5432"
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
MANIFEST

# ── Deploy a monitoring exporter ──────────────────────────────────────────────
echo "Deploying postgres-exporter..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: data-platform
  labels:
    app: postgres-exporter
    tier: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
        tier: monitoring
    spec:
      containers:
      - name: postgres-exporter
        image: prometheuscommunity/postgres-exporter:v0.15.0
        ports:
        - containerPort: 9187
        env:
        - name: DATA_SOURCE_NAME
          value: "postgresql://pgadmin@postgres-cluster.data-platform.svc.cluster.local:5432/healthdata?sslmode=disable"
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
MANIFEST

# ── Write the database cluster runbook ───────────────────────────────────────
echo "Writing database cluster runbook to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/database_cluster_runbook.md << 'DOC'
# PostgreSQL Cluster — Platform Runbook

## Namespace

`data-platform`

## Cluster Overview

The `postgres-cluster` is a 3-replica PostgreSQL StatefulSet providing high-availability
storage for the healthcare data platform. It uses the official PostgreSQL Docker image
and is managed through Kubernetes StatefulSet ordered pod management.

---

## Required Configuration

### 1. Container Image

The StatefulSet `postgres-cluster` must use:
```
image: postgres:15-alpine
```

**Not** `postgres:14-alpine` or any other tag. PostgreSQL 15 is required for:
- JSON path expressions used in the application
- Logical replication improvements
- Row-level security performance improvements

### 2. Secret: `postgres-credentials`

The Secret `postgres-credentials` in namespace `data-platform` must contain the
following keys (names are exact — the postgres Docker image reads these env vars):

| Key | Description |
|-----|-------------|
| `POSTGRES_PASSWORD` | Database superuser password (NOT `DB_PASSWORD`) |
| `POSTGRES_USER` | Database superuser name |
| `POSTGRES_DB` | Default database name |

**Important**: The official `postgres` Docker image reads `POSTGRES_PASSWORD` from
the environment. If the key is named `DB_PASSWORD`, the container will fail to
initialize the database cluster.

### 3. StatefulSet Resource Requests

Each container in the `postgres-cluster` StatefulSet must define resource **requests**:

| Resource | Request |
|----------|---------|
| cpu | `250m` |
| memory | `512Mi` |

Resource requests ensure the Kubernetes scheduler places pods on nodes with sufficient
capacity. Missing requests cause pods to be scheduled on overloaded nodes, leading to
OOMKilled events.

### 4. Headless Service for StatefulSet DNS

The Service `postgres-cluster` in namespace `data-platform` must be **headless**:

```yaml
spec:
  clusterIP: None
```

A headless Service is required by Kubernetes StatefulSets so that each pod gets a
stable DNS entry in the form:
```
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

For example:
- `postgres-cluster-0.postgres-cluster.data-platform.svc.cluster.local`
- `postgres-cluster-1.postgres-cluster.data-platform.svc.cluster.local`
- `postgres-cluster-2.postgres-cluster.data-platform.svc.cluster.local`

Without `clusterIP: None`, the StatefulSet members cannot reach each other by DNS,
breaking replication setup.

---

## Verification Commands

After fixing each issue, verify with:

```bash
# Check image tag
kubectl get statefulset postgres-cluster -n data-platform -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check Secret keys
kubectl get secret postgres-credentials -n data-platform -o jsonpath='{.data}' | base64 --decode

# Check resource requests
kubectl get statefulset postgres-cluster -n data-platform -o jsonpath='{.spec.template.spec.containers[0].resources}'

# Check Service headless
kubectl get service postgres-cluster -n data-platform -o jsonpath='{.spec.clusterIP}'
# Should return: None
```

---

## Architecture

```
External Clients
      │
      ▼
 pgbouncer (connection pooler, port 6432)
      │
      ▼
postgres-cluster-read (ClusterIP Service, port 5432) ──► read replicas
postgres-cluster (headless Service) ──► pod-to-pod DNS for replication
      │
      ├── postgres-cluster-0 (primary)
      ├── postgres-cluster-1 (replica)
      └── postgres-cluster-2 (replica)
```

## Login Credentials (Rancher)

- URL: https://localhost
- Username: admin
- Password: Admin12345678!
DOC

chown ga:ga /home/ga/Desktop/database_cluster_runbook.md

# ── Record baseline state ─────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/statefulset_database_cluster_restoration_start_ts

# ── Navigate Firefox to data-platform namespace ───────────────────────────────
echo "Navigating Firefox to data-platform namespace..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.statefulset?namespace=data-platform" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.statefulset?namespace=data-platform' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/statefulset_database_cluster_restoration_start.png

echo "=== statefulset_database_cluster_restoration setup complete ==="
echo ""
echo "The data-platform namespace has been created with a degraded postgres-cluster."
echo "Runbook: /home/ga/Desktop/database_cluster_runbook.md"
echo "4 failures have been injected. Agent must discover and fix all of them."
