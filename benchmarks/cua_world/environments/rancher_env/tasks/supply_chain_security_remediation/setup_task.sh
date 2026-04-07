#!/bin/bash
# Setup script for supply_chain_security_remediation
# Creates a CI/CD supply chain namespace with 5 workloads containing 6 security violations.
# The agent must read the audit report, discover which workloads violate which policies,
# and remediate all findings without being told the specific resource names.

echo "=== Setting up supply_chain_security_remediation ==="

source /workspace/scripts/task_utils.sh

# Wait for Rancher API
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready, proceeding anyway"
fi

# ── Clean up any previous run ────────────────────────────────────────────────
echo "Cleaning up previous supply-chain namespace..."
docker exec rancher kubectl delete namespace supply-chain --timeout=60s 2>/dev/null || true
docker exec rancher kubectl delete clusterrolebinding deploy-controller-admin 2>/dev/null || true
sleep 5

# ── Create namespace ─────────────────────────────────────────────────────────
echo "Creating supply-chain namespace..."
docker exec rancher kubectl create namespace supply-chain 2>/dev/null || true

# ── Create ServiceAccount for deploy-controller ──────────────────────────────
echo "Creating ServiceAccount for deploy-controller..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deploy-controller-sa
  namespace: supply-chain
MANIFEST

# ── Violation: deploy-controller SA has cluster-admin ClusterRoleBinding ─────
# (CIS Kubernetes Benchmark finding: excessive cluster-level permissions)
echo "Injecting RBAC violation: cluster-admin binding for deploy-controller..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: deploy-controller-admin
  labels:
    app: deploy-controller
    violation: rbac-over-permission
subjects:
- kind: ServiceAccount
  name: deploy-controller-sa
  namespace: supply-chain
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Workload 1: registry-proxy (Violation: privileged=true, no seccompProfile, no limits) ──
echo "Deploying registry-proxy (violation: privileged, no seccompProfile, no resource limits)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry-proxy
  namespace: supply-chain
  labels:
    app: registry-proxy
    tier: infrastructure
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry-proxy
  template:
    metadata:
      labels:
        app: registry-proxy
        tier: infrastructure
    spec:
      containers:
      - name: registry-proxy
        image: nginx:1.25-alpine
        ports:
        - containerPort: 5000
        securityContext:
          privileged: true
          allowPrivilegeEscalation: true
MANIFEST

# ── Workload 2: artifact-scanner (Violation: hostPath docker.sock, no runAsNonRoot) ───────
echo "Deploying artifact-scanner (violation: docker.sock hostPath, no runAsNonRoot)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: artifact-scanner
  namespace: supply-chain
  labels:
    app: artifact-scanner
    tier: security
spec:
  replicas: 1
  selector:
    matchLabels:
      app: artifact-scanner
  template:
    metadata:
      labels:
        app: artifact-scanner
        tier: security
    spec:
      containers:
      - name: artifact-scanner
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
        securityContext:
          runAsUser: 0
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
MANIFEST

# ── Workload 3: build-agent (Violation: SYS_ADMIN capability) ────────────────
echo "Deploying build-agent (violation: SYS_ADMIN capability)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: build-agent
  namespace: supply-chain
  labels:
    app: build-agent
    tier: build
spec:
  replicas: 1
  selector:
    matchLabels:
      app: build-agent
  template:
    metadata:
      labels:
        app: build-agent
        tier: build
    spec:
      containers:
      - name: build-agent
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
        securityContext:
          capabilities:
            add:
            - SYS_ADMIN
            - NET_BIND_SERVICE
MANIFEST

# ── Workload 4: deploy-controller (Uses the over-privileged SA) ──────────────
echo "Deploying deploy-controller (uses cluster-admin SA)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deploy-controller
  namespace: supply-chain
  labels:
    app: deploy-controller
    tier: orchestration
spec:
  replicas: 1
  selector:
    matchLabels:
      app: deploy-controller
  template:
    metadata:
      labels:
        app: deploy-controller
        tier: orchestration
    spec:
      serviceAccountName: deploy-controller-sa
      containers:
      - name: deploy-controller
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          seccompProfile:
            type: RuntimeDefault
MANIFEST

# ── Workload 5: sbom-generator (No resource limits — stealthy violation) ──────
echo "Deploying sbom-generator (violation: no resource limits at all)..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sbom-generator
  namespace: supply-chain
  labels:
    app: sbom-generator
    tier: compliance
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sbom-generator
  template:
    metadata:
      labels:
        app: sbom-generator
        tier: compliance
    spec:
      containers:
      - name: sbom-generator
        image: nginx:1.25-alpine
        ports:
        - containerPort: 9090
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          seccompProfile:
            type: RuntimeDefault
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
MANIFEST

# ── Write the security audit report on the desktop ───────────────────────────
echo "Writing security audit report to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/security_audit_report.txt << 'REPORT'
================================================================================
INTERNAL SECURITY AUDIT REPORT
Container Security Assessment — Software Supply Chain Platform
Audit Date: 2024-11-15
Performed by: Information Security Team
Classification: INTERNAL USE ONLY
================================================================================

