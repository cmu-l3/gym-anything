#!/bin/bash
# Setup script for cluster_rbac_audit_and_remediation
# Creates 3 namespaces with 4 injected RBAC violations.
# Agent must read the review document, identify specific misconfigurations, and remediate.

echo "=== Setting up cluster_rbac_audit_and_remediation ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready, proceeding anyway"
fi

# ── Clean up any previous run ────────────────────────────────────────────────
echo "Cleaning up previous namespaces..."
docker exec rancher kubectl delete namespace dev-team qa-team platform-ops --timeout=60s 2>/dev/null || true
docker exec rancher kubectl delete clusterrolebinding ci-runner-edit-crb ops-agent-admin-crb 2>/dev/null || true
sleep 8

# ── Create namespaces ─────────────────────────────────────────────────────────
echo "Creating namespaces..."
docker exec rancher kubectl create namespace dev-team 2>/dev/null || true
docker exec rancher kubectl create namespace qa-team 2>/dev/null || true
docker exec rancher kubectl create namespace platform-ops 2>/dev/null || true

# Label qa-team and platform-ops with pod-security (correct)
docker exec rancher kubectl label namespace qa-team \
    pod-security.kubernetes.io/enforce=restricted \
    team=qa environment=test 2>/dev/null || true

docker exec rancher kubectl label namespace platform-ops \
    pod-security.kubernetes.io/enforce=restricted \
    team=platform environment=production 2>/dev/null || true

# dev-team: intentionally NOT labeled with pod-security (VIOLATION 4)
docker exec rancher kubectl label namespace dev-team \
    team=dev environment=development 2>/dev/null || true

# ── Create ServiceAccounts ─────────────────────────────────────────────────────
echo "Creating ServiceAccounts..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-runner
  namespace: dev-team
  labels:
    app: ci-runner
    team: dev
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ops-agent
  namespace: platform-ops
  labels:
    app: ops-agent
    team: platform
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: qa-automation
  namespace: qa-team
  labels:
    app: qa-automation
    team: qa
MANIFEST

# ── VIOLATION 1: ci-runner has ClusterRoleBinding to 'edit' (should be namespace RoleBinding) ──
echo "Injecting VIOLATION 1: ci-runner cluster-scoped edit binding..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ci-runner-edit-crb
  labels:
    violation: excessive-scope
    team: dev
subjects:
- kind: ServiceAccount
  name: ci-runner
  namespace: dev-team
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── VIOLATION 2: qa-tester Role has wildcard verbs on pods ───────────────────
echo "Injecting VIOLATION 2: qa-tester Role with wildcard verbs on pods..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: qa-tester
  namespace: qa-team
  labels:
    violation: wildcard-verbs
    team: qa
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["get", "list", "watch"]
MANIFEST

# Bind qa-tester to qa-automation SA
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: qa-automation-binding
  namespace: qa-team
subjects:
- kind: ServiceAccount
  name: qa-automation
  namespace: qa-team
roleRef:
  kind: Role
  name: qa-tester
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── VIOLATION 3: ops-agent has cluster-admin ClusterRoleBinding ──────────────
echo "Injecting VIOLATION 3: ops-agent cluster-admin binding..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ops-agent-admin-crb
  labels:
    violation: cluster-admin-over-permission
    team: platform
subjects:
- kind: ServiceAccount
  name: ops-agent
  namespace: platform-ops
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Create legitimate workloads to make namespaces realistic ──────────────────
echo "Deploying workloads in each namespace..."

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-dev
  namespace: dev-team
  labels:
    app: api-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-dev
  template:
    metadata:
      labels:
        app: api-dev
    spec:
      serviceAccountName: ci-runner
      containers:
      - name: api-dev
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-runner
  namespace: qa-team
  labels:
    app: test-runner
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-runner
  template:
    metadata:
      labels:
        app: test-runner
    spec:
      serviceAccountName: qa-automation
      containers:
      - name: test-runner
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
MANIFEST

docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ops-controller
  namespace: platform-ops
  labels:
    app: ops-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ops-controller
  template:
    metadata:
      labels:
        app: ops-controller
    spec:
      serviceAccountName: ops-agent
      containers:
      - name: ops-controller
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
MANIFEST

# ── Write the RBAC review findings document ───────────────────────────────────
echo "Writing RBAC review findings document to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/rbac_review_findings.md << 'DOC'
# Kubernetes RBAC Security Review — Findings Report

**Review Date**: 2024-12-01
**Reviewer**: Platform Security Engineering Team
**Scope**: Namespaces `dev-team`, `qa-team`, `platform-ops`
**Classification**: INTERNAL SENSITIVE

---

## Executive Summary

Four RBAC security violations were identified during the annual Kubernetes access control
review. All violations must be remediated within 48 hours per the company's security SLA.

---

## FINDING-A: Excessive RBAC Scope — CI/CD Pipeline Account (Dev Team)

**Severity**: HIGH
**Namespace**: `dev-team`
**Affected Account Type**: CI/CD pipeline ServiceAccount

