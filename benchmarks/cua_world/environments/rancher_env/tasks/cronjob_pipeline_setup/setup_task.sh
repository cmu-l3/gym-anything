#!/bin/bash
# Setup script for cronjob_pipeline_setup task
# Sets up the operations namespace, prerequisite ConfigMap and Secret,
# and writes the specification document to the desktop.

echo "=== Setting up cronjob_pipeline_setup task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous operations namespace..."
docker exec rancher kubectl delete namespace operations --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating operations namespace..."
docker exec rancher kubectl create namespace operations 2>/dev/null || true

# ── Create prerequisite resources ─────────────────────────────────────────────
echo "Creating db-credentials Secret..."
docker exec rancher kubectl create secret generic db-credentials \
    -n operations \
    --from-literal=DB_HOST=postgres.operations.svc \
    --from-literal=DB_USER=backup_agent \
    --from-literal=DB_PASSWORD=s3cureP@ss! \
    2>/dev/null || true

echo "Creating metrics-config ConfigMap..."
docker exec rancher kubectl create configmap metrics-config \
    -n operations \
    --from-literal=METRICS_ENDPOINT=http://prometheus.monitoring:9090 \
    2>/dev/null || true

# ── Write specification file to desktop ───────────────────────────────────────
echo "Writing specification document to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/cronjob_pipeline_spec.md << 'SPEC'
# Operations CronJob Pipeline Specification

## Namespace: operations

All CronJobs must be created in the `operations` namespace. Prerequisites (Secret and ConfigMap) already exist.

---

### 1. db-backup

Database backup job that runs every 6 hours.

- **Schedule**: `0 */6 * * *`
- **Image**: `bitnami/postgresql:15`
- **Command**: `["/bin/sh", "-c", "echo 'Running pg_dump backup' && sleep 5"]`
- **Resource Limits**: cpu=500m, memory=512Mi
- **Resource Requests**: cpu=250m, memory=256Mi
- **Environment**: All keys from Secret `db-credentials` (use envFrom)
- **Concurrency Policy**: Forbid
- **Backoff Limit**: 3
- **Restart Policy**: OnFailure

---

### 2. log-cleanup

Log rotation job that runs daily at 2:30 AM UTC.

- **Schedule**: `30 2 * * *`
- **Image**: `busybox:1.36`
- **Command**: `["/bin/sh", "-c", "echo 'Cleaning logs older than 7 days' && find /var/log/app -name '*.log' -mtime +7 -delete 2>/dev/null; echo 'Done'"]`
- **Resource Limits**: cpu=200m, memory=128Mi
- **Resource Requests**: cpu=100m, memory=64Mi
- **Volume**: emptyDir named `log-volume` mounted at `/var/log/app`
- **Active Deadline Seconds**: 300
- **Successful Jobs History Limit**: 3
- **Failed Jobs History Limit**: 1
- **Restart Policy**: Never

---

### 3. metrics-aggregator

Metrics collection job that runs every 15 minutes.

- **Schedule**: `*/15 * * * *`
- **Image**: `curlimages/curl:8.5.0`
- **Command**: `["/bin/sh", "-c", "echo Collecting metrics from $METRICS_ENDPOINT"]`
- **Resource Limits**: cpu=100m, memory=64Mi
- **Resource Requests**: cpu=50m, memory=32Mi
- **Environment**: key `METRICS_ENDPOINT` from ConfigMap `metrics-config`
- **Concurrency Policy**: Replace
- **Starting Deadline Seconds**: 60
- **Restart Policy**: OnFailure

---

### 4. compliance-report

Weekly compliance report generation, runs Monday at 8:00 AM UTC.

- **Schedule**: `0 8 * * 1`
- **Image**: `python:3.11-slim`
- **Command**: `["/bin/sh", "-c", "python3 -c \"print('PCI-DSS Compliance Report Generated')\""]`
- **Resource Limits**: cpu=1, memory=1Gi
- **Resource Requests**: cpu=500m, memory=512Mi
- **Completions**: 1
- **Parallelism**: 1
- **Backoff Limit**: 2
- **Restart Policy**: Never
- **Pod Label**: `compliance-tier: pci-dss`
SPEC
chmod 644 /home/ga/Desktop/cronjob_pipeline_spec.md

# ── Start Firefox if not running ──────────────────────────────────────────────
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard/c/local/explorer &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ── Record start timestamp & initial screenshot ───────────────────────────────
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="