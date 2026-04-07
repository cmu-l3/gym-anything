#!/bin/bash
# Export script for supply_chain_security_remediation
# Queries the supply-chain namespace for compliance state of each workload

echo "=== Exporting supply_chain_security_remediation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/supply_chain_security_remediation_end.png

TASK_START=$(cat /tmp/supply_chain_security_remediation_start_ts 2>/dev/null || echo "0")

# ── Criterion 1: registry-proxy — privileged removed, seccompProfile set, limits set ──
echo "Checking registry-proxy security context..."

REG_PRIVILEGED=$(docker exec rancher kubectl get deployment registry-proxy -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.privileged}' 2>/dev/null || echo "")
[ -z "$REG_PRIVILEGED" ] && REG_PRIVILEGED="null"

REG_SECCOMP=$(docker exec rancher kubectl get deployment registry-proxy -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.seccompProfile.type}' 2>/dev/null || echo "")
[ -z "$REG_SECCOMP" ] && REG_SECCOMP=""

REG_CPU_LIMIT=$(docker exec rancher kubectl get deployment registry-proxy -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
[ -z "$REG_CPU_LIMIT" ] && REG_CPU_LIMIT=""

REG_MEM_LIMIT=$(docker exec rancher kubectl get deployment registry-proxy -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
[ -z "$REG_MEM_LIMIT" ] && REG_MEM_LIMIT=""

# ── Criterion 2: artifact-scanner — docker.sock removed, runAsNonRoot set ────
echo "Checking artifact-scanner..."

SCANNER_VOLUMES=$(docker exec rancher kubectl get deployment artifact-scanner -n supply-chain \
    -o jsonpath='{.spec.template.spec.volumes}' 2>/dev/null || echo "")
SCANNER_DOCKER_SOCK="false"
if echo "$SCANNER_VOLUMES" | grep -q "docker.sock"; then
    SCANNER_DOCKER_SOCK="true"
fi

SCANNER_RUN_AS_NONROOT=$(docker exec rancher kubectl get deployment artifact-scanner -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsNonRoot}' 2>/dev/null || echo "")
[ -z "$SCANNER_RUN_AS_NONROOT" ] && SCANNER_RUN_AS_NONROOT="null"

SCANNER_RUN_AS_USER=$(docker exec rancher kubectl get deployment artifact-scanner -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsUser}' 2>/dev/null || echo "0")
[ -z "$SCANNER_RUN_AS_USER" ] && SCANNER_RUN_AS_USER="0"

# Check volume mounts too for docker.sock
SCANNER_MOUNTS=$(docker exec rancher kubectl get deployment artifact-scanner -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}' 2>/dev/null || echo "")
if echo "$SCANNER_MOUNTS" | grep -q "docker.sock"; then
    SCANNER_DOCKER_SOCK="true"
fi

# ── Criterion 3: build-agent — SYS_ADMIN capability removed ─────────────────
echo "Checking build-agent capabilities..."

BUILD_CAPS=$(docker exec rancher kubectl get deployment build-agent -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.add}' 2>/dev/null || echo "")
[ -z "$BUILD_CAPS" ] && BUILD_CAPS="[]"

BUILD_HAS_SYS_ADMIN="false"
if echo "$BUILD_CAPS" | grep -q "SYS_ADMIN"; then
    BUILD_HAS_SYS_ADMIN="true"
fi

# ── Criterion 4: deploy-controller SA — cluster-admin CRB removed ────────────
echo "Checking deploy-controller RBAC..."

# Check if ClusterRoleBinding still exists binding deploy-controller-sa to cluster-admin
CTRL_ADMIN_CRB=$(docker exec rancher kubectl get clusterrolebinding deploy-controller-admin \
    -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "")
[ -z "$CTRL_ADMIN_CRB" ] && CTRL_ADMIN_CRB="not-found"

# Also check if ANY CRB binds the deploy-controller-sa to cluster-admin (it might be renamed)
CTRL_ANY_ADMIN_CRB=$(docker exec rancher kubectl get clusterrolebinding \
    -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    subs = item.get('subjects', [])
    role = item.get('roleRef', {}).get('name', '')
    for s in subs:
        if s.get('name') == 'deploy-controller-sa' and s.get('namespace') == 'supply-chain':
            if role == 'cluster-admin':
                print('cluster-admin')
                sys.exit()
print('none')
" 2>/dev/null || echo "none")
[ -z "$CTRL_ANY_ADMIN_CRB" ] && CTRL_ANY_ADMIN_CRB="none"

# Also check sbom-generator has resource limits (bonus check)
SBOM_CPU_LIMIT=$(docker exec rancher kubectl get deployment sbom-generator -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
[ -z "$SBOM_CPU_LIMIT" ] && SBOM_CPU_LIMIT=""

SBOM_MEM_LIMIT=$(docker exec rancher kubectl get deployment sbom-generator -n supply-chain \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
[ -z "$SBOM_MEM_LIMIT" ] && SBOM_MEM_LIMIT=""

# ── Check overall pod health ──────────────────────────────────────────────────
TOTAL_RUNNING=$(docker exec rancher kubectl get pods -n supply-chain --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$TOTAL_RUNNING" ] && TOTAL_RUNNING=0

# ── Write result JSON ─────────────────────────────────────────────────────────
cat > /tmp/supply_chain_security_remediation_result.json << EOF
{
  "task_start": $TASK_START,
  "namespace": "supply-chain",
  "registry_proxy": {
    "privileged": "$REG_PRIVILEGED",
    "seccomp_profile": "$REG_SECCOMP",
    "cpu_limit": "$REG_CPU_LIMIT",
    "mem_limit": "$REG_MEM_LIMIT"
  },
  "artifact_scanner": {
    "has_docker_sock_mount": $SCANNER_DOCKER_SOCK,
    "run_as_non_root": "$SCANNER_RUN_AS_NONROOT",
    "run_as_user": $SCANNER_RUN_AS_USER
  },
  "build_agent": {
    "capabilities_add": "$BUILD_CAPS",
    "has_sys_admin": $BUILD_HAS_SYS_ADMIN
  },
  "deploy_controller": {
    "original_crb_role": "$CTRL_ADMIN_CRB",
    "any_cluster_admin_binding": "$CTRL_ANY_ADMIN_CRB"
  },
  "sbom_generator": {
    "cpu_limit": "$SBOM_CPU_LIMIT",
    "mem_limit": "$SBOM_MEM_LIMIT"
  },
  "total_pods_running": $TOTAL_RUNNING
}
EOF

echo "Result JSON written."
echo "registry-proxy privileged=$REG_PRIVILEGED, seccomp=$REG_SECCOMP"
echo "artifact-scanner docker_sock=$SCANNER_DOCKER_SOCK, runAsNonRoot=$SCANNER_RUN_AS_NONROOT"
echo "build-agent SYS_ADMIN=$BUILD_HAS_SYS_ADMIN"
echo "deploy-controller cluster-admin binding=$CTRL_ANY_ADMIN_CRB"

echo "=== Export Complete ==="
