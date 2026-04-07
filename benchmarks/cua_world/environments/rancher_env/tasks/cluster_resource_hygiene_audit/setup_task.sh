#!/bin/bash
# Setup script for cluster_resource_hygiene_audit task
# Populates the platform-services namespace with a mix of active workloads
# and orphaned resources (Jobs, ConfigMaps, Secrets).

echo "=== Setting up cluster_resource_hygiene_audit task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace platform-services --wait=false 2>/dev/null || true
sleep 10

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating platform-services namespace..."
docker exec rancher kubectl create namespace platform-services 2>/dev/null || true

# ── Deploy Active and Orphaned Resources ──────────────────────────────────────
echo "Deploying mixed active and orphaned resources..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
# ==========================================
# ACTIVE CONFIGMAPS & SECRETS (Do not delete)
# ==========================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-server-config
  namespace: platform-services
data:
  PORT: "8080"
  LOG_LEVEL: "INFO"
  ENABLE_METRICS: "true"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: worker-config
  namespace: platform-services
data:
  BATCH_SIZE: "100"
  WORKER_THREADS: "4"
  QUEUE_NAME: "tasks-primary"
---
apiVersion: v1
kind: Secret
metadata:
  name: api-credentials
  namespace: platform-services
type: Opaque
stringData:
  API_KEY: "prod-api-key-889922"
  DB_PASS: "SuperSecretDBPass123"
---
apiVersion: v1
kind: Secret
metadata:
  name: worker-credentials
  namespace: platform-services
type: Opaque
stringData:
  QUEUE_TOKEN: "qt-9988-abcd-1234"
  S3_SECRET: "s3-sec-zzz-xxx-yyy"

# ==========================================
# ACTIVE DEPLOYMENTS (Reference the above)
# ==========================================
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: platform-services
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
        image: nginx:alpine
        envFrom:
        - configMapRef:
            name: api-server-config
        - secretRef:
            name: api-credentials
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-process
  namespace: platform-services
  labels:
    app: worker-process
spec:
  replicas: 1
  selector:
    matchLabels:
      app: worker-process
  template:
    metadata:
      labels:
        app: worker-process
    spec:
      containers:
      - name: worker-process
        image: nginx:alpine
        envFrom:
        - configMapRef:
            name: worker-config
        - secretRef:
            name: worker-credentials

# ==========================================
# ORPHANED CONFIGMAPS & SECRETS (Must delete)
# ==========================================
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: legacy-app-config
  namespace: platform-services
data:
  LEGACY_MODE: "true"
  SUPPORTED_VERSIONS: "v1,v1.1"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags-v1
  namespace: platform-services
data:
  NEW_UI: "false"
  BETA_CHECKOUT: "false"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: temp-debug-config
  namespace: platform-services
data:
  DEBUG_MODE: "true"
  TRACE_ALL: "1"
---
apiVersion: v1
kind: Secret
metadata:
  name: old-db-credentials
  namespace: platform-services
type: Opaque
stringData:
  DB_URL: "postgres://old-db.internal:5432/app"
---
apiVersion: v1
kind: Secret
metadata:
  name: staging-api-key
  namespace: platform-services
type: Opaque
stringData:
  API_KEY: "staging-only-do-not-use-in-prod"
---
apiVersion: v1
kind: Secret
metadata:
  name: decomm-service-token
  namespace: platform-services
type: Opaque
stringData:
  TOKEN: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.dummy"

# ==========================================
# ORPHANED JOBS (Must delete)
# ==========================================
---
apiVersion: batch/v1
kind: Job
metadata:
  name: data-migration-v2
  namespace: platform-services
spec:
  template:
    spec:
      containers:
      - name: migration
        image: alpine
        command: ["sh", "-c", "echo 'Migration complete'; exit 0"]
      restartPolicy: Never
---
apiVersion: batch/v1
kind: Job
metadata:
  name: schema-update-q3
  namespace: platform-services
spec:
  template:
    spec:
      containers:
      - name: update
        image: alpine
        command: ["sh", "-c", "echo 'Schema updated'; exit 0"]
      restartPolicy: Never
---
apiVersion: batch/v1
kind: Job
metadata:
  name: cleanup-batch-0412
  namespace: platform-services
spec:
  backoffLimit: 0
  template:
    spec:
      containers:
      - name: batch
        image: alpine
        command: ["sh", "-c", "echo 'Fatal error during batch'; exit 1"]
      restartPolicy: Never
MANIFEST

# Wait for jobs to settle into Completed/Failed states
echo "Waiting for Jobs to settle (approx 15-20 seconds)..."
sleep 20

# ── Write the cleanup checklist to the Desktop ────────────────────────────────
echo "Creating cleanup checklist on desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/cleanup_checklist.md << 'CHECKLIST'
# Quarterly Cluster Hygiene — platform-services Namespace

## Cleanup Criteria

### Jobs
- Delete all Jobs in **Completed** or **Failed** state
- These are one-off migration/batch tasks that have finished executing
- Active CronJobs (if any) should NOT be deleted

### ConfigMaps
- Delete ConfigMaps that are NOT referenced by any running Deployment, 
  StatefulSet, DaemonSet, or Pod as either:
  - An environment variable source (envFrom or env.valueFrom.configMapKeyRef)
  - A volume mount (volumes[].configMap)
- Do NOT delete system ConfigMaps (e.g., kube-root-ca.crt)

### Secrets
- Delete Secrets that are NOT referenced by any running Deployment,
  StatefulSet, DaemonSet, or Pod as either:
  - An environment variable source (envFrom or env.valueFrom.secretKeyRef)
  - A volume mount (volumes[].secret)
- Do NOT delete ServiceAccount token Secrets or system Secrets
- Do NOT delete Secrets of type kubernetes.io/service-account-token

### Preservation Rules
- NEVER delete active Deployments or their dependent resources
- NEVER delete system/default namespace resources
- When in doubt, check if any running pod references the resource
CHECKLIST

# Record baseline task start timestamp
date +%s > /tmp/task_start_time.txt
echo "=== Task setup complete ==="