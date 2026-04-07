#!/bin/bash
echo "=== Setting up private_registry_auth_migration task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up any existing state
docker exec rancher kubectl delete namespace production-apps --wait=false 2>/dev/null || true
sleep 5

# Create namespace
docker exec rancher kubectl create namespace production-apps 2>/dev/null || true

# Deploy starting state applications
echo "Deploying un-migrated applications..."
docker exec -i rancher kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: production-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:1.24
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: production-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: node:18
        command: ["sleep", "3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
  namespace: production-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      containers:
      - name: cache
        image: redis:7.0
        ports:
        - containerPort: 6379
EOF

# Create the instructions and credentials document on the desktop
echo "Writing instructions and credentials..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/registry_credentials.txt <<'EOF'
Private Container Registry Access Details
-----------------------------------------
The company is migrating to a secure, air-gapped container registry.
All deployments in the 'production-apps' namespace must pull their images from this registry.

Registry Server: harbor.corp.local
Username: svc_k8s_pull
Password: SecureToken-9988776655

Instructions for Platform Engineers:
1. Create a Docker registry secret named 'corp-registry-auth' in the 'production-apps' namespace using these credentials.
2. Link the secret to the 'default' ServiceAccount in the namespace so all new pods automatically authenticate.
3. Update the existing deployments (frontend, backend, cache) to use images from the new registry.
   Example: change 'nginx:1.24' to 'harbor.corp.local/library/nginx:1.24'.
EOF
chown ga:ga /home/ga/Desktop/registry_credentials.txt

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png || true

echo "=== Setup complete ==="