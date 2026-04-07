#!/bin/bash
echo "=== Setting up Docker Container Forensics Task ==="
source /workspace/scripts/task_utils.sh

wait_for_docker

# ── Prepare working directory ──────────────────────────────────────────────────
WORK_DIR="/home/ga/acme-corp-incident"
sudo -u ga mkdir -p "$WORK_DIR"
cp -r /workspace/data/task4_forensics/. "$WORK_DIR/"
chown -R ga:ga "$WORK_DIR"

# Create required subdirectory content for bind mounts in docker-compose.yml
mkdir -p "$WORK_DIR/webapp/html"
cat > "$WORK_DIR/webapp/html/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>AcmeCorp Portal</title></head>
<body>
<h1>Welcome to AcmeCorp Internal Portal</h1>
<p>For internal use only. Unauthorized access is prohibited.</p>
</body>
</html>
EOF

mkdir -p "$WORK_DIR/monitor"
cat > "$WORK_DIR/monitor/config.yml" <<'EOF'
# AcmeCorp Monitor Configuration
scrape_interval: 30s
metrics_path: /metrics
targets:
  - acme-webapp:80
  - acme-gateway:5000
log_level: info
EOF
chown -R ga:ga "$WORK_DIR"

# ── Tear down any pre-existing containers with these names ─────────────────────
for name in acme-webapp acme-gateway acme-monitor acme-webapp-fixed acme-gateway-fixed acme-monitor-fixed; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        docker rm -f "$name" 2>/dev/null || true
    fi
done

# ── Start the three misconfigured production containers ────────────────────────
cd "$WORK_DIR"
sudo -u ga docker compose up -d 2>&1 | tail -20

# ── Wait for all three containers to be running ───────────────────────────────
echo "Waiting for containers to start..."
for i in $(seq 1 30); do
    RUNNING=$(docker ps --format '{{.Names}}' | grep -cE '^acme-(webapp|gateway|monitor)$' 2>/dev/null)
    [ -z "$RUNNING" ] && RUNNING=0
    if [ "$RUNNING" -ge 3 ]; then
        echo "All 3 containers are running."
        break
    fi
    sleep 2
done

# ── Record baseline state ──────────────────────────────────────────────────────
docker ps --format '{{.Names}}\t{{.Status}}' | grep acme > /tmp/initial_container_state.txt
echo "Initial container state recorded:"
cat /tmp/initial_container_state.txt

# ── Record task start timestamp ───────────────────────────────────────────────
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── Create Desktop directory ───────────────────────────────────────────────────
sudo -u ga mkdir -p /home/ga/Desktop

# ── Take initial screenshot ────────────────────────────────────────────────────
take_screenshot "forensics_task_start"

echo "=== Setup Complete ==="
echo ""
echo "Three vulnerable containers are running:"
docker ps --filter "name=acme-" --format "  {{.Names}} ({{.Image}}) - {{.Status}}"
echo ""
echo "Use 'docker inspect', 'docker exec', and 'docker logs' to investigate."
echo "Create fixed containers named: acme-webapp-fixed, acme-gateway-fixed, acme-monitor-fixed"
echo "Write your incident report to: ~/Desktop/incident_report.txt"
