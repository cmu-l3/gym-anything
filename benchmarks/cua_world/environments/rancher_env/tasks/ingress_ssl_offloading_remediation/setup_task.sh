#!/bin/bash
# Setup script for ingress_ssl_offloading_remediation task

echo "=== Setting up ingress_ssl_offloading_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace secure-web --wait=false 2>/dev/null || true
sleep 5

docker exec rancher kubectl create namespace secure-web 2>/dev/null || true

# ── Generate Self-Signed Cert for secure.local ──────────────────────────────
echo "Generating TLS certificate..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=secure.local/O=MyCompany" 2>/dev/null

# Copy to container
docker cp /tmp/tls.key rancher:/tmp/tls.key
docker cp /tmp/tls.crt rancher:/tmp/tls.crt

# ── Create the broken Secret (Opaque instead of kubernetes.io/tls) ──────────
# Also uses wrong key names ('certificate.crt' instead of 'tls.crt')
echo "Creating Opaque secret with incorrect key names..."
docker exec rancher kubectl create secret generic portal-tls \
  -n secure-web \
  --from-file=certificate.crt=/tmp/tls.crt \
  --from-file=private.key=/tmp/tls.key

# ── Deploy the application and broken Ingress ────────────────────────────────
echo "Deploying application and broken Ingress..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: portal-app
  namespace: secure-web
  labels:
    app: portal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: portal
  template:
    metadata:
      labels:
        app: portal
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: portal-svc
  namespace: secure-web
spec:
  selector:
    app: portal
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portal-ingress
  namespace: secure-web
spec:
  tls:
  - hosts:
    - secure.local
    secretName: portal-tls
  rules:
  - host: secure.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: portal-svc
            port:
              number: 443 # FAILURE: SSL offloading should point to port 80 (where backend is listening)
MANIFEST

# ── Setup local DNS resolution inside container for curl verification ────────
docker exec rancher sh -c "grep -q 'secure.local' /etc/hosts || echo '127.0.0.1 secure.local' >> /etc/hosts"

# ── Final setup steps ────────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="