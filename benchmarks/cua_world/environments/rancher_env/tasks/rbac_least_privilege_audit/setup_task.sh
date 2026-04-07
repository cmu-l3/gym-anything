#!/bin/bash
# Setup script for rbac_least_privilege_audit task
# Injects 4 realistic RBAC violations into the cluster

echo "=== Setting up rbac_least_privilege_audit task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up any previous injections ────────────────────────────────────────
echo "Cleaning up previous RBAC injections..."
docker exec rancher kubectl delete clusterrolebinding dev-all-access 2>/dev/null || true
docker exec rancher kubectl delete clusterrolebinding monitoring-cluster-admin 2>/dev/null || true
docker exec rancher kubectl delete role wildcard-staging-role -n staging 2>/dev/null || true
docker exec rancher kubectl delete rolebinding ci-elevated-access -n staging 2>/dev/null || true

# Clean up service accounts we're about to create
docker exec rancher kubectl delete serviceaccount dev-automation -n development 2>/dev/null || true
docker exec rancher kubectl delete serviceaccount metrics-collector -n monitoring 2>/dev/null || true
docker exec rancher kubectl delete serviceaccount ci-runner -n staging 2>/dev/null || true

sleep 3

# ── Create Service Accounts ──────────────────────────────────────────────────
echo "Creating service accounts..."
docker exec rancher kubectl create serviceaccount dev-automation -n development 2>/dev/null || true
docker exec rancher kubectl create serviceaccount metrics-collector -n monitoring 2>/dev/null || true
docker exec rancher kubectl create serviceaccount ci-runner -n staging 2>/dev/null || true

# ── Violation 1: dev-automation with cluster-admin ClusterRoleBinding ───────
# Real violation: CI/CD automation SA should only deploy to its own namespace,
# not have cluster-wide admin access
echo "Injecting violation 1: dev-automation cluster-admin ClusterRoleBinding..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dev-all-access
  labels:
    created-by: setup-script
    violation-type: excessive-cluster-admin
subjects:
- kind: ServiceAccount
  name: dev-automation
  namespace: development
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Violation 2: wildcard Role in staging ────────────────────────────────────
# Real violation: an overly broad role that grants * on * in staging
echo "Injecting violation 2: wildcard Role in staging..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: wildcard-staging-role
  namespace: staging
  labels:
    created-by: setup-script
    violation-type: wildcard-permissions
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: wildcard-staging-binding
  namespace: staging
  labels:
    created-by: setup-script
subjects:
- kind: ServiceAccount
  name: ci-runner
  namespace: staging
roleRef:
  kind: Role
  name: wildcard-staging-role
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Violation 3: metrics-collector with cluster-admin ClusterRoleBinding ────
# Real violation: a monitoring SA should only read metrics endpoints,
# not have full cluster-admin
echo "Injecting violation 3: metrics-collector cluster-admin ClusterRoleBinding..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-cluster-admin
  labels:
    created-by: setup-script
    violation-type: excessive-cluster-admin
subjects:
- kind: ServiceAccount
  name: metrics-collector
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Violation 4: ci-runner with cluster-admin RoleBinding in staging ─────────
# Real violation: CI/CD service account should use a scoped deployer role,
# not cluster-admin even within staging
echo "Injecting violation 4: ci-runner cluster-admin RoleBinding in staging..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-elevated-access
  namespace: staging
  labels:
    created-by: setup-script
    violation-type: excessive-namespace-admin
subjects:
- kind: ServiceAccount
  name: ci-runner
  namespace: staging
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/rbac_least_privilege_audit_start_ts

INITIAL_DEV_CRB=$(docker exec rancher kubectl get clusterrolebinding dev-all-access -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")
INITIAL_MON_CRB=$(docker exec rancher kubectl get clusterrolebinding monitoring-cluster-admin -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")
INITIAL_WILDCARD=$(docker exec rancher kubectl get role wildcard-staging-role -n staging -o jsonpath='{.rules[0].verbs}' 2>/dev/null || echo "deleted")
INITIAL_CI_RB=$(docker exec rancher kubectl get rolebinding ci-elevated-access -n staging -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "deleted")

echo "Baseline:"
echo "  dev-all-access roleRef: $INITIAL_DEV_CRB"
echo "  monitoring-cluster-admin roleRef: $INITIAL_MON_CRB"
echo "  wildcard-staging-role verbs: $INITIAL_WILDCARD"
echo "  ci-elevated-access roleRef: $INITIAL_CI_RB"

# ── Navigate Firefox to RBAC section ────────────────────────────────────────
echo "Navigating Firefox to cluster RBAC section..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/rbac.authorization.k8s.io.clusterrolebinding" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/rbac.authorization.k8s.io.clusterrolebinding' > /tmp/firefox_task.log 2>&1 &"
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
take_screenshot /tmp/rbac_least_privilege_audit_start.png

echo "=== rbac_least_privilege_audit setup complete ==="
echo ""
echo "RBAC violations have been injected. The agent must audit and remediate all violations."
echo ""
