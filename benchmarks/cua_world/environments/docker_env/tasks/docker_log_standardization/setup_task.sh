#!/bin/bash
# Setup script for docker_log_standardization task

set -e
echo "=== Setting up Docker Log Standardization Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi

wait_for_docker

# Cleanup any previous state
echo "Cleaning up containers..."
docker rm -f acme-web acme-api acme-worker acme-scheduler acme-notifier 2>/dev/null || true
docker rm -f acme-web-fixed acme-api-fixed acme-worker-fixed acme-scheduler-fixed acme-notifier-fixed 2>/dev/null || true

# Prepare project directory
mkdir -p /home/ga/projects/log-audit
cat > /home/ga/projects/log-audit/README.md <<EOF
# Logging Standardization Project

Goal: Standardize logging across all services.
New Standard:
- Driver: json-file
- Max Size: 10m
- Max Files: 3

Current Status:
- Services are running with inconsistent configurations.
- Some logs are being lost.
- We need to find the error code (ERR-XXXX) from the recent outage.
EOF
chown -R ga:ga /home/ga/projects/log-audit

# Ensure Desktop exists for report
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Start containers with BAD configurations

echo "Starting acme-web (Source of Truth for error)..."
# json-file, default rotation (unlimited). Contains the error.
docker run -d --name acme-web \
  --log-driver json-file \
  alpine:3.18 sh -c '
i=0; while true; do
  i=$((i+1))
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ $i -eq 5 ]; then
    echo "$ts [ERROR] ERR-4721: payment gateway timeout after 30s - circuit breaker tripped"
  elif [ $((i % 7)) -eq 0 ]; then
    echo "$ts [WARN] slow response from upstream api: 2.3s"
  else
    echo "$ts [INFO] GET /index.html 200 0.${i}ms"
  fi
  sleep 2
done'

echo "Starting acme-api (Data Loss)..."
# json-file, 100 bytes max-size. Rotates instantly, losing history.
docker run -d --name acme-api \
  --log-driver json-file --log-opt max-size=100b --log-opt max-file=1 \
  alpine:3.18 sh -c '
i=0; while true; do
  i=$((i+1))
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$ts [INFO] API request processed: endpoint=/api/v2/orders status=200 latency=${i}ms"
  sleep 1
done'

echo "Starting acme-worker (Black Hole)..."
# none driver. Logs completely lost.
docker run -d --name acme-worker \
  --log-driver none \
  alpine:3.18 sh -c '
i=0; while true; do
  i=$((i+1))
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ $i -eq 5 ]; then
    echo "$ts [ERROR] ERR-4721: payment gateway timeout - job payment_batch_${i} failed"
  else
    echo "$ts [INFO] processing job batch_${i}: 42 items completed"
  fi
  sleep 4
done'

echo "Starting acme-scheduler (Over-provisioned)..."
# json-file, 50mb max-size. Way too big.
docker run -d --name acme-scheduler \
  --log-driver json-file --log-opt max-size=50m --log-opt max-file=10 \
  alpine:3.18 sh -c '
while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$ts [INFO] scheduler tick: next run in 60s, queue_depth=3"
  sleep 5
done'

echo "Starting acme-notifier (Default)..."
# json-file, no limits.
docker run -d --name acme-notifier \
  --log-driver json-file \
  alpine:3.18 sh -c '
i=0; while true; do
  i=$((i+1))
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$ts [INFO] notification sent: channel=email recipient=ops-team@acme.com event=deploy_${i}"
  sleep 6
done'

# Record start time
date +%s > /tmp/task_start_timestamp

# Wait a bit for logs to generate
sleep 5

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/log-audit && echo \"Log Standardization Task\"; echo; echo \"Check README.md for instructions.\"; echo; exec bash'" > /tmp/terminal.log 2>&1 &

echo "=== Setup Complete ==="