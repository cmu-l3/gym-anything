#!/bin/bash
echo "=== Setting up batch_cronjob_governance task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-platform --wait=false 2>/dev/null || true
sleep 5

echo "Creating data-platform namespace..."
docker exec rancher kubectl create namespace data-platform 2>/dev/null || true

echo "Deploying misconfigured CronJobs..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hourly-backup
  namespace: data-platform
spec:
  schedule: "0 * * * *"
  concurrencyPolicy: Allow
  successfulJobsHistoryLimit: 100
  failedJobsHistoryLimit: 100
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: busybox:1.36
            command: ["/bin/sh", "-c", "echo 'Backing up database...'; sleep 300"]
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: legacy-export
  namespace: data-platform
spec:
  schedule: "*/5 * * * *"
  suspend: false
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: export
            image: busybox:1.36
            command: ["/bin/sh", "-c", "echo 'Exporting...'; exit 1"]
          restartPolicy: Never
EOF

sleep 2

# Take initial screenshot to capture Rancher dashboard startup state
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="