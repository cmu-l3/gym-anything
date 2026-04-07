#!/bin/bash
# Setup script for microservice_mesh_connectivity_restoration
# Deploys 5 microservices in ecommerce-platform namespace with 5 injected connectivity failures.
# Agent must read the architecture doc and diagnose/fix all failures without being told which resources are broken.

echo "=== Setting up microservice_mesh_connectivity_restoration ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready, proceeding anyway"
fi

# ── Clean up any previous run ────────────────────────────────────────────────
echo "Cleaning up previous ecommerce-platform namespace..."
docker exec rancher kubectl delete namespace ecommerce-platform --timeout=60s 2>/dev/null || true
sleep 5

# ── Create namespace ─────────────────────────────────────────────────────────
echo "Creating ecommerce-platform namespace..."
docker exec rancher kubectl create namespace ecommerce-platform 2>/dev/null || true

# ── Create ConfigMaps ─────────────────────────────────────────────────────────
echo "Creating ConfigMaps..."

# product-service config — correct
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: product-config
  namespace: ecommerce-platform
data:
  APP_PORT: "8080"
  CACHE_TTL: "300"
  LOG_LEVEL: "info"
MANIFEST

# payment-service config — INJECTED FAILURE: NOTIFICATION_HOST uses wrong namespace "ecommerce-staging" instead of "ecommerce-platform"
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ConfigMap
metadata:
  name: payment-config
  namespace: ecommerce-platform
data:
  APP_PORT: "3000"
  PAYMENT_GATEWAY_URL: "https://payments.internal/v2"
  NOTIFICATION_HOST: "notification-service.ecommerce-staging.svc.cluster.local"
  DB_POOL_SIZE: "10"
MANIFEST

# ── Deploy Workload 1: api-gateway ────────────────────────────────────────────
echo "Deploying api-gateway..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: ecommerce-platform
  labels:
    app: api-gateway
    tier: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        tier: frontend
    spec:
      containers:
      - name: api-gateway
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
MANIFEST

# INJECTED FAILURE 1: api-gateway Service has wrong selector 'app: api-gw' instead of 'app: api-gateway'
# This means the Service has no endpoints and traffic cannot reach api-gateway pods
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: ecommerce-platform
  labels:
    app: api-gateway
spec:
  selector:
    app: api-gw
  ports:
  - name: http
    port: 80
    targetPort: 80
  type: ClusterIP
MANIFEST

# ── Deploy Workload 2: product-service ───────────────────────────────────────
echo "Deploying product-service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service
  namespace: ecommerce-platform
  labels:
    app: product-service
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: product-service
  template:
    metadata:
      labels:
        app: product-service
        tier: backend
    spec:
      containers:
      - name: product-service
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        env:
        - name: APP_PORT
          value: "8080"
        - name: INVENTORY_HOST
          value: "inventory-service.ecommerce-staging.svc.cluster.local"
        - name: CACHE_HOST
          value: "redis-cache.ecommerce-platform.svc.cluster.local"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: product-service
  namespace: ecommerce-platform
  labels:
    app: product-service
spec:
  selector:
    app: product-service
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  type: ClusterIP
MANIFEST

# ── Deploy Workload 3: cart-service ──────────────────────────────────────────
echo "Deploying cart-service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart-service
  namespace: ecommerce-platform
  labels:
    app: cart-service
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart-service
  template:
    metadata:
      labels:
        app: cart-service
        tier: backend
    spec:
      containers:
      - name: cart-service
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8081
        env:
        - name: PAYMENT_HOST
          value: "payment-service.ecommerce-platform.svc.cluster.local"
        - name: PAYMENT_PORT
          value: "3000"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: cart-service
  namespace: ecommerce-platform
  labels:
    app: cart-service
spec:
  selector:
    app: cart-service
  ports:
  - name: http
    port: 8081
    targetPort: 8081
  type: ClusterIP
MANIFEST

# INJECTED FAILURE 3: NetworkPolicy blocks port 3000 egress from cart-service to payment-service
# Only allows port 8080, not 3000 which payment-service listens on
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-cart-egress
  namespace: ecommerce-platform
spec:
  podSelector:
    matchLabels:
      app: cart-service
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ecommerce-platform
    ports:
    - port: 8080
    - port: 8081
    - port: 5432
MANIFEST

# ── Deploy Workload 4: payment-service ───────────────────────────────────────
echo "Deploying payment-service..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: ecommerce-platform
  labels:
    app: payment-service
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-service
  template:
    metadata:
      labels:
        app: payment-service
        tier: backend
    spec:
      containers:
      - name: payment-service
        image: nginx:1.25-alpine
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: payment-config
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: payment-service
  namespace: ecommerce-platform
  labels:
    app: payment-service
spec:
  selector:
    app: payment-service
  ports:
  - name: http
    port: 3000
    targetPort: 3000
  type: ClusterIP
MANIFEST

# ── Deploy Workload 5: inventory-db ──────────────────────────────────────────
echo "Deploying inventory-db..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-db
  namespace: ecommerce-platform
  labels:
    app: inventory-db
    tier: data
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-db
  template:
    metadata:
      labels:
        app: inventory-db
        tier: data
    spec:
      containers:
      - name: inventory-db
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: inventory
        - name: POSTGRES_USER
          value: inventory_user
        - name: POSTGRES_PASSWORD
          value: changeme
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
MANIFEST

