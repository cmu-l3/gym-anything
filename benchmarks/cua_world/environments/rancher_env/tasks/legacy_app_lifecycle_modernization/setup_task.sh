#!/bin/bash
echo "=== Setting up legacy_app_lifecycle_modernization task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace finance --wait=false 2>/dev/null || true
sleep 5

# Create finance namespace
echo "Creating finance namespace..."
docker exec rancher kubectl create namespace finance 2>/dev/null || true

# Deploy broken application
# The container sleeps for 45s (simulating slow startup)
# But livenessProbe starts checking at 15s, every 5s, failing at 3 thresholds -> kills pod at ~30s.
echo "Deploying broken payment-processor deployment..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
  namespace: finance
  labels:
    app: payment-processor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
    spec:
      containers:
      - name: app
        image: nginx:alpine
        command: ["/bin/sh", "-c"]
        args: ["echo 'Starting JVM...'; sleep 45; echo 'App Started'; exec nginx -g 'daemon off;'"]
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 5
          failureThreshold: 3
MANIFEST

# Create the specification file on the desktop
echo "Writing lifecycle specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/lifecycle_spec.yaml << 'SPEC'
# Lifecycle Modernization Specification
# Target: deployment/payment-processor in namespace: finance

probes:
  startupProbe:
    httpGet:
      path: /
      port: 80
    failureThreshold: 20
    periodSeconds: 5
    
  livenessProbe:
    # Now protected by startupProbe. Remove initialDelaySeconds (or set to 0).
    httpGet:
      path: /
      port: 80
    failureThreshold: 3
    periodSeconds: 10
    
  readinessProbe:
    # Ensure no traffic is routed during the 45s initialization
    httpGet:
      path: /
      port: 80
    failureThreshold: 2
    periodSeconds: 5

lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 15"]
SPEC

chmod 644 /home/ga/Desktop/lifecycle_spec.yaml

# Ensure Firefox is focused and maximized
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing setup is complete
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="