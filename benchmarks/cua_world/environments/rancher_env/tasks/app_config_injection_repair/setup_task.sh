#!/bin/bash
# Setup script for app_config_injection_repair task
# Injects a destructive ConfigMap mount and misses Secret/DownwardAPI injection

echo "=== Setting up app_config_injection_repair task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
docker exec rancher kubectl delete namespace dashboard-prod --wait=false 2>/dev/null || true
sleep 10

# Create namespace
docker exec rancher kubectl create namespace dashboard-prod 2>/dev/null || true

# Create Secret with DB credentials
docker exec rancher kubectl create secret generic db-credentials \
    -n dashboard-prod \
    --from-literal=DB_USER=analytics_admin \
    --from-literal=DB_PASS=S3cr3tP@ssw0rd! \
    2>/dev/null || true

# Create ConfigMap with custom nginx config
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-nginx-config
  namespace: dashboard-prod
data:
  nginx.conf: |
    user  nginx;
    worker_processes  auto;
    error_log  /var/log/nginx/error.log notice;
    pid        /var/run/nginx.pid;
    events {
        worker_connections  1024;
    }
    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;
        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';
        access_log  /var/log/nginx/access.log  main;
        sendfile        on;
        keepalive_timeout  65;
        server {
            listen       80;
            server_name  localhost;
            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
            }
        }
    }
EOF

# Create deployment with destructive volume mount and missing credentials/metadata
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics-dashboard
  namespace: dashboard-prod
  labels:
    app: analytics-dashboard
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: analytics-dashboard
  template:
    metadata:
      labels:
        app: analytics-dashboard
        tier: frontend
      annotations:
        observability.company.com/scrape: "true"
        team: "data-science"
    spec:
      containers:
      - name: dashboard
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        # Destructive mount! Mounts the whole directory, hiding mime.types
        - name: nginx-config-vol
          mountPath: /etc/nginx/
      volumes:
      - name: nginx-config-vol
        configMap:
          name: dashboard-nginx-config
EOF

# Record baseline state
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="