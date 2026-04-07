#!/bin/bash
echo "=== Setting up db_pss_remediation task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up any existing state
docker exec rancher kubectl delete namespace finance --wait=false 2>/dev/null || true
sleep 8

# Create namespace
docker exec rancher kubectl create namespace finance 2>/dev/null || true

# Generate TLS certs for the secure-db
mkdir -p /tmp/finance-certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /tmp/finance-certs/tls.key -out /tmp/finance-certs/tls.crt \
    -subj "/CN=postgres.finance.svc" 2>/dev/null

# Create secret with the certificates
docker exec rancher kubectl create secret tls db-tls-certs \
    -n finance \
    --cert=/tmp/finance-certs/tls.crt \
    --key=/tmp/finance-certs/tls.key 2>/dev/null

# Deploy the secure-db with conflicting strict security constraints
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-db
  namespace: finance
  labels:
    app: secure-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secure-db
  template:
    metadata:
      labels:
        app: secure-db
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
      containers:
      - name: postgres
        image: postgres:15-alpine
        args:
        - "-c"
        - "ssl=on"
        - "-c"
        - "ssl_cert_file=/etc/certs/tls.crt"
        - "-c"
        - "ssl_key_file=/etc/certs/tls.key"
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          value: "StrictSecurity123!"
        securityContext:
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        - name: certs
          mountPath: /etc/certs
          readOnly: true
        readinessProbe:
          exec:
            command:
            - pg_isready
            - "-U"
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: data
        emptyDir: {}
      - name: certs
        secret:
          secretName: db-tls-certs
          # Intentionally missing defaultMode. Defaults to 0644, which Postgres rejects.
MANIFEST

# Record start time
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="