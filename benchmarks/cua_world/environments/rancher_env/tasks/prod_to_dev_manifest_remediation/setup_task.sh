#!/bin/bash
# Setup script for prod_to_dev_manifest_remediation task
# Deploys a set of Kubernetes manifests with "production" constraints 
# that cause them to fail on a local single-node cluster.

echo "=== Setting up prod_to_dev_manifest_remediation task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up previous state
echo "Cleaning up previous dev-environment namespace..."
docker exec rancher kubectl delete namespace dev-environment --timeout=60s 2>/dev/null || true
sleep 5

# Create the target namespace
echo "Creating dev-environment namespace..."
docker exec rancher kubectl create namespace dev-environment 2>/dev/null || true

# Deploy the broken manifests
echo "Deploying production manifests to dev-environment..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: dev-environment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      # FAILURE 1: PodAntiAffinity prevents 3 replicas from running on a 1-node dev cluster
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - web-app
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-app
  namespace: dev-environment
spec:
  selector:
    app: web-app
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db-backend
  namespace: dev-environment
spec:
  serviceName: db-backend
  replicas: 1
  selector:
    matchLabels:
      app: db-backend
  template:
    metadata:
      labels:
        app: db-backend
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      # FAILURE 2: StorageClass doesn't exist locally (should be 'local-path')
      storageClassName: premium-rwo
      resources:
        requests:
          storage: 2Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: data-processor
  namespace: dev-environment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-processor
  template:
    metadata:
      labels:
        app: data-processor
    spec:
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sleep", "3600"]
        # FAILURE 3: CPU request exceeds node capacity, causing Pending state
        resources:
          requests:
            cpu: "16"
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: dev-environment
spec:
  # FAILURE 4: Wrong Ingress class (should be 'traefik' or omitted)
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app
            port:
              number: 80
MANIFEST

# Drop a copy of the manifests on the desktop for the agent
mkdir -p /home/ga/Desktop
docker exec rancher kubectl get deploy,sts,ingress -n dev-environment -o yaml > /home/ga/Desktop/prod_manifests.yaml
chown ga:ga /home/ga/Desktop/prod_manifests.yaml

# Record baseline state
date +%s > /tmp/prod_to_dev_task_start_ts

# Take initial setup screenshot
take_screenshot /tmp/prod_to_dev_initial.png

echo "=== Task setup complete ==="