#!/bin/bash
# Setup script for network_policy_zero_trust task
# Creates online-banking namespace with microservices running with NO network policies.
# A security audit flagged this; agent must implement zero-trust network policies.

echo "=== Setting up network_policy_zero_trust task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace online-banking --wait=false 2>/dev/null || true
sleep 8

# ── Create online-banking namespace ──────────────────────────────────────────
echo "Creating online-banking namespace..."
docker exec rancher kubectl create namespace online-banking 2>/dev/null || true

# ── Deploy microservices (no network policies - security gap) ─────────────────
echo "Deploying online banking microservices without network policies..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
# Ingress controller namespace label (needed for NetworkPolicy selectors)
# In this cluster, ingress-nginx runs in its own namespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-app
  namespace: online-banking
  labels:
    app: frontend-app
    tier: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend-app
  template:
    metadata:
      labels:
        app: frontend-app
        tier: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-app
  namespace: online-banking
spec:
  selector:
    app: frontend-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: online-banking
  labels:
    app: api-gateway
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        tier: backend
    spec:
      containers:
      - name: api-gateway
        image: nginx:alpine
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: online-banking
spec:
  selector:
    app: api-gateway
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: online-banking
  labels:
    app: auth-service
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
        tier: backend
    spec:
      containers:
      - name: auth-service
        image: nginx:alpine
        ports:
        - containerPort: 8081
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: online-banking
spec:
  selector:
    app: auth-service
  ports:
  - port: 8081
    targetPort: 8081
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: account-service
  namespace: online-banking
  labels:
    app: account-service
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: account-service
  template:
    metadata:
      labels:
        app: account-service
        tier: backend
    spec:
      containers:
      - name: account-service
        image: nginx:alpine
        ports:
        - containerPort: 8082
---
apiVersion: v1
kind: Service
metadata:
  name: account-service
  namespace: online-banking
spec:
  selector:
    app: account-service
  ports:
  - port: 8082
    targetPort: 8082
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: account-db
  namespace: online-banking
  labels:
    app: account-db
    tier: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: account-db
  template:
    metadata:
      labels:
        app: account-db
        tier: database
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          value: "changeme"
        - name: POSTGRES_DB
          value: "accounts"
MANIFEST

# ── Create ingress-nginx namespace (simulated) with label ─────────────────────
docker exec rancher kubectl create namespace ingress-nginx 2>/dev/null || true
docker exec rancher kubectl label namespace ingress-nginx \
    kubernetes.io/metadata.name=ingress-nginx --overwrite 2>/dev/null || true

# ── Drop the network topology specification on the desktop ────────────────────
echo "Writing network topology spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/network_topology_spec.md << 'SPEC'
# Online Banking Zero-Trust Network Policy Specification
# Security Audit Reference: SEC-2024-0847
# Classification: INTERNAL

## Objective
Implement zero-trust network segmentation for the online-banking namespace.
All traffic must be explicitly allowed; implicit allow-all is prohibited.

## Architecture

```
[Internet] → ingress-nginx → frontend-app → api-gateway → auth-service
                                                         → account-service → account-db
```

## Namespace Labels
- online-banking namespace pods use their `app` labels for selection
- Ingress controller runs in `ingress-nginx` namespace (label: kubernetes.io/metadata.name=ingress-nginx)

## Required Network Policies

### Policy 1: Default Deny All (MANDATORY - all other policies depend on this)
- Name: default-deny-all
- Namespace: online-banking
- PodSelector: {} (selects ALL pods in namespace)
- PolicyTypes: Ingress, Egress
- Ingress: (none — deny all ingress by default)
- Egress: (none — deny all egress by default)

### Policy 2: Allow Frontend Ingress from Ingress Controller
- Name: allow-frontend-ingress
- Namespace: online-banking
- PodSelector: app=frontend-app
- PolicyTypes: Ingress, Egress
- Ingress: Allow from namespace with label kubernetes.io/metadata.name=ingress-nginx (port 80)
- Egress: Allow to pods with label app=api-gateway (port 8080)
  Also allow DNS (UDP/TCP port 53) to kube-system namespace

### Policy 3: Allow API Gateway Traffic
- Name: allow-api-gateway
- Namespace: online-banking
- PodSelector: app=api-gateway
- PolicyTypes: Ingress, Egress
- Ingress: Allow from pods with label app=frontend-app (port 8080)
- Egress:
    - Allow to pods with label app=auth-service (port 8081)
    - Allow to pods with label app=account-service (port 8082)
    - Allow DNS (UDP/TCP port 53) to kube-system namespace

### Policy 4: Allow Auth Service Ingress
- Name: allow-auth-service
- Namespace: online-banking
- PodSelector: app=auth-service
- PolicyTypes: Ingress
- Ingress: Allow from pods with label app=api-gateway (port 8081)

### Policy 5: Allow Account Service Traffic
- Name: allow-account-service
- Namespace: online-banking
- PodSelector: app=account-service
- PolicyTypes: Ingress, Egress
- Ingress: Allow from pods with label app=api-gateway (port 8082)
- Egress: Allow to pods with label app=account-db (port 5432)

### Policy 6: Allow Database Ingress (CRITICAL - PCI-DSS requirement)
- Name: allow-account-db-ingress
- Namespace: online-banking
- PodSelector: app=account-db
- PolicyTypes: Ingress
- Ingress: Allow ONLY from pods with label app=account-service (port 5432)
  NOTE: No other service may access the database directly.

## Verification Commands
kubectl get networkpolicy -n online-banking
kubectl describe networkpolicy default-deny-all -n online-banking
SPEC

chown ga:ga /home/ga/Desktop/network_topology_spec.md

# ── Record baseline (no network policies exist yet) ───────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/network_policy_zero_trust_start_ts

NP_COUNT=$(docker exec rancher kubectl get networkpolicy -n online-banking --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "Baseline network policy count: $NP_COUNT (expected: 0)"

# ── Navigate Firefox ──────────────────────────────────────────────────────────
echo "Navigating Firefox to network policies page..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/networking.k8s.io.networkpolicy" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/networking.k8s.io.networkpolicy' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

if ! wait_for_window "firefox\|mozilla\|rancher" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/network_policy_zero_trust_start.png

echo "=== network_policy_zero_trust setup complete ==="
echo ""
echo "online-banking namespace deployed with NO NetworkPolicies."
echo "Security topology spec is at: /home/ga/Desktop/network_topology_spec.md"
echo ""
