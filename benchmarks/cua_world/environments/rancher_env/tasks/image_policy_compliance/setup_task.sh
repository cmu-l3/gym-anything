#!/bin/bash
# Setup script for image_policy_compliance task
# Creates the platform-services namespace and 4 deployments with image policy violations.

echo "=== Setting up image_policy_compliance task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace platform-services --wait=false 2>/dev/null || true
sleep 5

# ── Create namespace ──────────────────────────────────────────────────────────
echo "Creating platform-services namespace..."
docker exec rancher kubectl create namespace platform-services 2>/dev/null || true

# ── Deploy workloads WITH violations ──────────────────────────────────────────
echo "Deploying workloads with image policy violations..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-proxy
  namespace: platform-services
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-proxy
  template:
    metadata:
      labels:
        app: web-proxy
    spec:
      containers:
      - name: proxy
        image: nginx:latest            # VIOLATION: :latest tag
        # VIOLATION: missing imagePullPolicy (defaults to Always for :latest)
        # VIOLATION: missing securityContext.allowPrivilegeEscalation: false
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-store
  namespace: platform-services
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache-store
  template:
    metadata:
      labels:
        app: cache-store
    spec:
      containers:
      - name: redis
        image: redis:latest            # VIOLATION: :latest tag
        imagePullPolicy: Always        # VIOLATION: wrong pull policy
        # VIOLATION: missing securityContext.allowPrivilegeEscalation: false
        ports:
        - containerPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: task-runner
  namespace: platform-services
spec:
  replicas: 1
  selector:
    matchLabels:
      app: task-runner
  template:
    metadata:
      labels:
        app: task-runner
    spec:
      containers:
      - name: runner
        image: busybox:latest          # VIOLATION: :latest tag
        command: ["sleep", "3600"]
        # VIOLATION: missing imagePullPolicy
        # VIOLATION: missing securityContext.allowPrivilegeEscalation: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-agent
  namespace: platform-services
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      containers:
      - name: fluentd
        image: fluentd:latest          # VIOLATION: :latest tag
        imagePullPolicy: Always        # VIOLATION: wrong pull policy
        securityContext:
          privileged: true             # VIOLATION: must be false
        # VIOLATION: missing securityContext.allowPrivilegeEscalation: false
MANIFEST

# ── Write the policy specification to the desktop ─────────────────────────────
echo "Writing image policy spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/image_policy_spec.md << 'SPEC'
# Container Image Policy — Platform Services

## Effective Date: Immediate
## Compliance Deadline: End of current sprint

### Policy Requirements

All deployments in the `platform-services` namespace MUST comply with:

#### 1. Image Version Pinning
All container images must use specific, immutable version tags. The `:latest` tag is prohibited.

| Deployment   | Approved Image        |
|-------------|----------------------|
| web-proxy    | nginx:1.25.4         |
| cache-store  | redis:7.2.4          |
| task-runner  | busybox:1.36.1       |
| log-agent    | fluentd:v1.16-1      |

#### 2. Image Pull Policy
All containers must set `imagePullPolicy: IfNotPresent` to avoid unnecessary registry pulls
and to ensure deterministic deployments from cached images.

#### 3. Security Context Hardening
All containers must include the following securityContext fields:
- `allowPrivilegeEscalation: false`

Additionally, any container currently running with `privileged: true` must be changed to
`privileged: false`.

### Rationale
- Unpinned images cause non-reproducible deployments
- `Always` pull policy increases deployment latency and registry dependency
- Privilege escalation is the #1 container escape vector (CVE-2019-5736)
- Privileged containers have full host access and violate least-privilege
SPEC
chown ga:ga /home/ga/Desktop/image_policy_spec.md
chmod 644 /home/ga/Desktop/image_policy_spec.md

# Focus Firefox (Rancher dashboard)
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="