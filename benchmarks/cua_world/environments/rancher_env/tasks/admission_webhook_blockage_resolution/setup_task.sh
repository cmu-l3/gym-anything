#!/bin/bash
# Setup script for admission_webhook_blockage_resolution task
# Injects broken Validating and Mutating webhook configurations that block operations

echo "=== Setting up admission_webhook_blockage_resolution task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── 1. Clean up any previous state ──────────────────────────────────────────
echo "Cleaning up previous webhook state..."
docker exec rancher kubectl delete validatingwebhookconfiguration security-policy-validator --wait=false 2>/dev/null || true
docker exec rancher kubectl delete mutatingwebhookconfiguration resource-defaults-injector --wait=false 2>/dev/null || true
docker exec rancher kubectl delete namespace security-system --wait=false 2>/dev/null || true
docker exec rancher kubectl delete deployment webhook-test -n staging --wait=false 2>/dev/null || true
sleep 5

# ── 2. Setup namespaces and labels ──────────────────────────────────────────
echo "Creating security-system namespace (service intentionally omitted)..."
docker exec rancher kubectl create namespace security-system 2>/dev/null || true

echo "Labeling staging namespace to enforce webhooks..."
docker exec rancher kubectl label namespace staging webhook-enforce=true --overwrite 2>/dev/null || true

# ── 3. Generate a valid CA bundle for the webhooks ──────────────────────────
echo "Generating CA bundle for webhooks..."
docker exec rancher sh -c 'openssl req -x509 -newkey rsa:2048 -keyout /tmp/webhook.key -out /tmp/webhook.crt -days 365 -nodes -subj "/CN=security-policy-svc.security-system.svc"' 2>/dev/null
CABUNDLE=$(docker exec rancher base64 -w 0 /tmp/webhook.crt)

# ── 4. Inject broken webhook configurations ─────────────────────────────────
echo "Injecting broken webhook configurations..."

docker exec -i rancher kubectl apply -f - <<MANIFEST
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: security-policy-validator
  labels:
    injected-by: task-setup
webhooks:
  - name: validate.security.example.com
    clientConfig:
      service:
        name: security-policy-svc    # Intentionally missing service
        namespace: security-system
        path: "/validate"
        port: 443
      caBundle: ${CABUNDLE}
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: ["apps"]
        apiVersions: ["v1"]
        resources: ["deployments"]
    failurePolicy: Fail             # The core of the problem
    sideEffects: None
    admissionReviewVersions: ["v1"]
    namespaceSelector:
      matchLabels:
        webhook-enforce: "true"
---
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: resource-defaults-injector
  labels:
    injected-by: task-setup
webhooks:
  - name: mutate.security.example.com
    clientConfig:
      service:
        name: resource-injector-svc  # Intentionally missing service
        namespace: security-system
        path: "/mutate"
        port: 9443
      caBundle: ${CABUNDLE}
    rules:
      - operations: ["CREATE"]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
    failurePolicy: Fail             # The core of the problem
    sideEffects: None
    admissionReviewVersions: ["v1"]
    namespaceSelector:
      matchLabels:
        webhook-enforce: "true"
MANIFEST

# ── 5. Verify blockage is active (sanity check) ─────────────────────────────
echo "Testing webhook blockage (should fail)..."
if docker exec rancher kubectl create deployment test-blockage --image=nginx:alpine -n staging 2>/dev/null; then
    echo "WARNING: Webhooks failed to block the test deployment! Cleaning up..."
    docker exec rancher kubectl delete deployment test-blockage -n staging 2>/dev/null || true
else
    echo "Success: Webhooks are actively blocking operations in staging."
fi

# ── 6. Record timestamp and launch UI ───────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Opening Firefox to Rancher..."

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard/c/local/explorer > /dev/null 2>&1 &"
    sleep 5
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|rancher" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="