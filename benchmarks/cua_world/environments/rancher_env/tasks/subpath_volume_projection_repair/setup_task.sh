#!/bin/bash
# Setup script for subpath_volume_projection_repair task
# Injects a broken Nginx deployment suffering from the "directory masking" volume mount issue.

echo "=== Setting up subpath_volume_projection_repair task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace edge-routing --wait=false 2>/dev/null || true
sleep 8

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating edge-routing namespace..."
docker exec rancher kubectl create namespace edge-routing 2>/dev/null || true

# ── Generate TLS Certificates and Create Secret ───────────────────────────────
echo "Generating TLS certificates for gateway..."
docker exec rancher sh -c "mkdir -p /tmp/certs && openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/certs/tls.key -out /tmp/certs/tls.crt -subj '/CN=nginx-gateway.edge-routing.svc.cluster.local' 2>/dev/null"

echo "Creating gateway-certs Secret..."
docker exec rancher kubectl create secret tls gateway-certs \
    --cert=/tmp/certs/tls.crt \
    --key=/tmp/certs/tls.key \
    -n edge-routing 2>/dev/null || true

# ── Create ConfigMap (NOT immutable yet) ──────────────────────────────────────
echo "Creating gateway-config ConfigMap..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config
  namespace: edge-routing
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
            listen 443 ssl;
            server_name localhost;
            
            # Requires these certificates to be mounted!
            ssl_certificate /etc/nginx/ssl/tls.crt;
            ssl_certificate_key /etc/nginx/ssl/tls.key;
            
            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
            }
        }
    }
MANIFEST

# ── Deploy the broken Deployment ──────────────────────────────────────────────
# Injected failures:
# 1. Mounts ConfigMap to /etc/nginx (hides everything including mime.types)
# 2. Missing volume and volumeMount for gateway-certs secret
echo "Deploying broken nginx-gateway..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-gateway
  namespace: edge-routing
  labels:
    app: nginx-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-gateway
  template:
    metadata:
      labels:
        app: nginx-gateway
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 443
        volumeMounts:
        # BUG: This mounts the whole ConfigMap over /etc/nginx, hiding mime.types and breaking Nginx
        - name: config-volume
          mountPath: /etc/nginx
        # BUG: Missing mount for /etc/nginx/ssl
      volumes:
      - name: config-volume
        configMap:
          name: gateway-config
MANIFEST

# ── Drop the specification file on the desktop ────────────────────────────────
echo "Writing specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/gateway_spec.md << 'SPEC'
# Nginx Gateway Repair Specification
# Ticket: PLAT-8821
# Namespace: edge-routing

The `nginx-gateway` deployment is crashing because a junior developer mounted a ConfigMap incorrectly and forgot the TLS certificates. 

Please apply the following fixes to the `nginx-gateway` deployment:

1. **Fix the Configuration Mount (Directory Masking)**
   - The ConfigMap `gateway-config` contains `nginx.conf`.
   - Do NOT mount it to `/etc/nginx` as a full directory (this hides `mime.types`).
   - Use the `subPath` directive to mount ONLY the `nginx.conf` file to `/etc/nginx/nginx.conf`.

2. **Mount TLS Certificates**
   - A Secret named `gateway-certs` already exists in the namespace.
   - Add it as a volume to the deployment.
   - Mount it into the container at `/etc/nginx/ssl/`.
   - **SECURITY REQUIREMENT:** Set the `defaultMode` of the Secret volume to `0400` (read-only by owner).

3. **Enforce Immutability**
   - Edit the `gateway-config` ConfigMap and set `immutable: true` to prevent accidental changes.

The deployment should automatically roll out and reach a `Running` state once these issues are resolved.
SPEC

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="