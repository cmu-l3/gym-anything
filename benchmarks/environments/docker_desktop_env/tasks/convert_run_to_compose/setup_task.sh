#!/bin/bash
# Setup script for convert_run_to_compose task

echo "=== Setting up convert_run_to_compose task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create working directory
PROJECT_DIR="/home/ga/monitoring-stack"
mkdir -p "$PROJECT_DIR"

# Cleanup any previous state
echo "Cleaning up previous containers and networks..."
docker rm -f prometheus grafana node-exporter 2>/dev/null || true
docker network rm monitoring 2>/dev/null || true
docker volume rm prometheus-data grafana-data 2>/dev/null || true
# Also clean up compose project if it exists
cd "$PROJECT_DIR" && docker compose down -v 2>/dev/null || true

# Pre-pull images to ensure task focuses on composition, not download speed
echo "Pre-pulling images..."
docker pull prom/prometheus:v2.53.0 &
docker pull grafana/grafana:11.0.0 &
docker pull prom/node-exporter:v1.8.1 &
wait

# Create the reference run_commands.sh
cat > "$PROJECT_DIR/run_commands.sh" << 'EOF'
#!/bin/bash
# Legacy monitoring stack setup - DO NOT RUN
# Convert these to docker-compose.yml instead

# Network
docker network create monitoring

# Prometheus
docker run -d \
  --name prometheus \
  --network monitoring \
  -p 9090:9090 \
  -v prometheus-data:/prometheus \
  -v /home/ga/monitoring-stack/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  --restart unless-stopped \
  prom/prometheus:v2.53.0

# Grafana
docker run -d \
  --name grafana \
  --network monitoring \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=monitoring123 \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -v grafana-data:/var/lib/grafana \
  --restart unless-stopped \
  grafana/grafana:11.0.0

# Node Exporter
docker run -d \
  --name node-exporter \
  --network monitoring \
  -p 9100:9100 \
  --pid host \
  --restart unless-stopped \
  prom/node-exporter:v1.8.1
EOF

# Make it read-only and non-executable to discourage running it directly
chmod 444 "$PROJECT_DIR/run_commands.sh"

# Create the prometheus.yml config file
cat > "$PROJECT_DIR/prometheus.yml" << 'EOF'
# Prometheus configuration
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

# Ensure ownership
chown -R ga:ga "$PROJECT_DIR"

# Wait for Docker Desktop to be ready
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    wait_for_docker_daemon 60
fi

# Focus Docker Desktop
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="