**Description**: The CI/CD pipeline service account in the `dev-team` namespace has been
granted the `edit` ClusterRole via a **ClusterRoleBinding**. This gives the pipeline
account write access to ALL namespaces in the cluster, far exceeding what a CI/CD
pipeline requires for deploying to a single team's namespace.

**Required Fix**: Remove the ClusterRoleBinding. If the CI pipeline needs `edit` access,
create a **namespace-scoped RoleBinding** (not a ClusterRoleBinding) within `dev-team`
only. A ClusterRoleBinding with ClusterRole `edit` is what must be removed.

---

## FINDING-B: Wildcard Verb Permissions — QA Automation Role (QA Team)

**Severity**: HIGH
**Namespace**: `qa-team`
**Affected Role**: QA test automation Role

**Description**: The Role used by the QA automation team grants wildcard (`*`) verbs
on the `pods` resource. Wildcard verbs include `create`, `delete`, `exec`, `portforward`,
and `patch` — far more than needed for test observation. At minimum, `delete` and
`exec` on pods should not be granted to QA automation.

**Required Fix**: Modify the `qa-tester` Role in namespace `qa-team` to replace the
wildcard verbs `["*"]` on `pods` with specific verbs. The QA role should only need
`["get", "list", "watch"]` for pods. Remove the wildcard.

---

## FINDING-C: Cluster-Admin Binding — Platform Operations Account

**Severity**: CRITICAL
**Namespace**: `platform-ops`
**Affected Account Type**: Platform operations ServiceAccount

**Description**: The platform operations agent ServiceAccount (`ops-agent`) in the
`platform-ops` namespace is bound to the `cluster-admin` ClusterRole via a
ClusterRoleBinding. This grants unrestricted access to every resource in every namespace
and at the cluster level. No workload running in a namespace should have cluster-admin
permissions.

**Required Fix**: Remove the ClusterRoleBinding that grants `cluster-admin` to the
`ops-agent` ServiceAccount. Create a scoped Role or use an appropriate least-privilege
ClusterRole for the specific operations required.

---

## FINDING-D: Missing Namespace Pod Security Label (Dev Team)

**Severity**: MEDIUM
**Namespace**: `dev-team`
**Affected Resource Type**: Namespace configuration

**Description**: The `dev-team` namespace is missing the required pod security admission
label. Per company policy (aligned with Kubernetes Pod Security Standards), all
namespaces must have the enforcement mode label set to `restricted`:

```
pod-security.kubernetes.io/enforce: restricted
```

The `qa-team` and `platform-ops` namespaces already have this label. Only `dev-team`
is missing it.

**Required Fix**: Add the label `pod-security.kubernetes.io/enforce=restricted` to the
`dev-team` namespace.

---

## Remediation Checklist

- [ ] FINDING-A: Remove ClusterRoleBinding granting `edit` to CI runner account in dev-team
- [ ] FINDING-B: Update `qa-tester` Role to use specific verbs instead of `*` on pods
- [ ] FINDING-C: Remove ClusterRoleBinding granting `cluster-admin` to ops-agent in platform-ops
- [ ] FINDING-D: Add pod-security label `pod-security.kubernetes.io/enforce=restricted` to dev-team namespace

---

## Verification

After remediation, verify each fix:

```bash
# FINDING-A: No ClusterRoleBinding should bind ci-runner to edit
kubectl get clusterrolebindings -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data['items']:
    for s in item.get('subjects', []):
        if s.get('name') == 'ci-runner' and s.get('namespace') == 'dev-team':
            if item['roleRef']['name'] == 'edit' and item['kind'] == 'ClusterRoleBinding':
                print('STILL PRESENT:', item['metadata']['name'])
"

# FINDING-B: qa-tester Role should not have * verbs on pods
kubectl get role qa-tester -n qa-team -o jsonpath='{.rules}'

# FINDING-C: ops-agent should not have cluster-admin binding
kubectl get clusterrolebindings -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data['items']:
    for s in item.get('subjects', []):
        if s.get('name') == 'ops-agent' and s.get('namespace') == 'platform-ops':
            if item['roleRef']['name'] == 'cluster-admin':
                print('STILL PRESENT:', item['metadata']['name'])
"

# FINDING-D: dev-team namespace pod-security label
kubectl get namespace dev-team -o jsonpath='{.metadata.labels}'
```
DOC

chown ga:ga /home/ga/Desktop/rbac_review_findings.md

# ── Record baseline state ─────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/cluster_rbac_audit_and_remediation_start_ts

# ── Navigate Firefox to cluster RBAC overview ─────────────────────────────────
echo "Navigating Firefox to cluster RBAC overview..."
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

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/cluster_rbac_audit_and_remediation_start.png

echo "=== cluster_rbac_audit_and_remediation setup complete ==="
echo ""
echo "Namespaces created: dev-team, qa-team, platform-ops"
echo "Review document: /home/ga/Desktop/rbac_review_findings.md"
echo "4 RBAC violations injected. Agent must discover and remediate all."
