#!/bin/bash
echo "=== Setting up legacy_workload_network_ipc_customization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace legacy-migration --wait=false 2>/dev/null || true
sleep 5

# Create namespace
echo "Creating legacy-migration namespace..."
docker exec rancher kubectl create namespace legacy-migration 2>/dev/null || true

# Deploy the initial (unconfigured) deployment
echo "Deploying unconfigured trading-monolith..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trading-monolith
  namespace: legacy-migration
  labels:
    app: trading-monolith
spec:
  replicas: 1
  selector:
    matchLabels:
      app: trading-monolith
  template:
    metadata:
      labels:
        app: trading-monolith
    spec:
      containers:
      - name: engine
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: fast-cache
          mountPath: /var/cache/trading
      volumes:
      - name: fast-cache
        emptyDir: {}
MANIFEST

# Create the specification file on the desktop
echo "Writing migration specification to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/migration_spec.md << 'SPEC'
# Trading Engine Migration - Infrastructure Spec
Classification: INTERNAL / HYBRID-CLOUD

## 1. Static Host Mappings
The monolith hardcodes connections to legacy physical servers that are not in DNS.
You must configure Pod-level Host Aliases (`hostAliases`) for:
- IP: `198.51.100.15` -> Hostname: `clearinghouse.local`
- IP: `198.51.100.16` -> Hostname: `audit.local`

## 2. DNS Resolution Override
The monolith queries external financial partner APIs that must be resolved using specific nameservers, bypassing standard Kubernetes CoreDNS.
- DNS Policy (`dnsPolicy`): Must be entirely overridden to `None` (do NOT use ClusterFirst)
- Nameservers: `1.1.1.1` and `1.0.0.1`
- Search Domains: `trading.internal` and `finance.internal`
- Options: `ndots` must be set to `2`

## 3. High-Speed IPC Cache
The sidecar and main container share a volume named `fast-cache`.
Currently, this is a standard disk-backed emptyDir, which is too slow.
- You must change this volume to use a RAM Disk (`medium: Memory`).
- To prevent OOM evictions, you MUST set a size limit of `512Mi` on this volume.
SPEC

chmod 644 /home/ga/Desktop/migration_spec.md

# Ensure Rancher UI is accessible and focused
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="