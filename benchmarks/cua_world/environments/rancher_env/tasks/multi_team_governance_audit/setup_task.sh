#!/bin/bash
# Setup script for multi_team_governance_audit task
#
# This script creates a PARTIALLY CONFIGURED and MISCONFIGURED governance setup:
# - platform-infra project: exists with WRONG quota values
# - Infrastructure Operator role template: exists but INCOMPLETE (missing 4 resources)
# - ops-lead user: exists but bound to WRONG role (Cluster Owner instead of Infrastructure Operator)
# - team-alpha project: MISSING (agent must create)
# - Release Manager role template: MISSING (agent must create)
# - alpha-lead, alpha-dev users: MISSING (agent must create)

echo "=== Setting up multi_team_governance_audit task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 120; then
    echo "WARNING: Rancher API not ready"
fi

# ── Clean up previous state ──────────────────────────────────────────────────
echo "Cleaning up previous state..."

TOKEN=$(get_rancher_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not get admin token. Retrying..."
    sleep 10
    TOKEN=$(get_rancher_token)
fi

if [ -n "$TOKEN" ]; then
    # Clean users from previous runs
    for user in ops-lead alpha-lead alpha-dev; do
        USER_ID=$(curl -sk "$RANCHER_URL/v3/users?username=$user" \
            -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id // empty')
        if [ -n "$USER_ID" ]; then
            echo "Deleting stale user: $user ($USER_ID)"
            curl -sk -X DELETE "$RANCHER_URL/v3/users/$USER_ID" \
                -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1
        fi
    done

    # Clean projects from previous runs
    for proj in platform-infra team-alpha; do
        PROJ_ID=$(curl -sk "$RANCHER_URL/v3/projects?clusterId=local&name=$proj" \
            -H "Authorization: Bearer $TOKEN" | jq -r '.data[0].id // empty')
        if [ -n "$PROJ_ID" ]; then
            echo "Deleting stale project: $proj ($PROJ_ID)"
            curl -sk -X DELETE "$RANCHER_URL/v3/projects/$PROJ_ID" \
                -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1
        fi
    done

    # Clean custom role templates from previous runs
    for role_name in "Infrastructure Operator" "Release Manager"; do
        ROLE_ID=$(curl -sk "$RANCHER_URL/v3/roleTemplates" \
            -H "Authorization: Bearer $TOKEN" | \
            jq -r --arg name "$role_name" '.data[] | select(.name == $name) | .id // empty')
        if [ -n "$ROLE_ID" ]; then
            echo "Deleting stale role template: $role_name ($ROLE_ID)"
            curl -sk -X DELETE "$RANCHER_URL/v3/roleTemplates/$ROLE_ID" \
                -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1
        fi
    done

fi

sleep 5

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/multi_team_governance_audit_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ── Create BROKEN platform-infra project (WRONG quotas) ─────────────────────
echo "Creating platform-infra project with INCORRECT quotas..."

# Quotas are deliberately WRONG:
# CPU should be 6000m but is set to 8000m
# Memory should be 12Gi but is set to 16Gi
# NS Default CPU should be 2000m but is set to 4000m
# NS Default Memory should be 4Gi but is set to 8Gi
# Pods limit 40 and NS default 20 are correct (to make audit non-trivial)
PLATFORM_PROJECT=$(curl -sk -X POST "$RANCHER_URL/v3/projects" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "platform-infra",
        "clusterId": "local",
        "resourceQuota": {
            "limit": {
                "limitsCpu": "8000m",
                "limitsMemory": "16384Mi",
                "pods": "40"
            }
        },
        "namespaceDefaultResourceQuota": {
            "limit": {
                "limitsCpu": "4000m",
                "limitsMemory": "8192Mi",
                "pods": "20"
            }
        }
    }')

PLATFORM_PROJECT_ID=$(echo "$PLATFORM_PROJECT" | jq -r '.id // empty')
echo "Created platform-infra project: $PLATFORM_PROJECT_ID"

# ── Create INCOMPLETE Infrastructure Operator role template ──────────────────
echo "Creating INCOMPLETE Infrastructure Operator role template..."

# Only has nodes and namespaces — deliberately MISSING:
# persistentvolumes, storageclasses, events, persistentvolumeclaims
INFRA_ROLE=$(curl -sk -X POST "$RANCHER_URL/v3/roleTemplates" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Infrastructure Operator",
        "context": "cluster",
        "rules": [
            {
                "apiGroups": [""],
                "resources": ["nodes"],
                "verbs": ["get", "list", "watch"]
            },
            {
                "apiGroups": [""],
                "resources": ["namespaces"],
                "verbs": ["get", "list", "watch"]
            }
        ]
    }')

INFRA_ROLE_ID=$(echo "$INFRA_ROLE" | jq -r '.id // empty')
echo "Created Infrastructure Operator role: $INFRA_ROLE_ID"

# ── Create ops-lead user ─────────────────────────────────────────────────────
echo "Creating ops-lead user..."

OPS_USER=$(curl -sk -X POST "$RANCHER_URL/v3/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "ops-lead",
        "password": "OpsLead2024!#",
        "mustChangePassword": false,
        "enabled": true
    }')

OPS_USER_ID=$(echo "$OPS_USER" | jq -r '.id // empty')
OPS_PRINCIPAL_ID="local://$OPS_USER_ID"
echo "Created ops-lead user: $OPS_USER_ID"

# ── Bind ops-lead to Cluster Owner (WRONG — should be Infrastructure Operator) ──
echo "Binding ops-lead to Cluster Owner (deliberately WRONG)..."

if [ -n "$OPS_USER_ID" ]; then
    curl -sk -X POST "$RANCHER_URL/v3/clusterRoleTemplateBindings" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"clusterId\": \"local\",
            \"userPrincipalId\": \"$OPS_PRINCIPAL_ID\",
            \"roleTemplateId\": \"cluster-owner\"
        }" >/dev/null 2>&1
    echo "Bound ops-lead to cluster-owner"
fi

# ── Write governance specification to desktop ────────────────────────────────
echo "Writing governance spec to desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/governance_spec.md << 'SPEC'
# Platform Governance Specification

This document defines the target-state configuration for multi-team access control
on the Rancher-managed local cluster. All items must be implemented exactly as specified.

---

## 1. Rancher Projects

### Project: platform-infra

| Quota Dimension | Project Limit | Namespace Default |
|----------------|---------------|-------------------|
| CPU            | 6000m         | 2000m             |
| Memory         | 12Gi          | 4Gi               |
| Pods           | 40            | 20                |

### Project: team-alpha

| Quota Dimension | Project Limit | Namespace Default |
|----------------|---------------|-------------------|
| CPU            | 4000m         | 2000m             |
| Memory         | 8Gi           | 4Gi               |
| Pods           | 30            | 15                |

---

## 2. Custom Role Templates

### Infrastructure Operator (Cluster scope)

This role grants infrastructure-level visibility and management capabilities.

| Resource               | API Group        | Allowed Verbs                          |
|-----------------------|------------------|----------------------------------------|
| nodes                 | _(core)_         | get, list, watch                       |
| persistentvolumes     | _(core)_         | get, list, watch, create, update, delete |
| storageclasses        | storage.k8s.io   | get, list, watch, create, update, delete |
| namespaces            | _(core)_         | get, list, watch                       |
| events                | _(core)_         | get, list, watch                       |
| persistentvolumeclaims| _(core)_         | get, list, watch                       |

**Requirements**: No wildcard (*) permissions allowed.

### Release Manager (Project scope)

This role provides full deployment lifecycle management with read-only access to
configuration and strict exclusion of secret-writing and execution capabilities.

| Resource     | API Group          | Allowed Verbs                                    |
|-------------|--------------------|-------------------------------------------------|
| deployments | apps               | get, list, watch, create, update, patch, delete  |
| services    | _(core)_           | get, list, watch, create, update, patch, delete  |
| ingresses   | networking.k8s.io  | get, list, watch, create, update, patch, delete  |
| configmaps  | _(core)_           | get, list, watch                                 |
| secrets     | _(core)_           | get, list                                        |
| pods        | _(core)_           | get, list, watch                                 |
| pods/log    | _(core)_           | get                                              |
| replicasets | apps               | get, list, watch                                 |

**Compliance Requirements**:
- The Release Manager role must NOT grant create, update, delete, or patch access to secrets.
- The Release Manager role must NOT include pods/exec permissions.
- No wildcard (*) permissions allowed.

---

## 3. Users

| Username   | Password        | Role Assignment                                 |
|-----------|-----------------|------------------------------------------------|
| ops-lead  | OpsLead2024!#   | Infrastructure Operator - cluster-wide          |
| alpha-lead| AlphaLead2024!# | Release Manager - on the team-alpha project     |
| alpha-dev | AlphaDev2024!#  | Member (read-only) - on the team-alpha project  |

---

## 4. Current State (Audit Findings)

The following issues have been identified during the handoff review:

1. **platform-infra project**: Exists but has wrong CPU and memory quotas.
   The current values are too high and do not match the approved budget.
2. **team-alpha project**: Does not exist. Must be created.
3. **Infrastructure Operator role**: Exists but is incomplete. It only covers
   nodes and namespaces. Storage and event resources are missing.
4. **Release Manager role**: Does not exist. Must be created per the spec above.
5. **ops-lead user**: Exists but is assigned Cluster Owner privileges, which
   violates least-privilege requirements. Must be reassigned to Infrastructure Operator only.
6. **alpha-lead and alpha-dev users**: Do not exist. Must be created and assigned
   to the team-alpha project with the appropriate roles.
SPEC

chmod 644 /home/ga/Desktop/governance_spec.md
chown ga:ga /home/ga/Desktop/governance_spec.md

# ── Ensure Firefox is running and focused ────────────────────────────────────
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost/dashboard &"
    sleep 5
fi

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Broken state summary:"
echo "  - platform-infra project: CPU=8000m (should be 6000m), Memory=16Gi (should be 12Gi)"
echo "  - Infrastructure Operator role: only nodes+namespaces (missing 4 resource types)"
echo "  - ops-lead user: bound to Cluster Owner (should be Infrastructure Operator)"
echo "  - team-alpha project: MISSING"
echo "  - Release Manager role: MISSING"
echo "  - alpha-lead, alpha-dev users: MISSING"
