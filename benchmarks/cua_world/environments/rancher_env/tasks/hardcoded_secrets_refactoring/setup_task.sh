#!/bin/bash
# Setup script for hardcoded_secrets_refactoring task

echo "=== Setting up hardcoded_secrets_refactoring task ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace customer-portal --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating customer-portal namespace..."
docker exec rancher kubectl create namespace customer-portal 2>/dev/null || true

# ── Deploy the vulnerable Deployment with hardcoded secrets ───────────────────
echo "Deploying backend-service with hardcoded secrets..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-service
  namespace: customer-portal
  labels:
    app: backend
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
        image: nginx:alpine
        command: ["/bin/sh", "-c", "echo 'Application starting...'; sleep 3600"]
        env:
        - name: API_KEY
          value: "sk_live_51MabcdeFghijKLmnoPQRstuvWxyz"
        - name: DB_PASS
          value: "ProdDB!SuperSecret99"
        - name: LOG_LEVEL
          value: "DEBUG"
        - name: ROUTING_RULES_JSON
          value: '{"routes": [{"path": "/api/v1", "backend": "service-v1"}, {"path": "/api/v2", "backend": "service-v2"}]}'
MANIFEST

# ── Drop the security audit ticket on the desktop ─────────────────────────────
echo "Writing security audit ticket to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/security_audit_ticket.md << 'TICKET'
# Security Audit Ticket: SEC-2026-042

**Severity:** CRITICAL
**Target:** Deployment `backend-service` in namespace `customer-portal`

## Findings
The `backend-service` deployment contains hardcoded plain-text secrets and configuration directly in its environment variables:
- `API_KEY`
- `DB_PASS`
- `LOG_LEVEL`
- `ROUTING_RULES_JSON` (A large JSON routing ruleset)

## Required Remediation
1. **Secrets:** Extract `API_KEY` (key: `api_key`) and `DB_PASS` (key: `db_pass`) into a Kubernetes Secret named `backend-secrets` in the same namespace.
2. **Standard Config:** Extract `LOG_LEVEL` (key: `log_level`) into a ConfigMap named `backend-config`.
3. **Volume Config:** Extract the JSON payload from `ROUTING_RULES_JSON` into a ConfigMap named `routing-config` under the key `routes.json`.
4. **Deployment Refactoring:**
   - Remove all four plain-text `value:` fields from the deployment.
   - Inject `API_KEY` and `DB_PASS` using `valueFrom: secretKeyRef`.
   - Inject `LOG_LEVEL` using `valueFrom: configMapKeyRef`.
   - Remove the `ROUTING_RULES_JSON` environment variable entirely.
   - Mount the `routing-config` ConfigMap as a volume at the exact path `/app/config/`.
5. Ensure the deployment successfully rolls out and the pod is Running.
TICKET

# Focus Firefox if open
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="