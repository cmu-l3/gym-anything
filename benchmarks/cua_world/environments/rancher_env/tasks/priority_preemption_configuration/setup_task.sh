#!/bin/bash
# Setup script for priority_preemption_configuration task
# Ensures the staging namespace workloads exist without priority classes,
# drops the specification file on the desktop.

echo "=== Setting up priority_preemption_configuration task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up any previous run's PriorityClasses ──────────────────────────────
echo "Cleaning up any custom PriorityClasses..."
for pc in platform-critical business-critical standard batch-low; do
    docker exec rancher kubectl delete priorityclass "$pc" --ignore-not-found=true 2>/dev/null || true
done

# Wait for deletion
sleep 2

# ── Ensure staging namespace deployments have NO priorityClassName ───────────
echo "Resetting priorityClassName on staging workloads..."
docker exec rancher kubectl patch deployment redis-primary -n staging --type=json \
    -p='[{"op": "remove", "path": "/spec/template/spec/priorityClassName"}]' 2>/dev/null || true

docker exec rancher kubectl patch deployment nginx-web -n staging --type=json \
    -p='[{"op": "remove", "path": "/spec/template/spec/priorityClassName"}]' 2>/dev/null || true

# Wait for pods to stabilize after patch
sleep 10

# ── Drop the specification file on the desktop ───────────────────────────────
echo "Writing priority tier spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/priority_tier_spec.yaml << 'SPEC'
# Priority Tier Specification for Capacity Management
# Implement these PriorityClasses and workload assignments before Q4 earnings window
#
# IMPORTANT: Only ONE PriorityClass may have globalDefault: true
# IMPORTANT: Batch workloads must NOT preempt other pods (preemptionPolicy: Never)

priorityClasses:
  - name: platform-critical
    value: 1000000
    globalDefault: false
    preemptionPolicy: PreemptLowerPriority
    description: "Reserved for platform infrastructure (ingress controllers, monitoring, DNS)"

  - name: business-critical
    value: 750000
    globalDefault: false
    preemptionPolicy: PreemptLowerPriority
    description: "Business-critical data services (databases, caches, message queues)"

  - name: standard
    value: 500000
    globalDefault: true
    preemptionPolicy: PreemptLowerPriority
    description: "Default tier for web frontends and standard application workloads"

  - name: batch-low
    value: 100000
    globalDefault: false
    preemptionPolicy: Never
    description: "Non-preempting tier for batch analytics, CI runners, and dev tools"

workloadAssignments:
  staging:
    - deployment: redis-primary
      priorityClassName: business-critical
      reason: "Redis cache is critical for transaction processing latency"
    - deployment: nginx-web
      priorityClassName: standard
      reason: "Web frontend uses the default application tier"
SPEC

chown ga:ga /home/ga/Desktop/priority_tier_spec.yaml

# ── Record baseline state ────────────────────────────────────────────────────
echo "Recording baseline state..."
date +%s > /tmp/task_start_time.txt

# Start Firefox if not already running (Rancher context usually starts it, but just in case)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard &"
    sleep 5
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="