# Task: rbac_least_privilege_audit

## Overview

A security engineer must audit Kubernetes RBAC configuration across all namespaces. Multiple RBAC violations have been injected — each grants excessive permissions to service accounts in ways that a real security audit would flag. The engineer must discover all violations independently, remove or remediate them, and apply proper least-privilege replacements.

## Professional Context

**Occupation**: Information Security Engineer / Platform Security Engineer
**Why realistic**: Kubernetes RBAC security audits are standard quarterly security hygiene. Security engineers regularly review ClusterRoleBindings and RoleBindings for over-permissioned service accounts — especially cluster-admin bindings — and replace them with minimum necessary permissions. This is exactly the kind of work Rancher's security panel enables.

## Goal

Audit all RBAC configuration in the cluster. Find and remediate all service accounts with excessive permissions. Apply least-privilege replacements.

## What Success Looks Like

All 4 injected RBAC violations must be remediated:
1. `dev-all-access` ClusterRoleBinding removed or no longer bound to cluster-admin
2. `wildcard-staging-role` Role in staging no longer uses wildcards for verbs/resources
3. `monitoring-cluster-admin` ClusterRoleBinding removed or no longer bound to cluster-admin
4. `ci-elevated-access` RoleBinding in staging no longer bound to cluster-admin

## Verification Strategy

Each remediation is 25 points:
- **Criterion 1** (25 pts): `dev-all-access` ClusterRoleBinding no longer grants cluster-admin
- **Criterion 2** (25 pts): `wildcard-staging-role` Role no longer has wildcard (*) resources
- **Criterion 3** (25 pts): `monitoring-cluster-admin` ClusterRoleBinding no longer grants cluster-admin
- **Criterion 4** (25 pts): `ci-elevated-access` RoleBinding no longer grants cluster-admin

**Pass threshold**: 70/100 points (3 of 4 violations fixed)

## Scoring Strategy Enumeration (Anti-Gaming Check)

| Strategy | C1 | C2 | C3 | C4 | Score | Pass? |
|----------|----|----|----|----|----|-------|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | No |
| Delete all RBAC objects indiscriminately | 25 | 25 | 25 | 25 | 100 | Yes |

Note: Bulk-deleting everything is a valid approach — this task tests discovery of violations, not prevention of over-correction. The scoring correctly rewards fixing violations regardless of method.

## Environment Details

- Rancher URL: https://localhost
- Credentials: admin / Admin12345678!
- Affected namespaces: development, staging, monitoring
- Cluster: local (embedded K3s)

## Schema Reference

```bash
# List all ClusterRoleBindings
docker exec rancher kubectl get clusterrolebindings -o wide

# List all RoleBindings in staging
docker exec rancher kubectl get rolebindings -n staging -o wide

# Describe a specific ClusterRoleBinding
docker exec rancher kubectl describe clusterrolebinding dev-all-access

# List all Roles in staging
docker exec rancher kubectl get roles -n staging -o yaml
```

## Edge Cases

- The agent may delete the binding/role OR modify it to use appropriate permissions
- Creating scoped replacement Roles/RoleBindings is acceptable (and professionally correct)
- The verifier checks that cluster-admin is no longer granted — it doesn't require the original binding to be deleted as long as it no longer grants cluster-admin