# INJECTED FAILURE 5: inventory-db Service port is 5433 instead of 5432
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Service
metadata:
  name: inventory-db
  namespace: ecommerce-platform
  labels:
    app: inventory-db
spec:
  selector:
    app: inventory-db
  ports:
  - name: postgres
    port: 5433
    targetPort: 5432
  type: ClusterIP
MANIFEST

# ── Write the service architecture document ───────────────────────────────────
echo "Writing service architecture document to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/service_architecture.md << 'DOC'
# Ecommerce Platform — Service Architecture Reference

## Overview

The `ecommerce-platform` Kubernetes namespace hosts a microservice-based ecommerce
backend. All services communicate via Kubernetes DNS (`<service>.<namespace>.svc.cluster.local`).
This document describes the **intended** post-migration topology.

## Namespace

`ecommerce-platform`

## Services and Their Connectivity

### 1. api-gateway
- **Purpose**: Public-facing API gateway, routes all external traffic to backend services
- **Kubernetes Service**: `api-gateway.ecommerce-platform.svc.cluster.local:80`
- **Pod Label**: `app: api-gateway`
- **Deployment replicas**: 2
- **Expected**: The `api-gateway` Kubernetes Service must select pods with label `app: api-gateway` and have at least 1 healthy endpoint

### 2. product-service
- **Purpose**: Manages product catalog, calls inventory-service for stock levels
- **Kubernetes Service**: `product-service.ecommerce-platform.svc.cluster.local:8080`
- **Pod Label**: `app: product-service`
- **Environment Variables**:
  - `INVENTORY_HOST`: Must be `inventory-service.ecommerce-platform.svc.cluster.local` (same namespace FQDN)
  - `CACHE_HOST`: `redis-cache.ecommerce-platform.svc.cluster.local`
- **Expected**: INVENTORY_HOST must use the `ecommerce-platform` namespace FQDN, not any other namespace

### 3. cart-service
- **Purpose**: Shopping cart management, calls payment-service to initiate checkout
- **Kubernetes Service**: `cart-service.ecommerce-platform.svc.cluster.local:8081`
- **Pod Label**: `app: cart-service`
- **Outbound connections**:
  - `payment-service.ecommerce-platform.svc.cluster.local` **port 3000** (TCP)
  - `product-service.ecommerce-platform.svc.cluster.local` **port 8080** (TCP)
- **Network Policy**: cart-service must have unrestricted egress to port 3000 within the namespace
- **Expected**: No NetworkPolicy may block TCP port 3000 egress from cart-service pods

### 4. payment-service
- **Purpose**: Handles payment processing and sends notifications
- **Kubernetes Service**: `payment-service.ecommerce-platform.svc.cluster.local:3000`
- **Pod Label**: `app: payment-service`
- **ConfigMap**: `payment-config` provides environment variables
  - `NOTIFICATION_HOST`: Must be `notification-service.ecommerce-platform.svc.cluster.local`
  - `PAYMENT_GATEWAY_URL`: `https://payments.internal/v2`
  - `APP_PORT`: `3000`
- **Expected**: `payment-config` ConfigMap `NOTIFICATION_HOST` value must contain `ecommerce-platform` namespace

### 5. inventory-db
- **Purpose**: PostgreSQL database for inventory data
- **Kubernetes Service**: `inventory-db.ecommerce-platform.svc.cluster.local:5432`
- **Pod Label**: `app: inventory-db`
- **Expected**: The `inventory-db` Kubernetes Service must expose port **5432** (standard PostgreSQL port)

## Inter-Service Communication Diagram

```
[External Traffic]
       │
       ▼
  api-gateway (:80)
       │
       ├──────────────► product-service (:8080)
       │                       │
       │                       └──────► inventory-db (:5432)
       │
       └──────────────► cart-service (:8081)
                               │
                               └──────► payment-service (:3000)
                                               │
                                               └──► notification-service (:8080)
                                                    [external — not in this NS]
```

## Kubernetes DNS Naming Convention

All internal service FQDNs follow:
```
<service-name>.<namespace>.svc.cluster.local
```

Services in THIS namespace (`ecommerce-platform`) must reference each other as:
```
<service-name>.ecommerce-platform.svc.cluster.local
```

References to any other namespace (e.g., `ecommerce-staging`, `default`) indicate a
misconfiguration and must be corrected.

## Migration Notes

This namespace was recently migrated from `ecommerce-staging`. All service references
must now use the `ecommerce-platform` namespace. Check environment variables, ConfigMaps,
Service selectors, and NetworkPolicies for any lingering references to the old namespace
or incorrect configurations.
DOC

chown ga:ga /home/ga/Desktop/service_architecture.md

# ── Record baseline state ─────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/microservice_mesh_connectivity_restoration_start_ts

# ── Navigate Firefox to the ecommerce-platform namespace ─────────────────────
echo "Navigating Firefox to ecommerce-platform namespace..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=ecommerce-platform" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=ecommerce-platform' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/microservice_mesh_connectivity_restoration_start.png

echo "=== microservice_mesh_connectivity_restoration setup complete ==="
echo ""
echo "The ecommerce-platform namespace has been created with 5 microservices."
echo "An architecture reference is available at /home/ga/Desktop/service_architecture.md"
echo "5 connectivity failures have been injected. The agent must discover and fix all of them."