EXECUTIVE SUMMARY
-----------------
An automated container security scan and manual review of the 'supply-chain'
namespace revealed 6 high-severity policy violations. All findings must be
remediated before the next compliance review window.

The supply-chain platform runs 5 workloads across 4 functional tiers:
  - Infrastructure tier (registry proxy functions)
  - Security tier (artifact analysis)
  - Build tier (CI pipeline agents)
  - Orchestration tier (deployment automation)
  - Compliance tier (SBOM and attestation)

All findings are rated HIGH severity per the CIS Kubernetes Benchmark v1.8
and the company's Container Security Policy v3.2.

================================================================================
FINDINGS
================================================================================

FINDING-001: Privileged Container Execution
Severity: HIGH | CIS Control: 5.2.1
Tier Affected: Infrastructure
Description: A container in the infrastructure tier is running with
  privileged=true and allowPrivilegeEscalation=true. This grants the container
  near-root access to the host node kernel, enabling escape from the container
  boundary. Additionally, no seccomp profile is set, leaving all system calls
  unrestricted.
Required Fix: Remove privileged flag. Set seccompProfile to RuntimeDefault.
  Add explicit resource limits if absent.

FINDING-002: Host Socket Mount (Container Escape Vector)
Severity: HIGH | CIS Control: 5.2.4
Tier Affected: Security
Description: A container in the security tier mounts the host Docker daemon
  socket (/var/run/docker.sock) as a hostPath volume. This allows the container
  to control the Docker daemon directly, enabling creation of privileged
  containers and full host compromise. Container also runs as root (UID 0).
Required Fix: Remove the hostPath volume and volumeMount referencing the
  Docker socket. Set runAsNonRoot=true with a non-zero UID.

FINDING-003: Excessive Linux Capabilities
Severity: HIGH | CIS Control: 5.2.8
Tier Affected: Build
Description: A container in the build tier has SYS_ADMIN added to its
  Linux capability set. SYS_ADMIN is one of the most powerful capabilities,
  equivalent to partial root access, and enables mounting filesystems,
  modifying kernel parameters, and namespace operations.
Required Fix: Remove SYS_ADMIN from the capabilities.add list. If specific
  capabilities are needed, use only the minimum required set (e.g.,
  NET_BIND_SERVICE for port binding below 1024).

FINDING-004: Excessive RBAC Permissions — ServiceAccount
Severity: HIGH | CIS Control: 5.1.5
Tier Affected: Orchestration
Description: The ServiceAccount used by the deployment automation controller
  is bound to the cluster-admin ClusterRole via a ClusterRoleBinding. This
  grants cluster-wide administrative access, violating the principle of least
  privilege. A deployment controller requires only namespace-scoped permissions.
Required Fix: Remove the ClusterRoleBinding granting cluster-admin. Create
  a scoped Role (not ClusterRole) with only required permissions, or bind to
  an existing least-privilege role within the namespace.

FINDING-005: Missing Resource Limits
Severity: HIGH | CIS Control: 5.7.4
Tier Affected: Compliance
Description: A container in the compliance tier (SBOM/attestation functions)
  does not define resource requests or limits. Unbounded containers can cause
  resource starvation across the node, affecting other workloads. This also
  violates LimitRange enforcement policies.
Required Fix: Set CPU and memory requests and limits appropriate to the
  workload. For a lightweight SBOM generator, typical values:
  CPU request=100m, limit=500m; Memory request=128Mi, limit=512Mi.

FINDING-006: Missing Seccomp Profile + Privileged Flags
Severity: HIGH | CIS Control: 5.2.1 (duplicate finding, separate container)
Tier Affected: Infrastructure (same tier as FINDING-001, second container)
Description: Same infrastructure-tier workload as FINDING-001. Both the
  seccompProfile absence and privileged flag constitute separate control
  violations per the audit framework.
Required Fix: Addressed as part of FINDING-001 remediation.

================================================================================
REMEDIATION DEADLINE: 2024-11-22 (7 days from audit date)
ESCALATION CONTACT: security-oncall@company.internal
================================================================================
REPORT

chown ga:ga /home/ga/Desktop/security_audit_report.txt

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/supply_chain_security_remediation_start_ts

# ── Navigate Firefox to the supply-chain namespace ───────────────────────────
echo "Navigating Firefox to supply-chain namespace..."
sleep 3
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=supply-chain" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
else
    rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
    su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard/c/local/explorer/apps.deployment?namespace=supply-chain' > /tmp/firefox_task.log 2>&1 &"
    sleep 12
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

sleep 3
take_screenshot /tmp/supply_chain_security_remediation_start.png

echo "=== supply_chain_security_remediation setup complete ==="
echo ""
echo "The supply-chain namespace has been created with 5 workloads."
echo "An audit report is available at /home/ga/Desktop/security_audit_report.txt"
echo "The agent must read the report and remediate all 6 security violations."
