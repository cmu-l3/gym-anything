# Task: cluster_rbac_audit_and_remediation

## Overview

A cloud-native SaaS company's Kubernetes cluster has accumulated 4 RBAC security violations during rapid developer onboarding across 3 namespaces. An internal security review document describes the violations by category and affected team — not by specific resource names. As the Kubernetes Security Engineer, you must identify the specific misconfigurations and remediate all 4 findings.

**Difficulty**: Very Hard
**Domain**: Kubernetes Security Engineering / RBAC
**Primary Occupation**: Computer Systems Engineers/Architects

## Professional Context

RBAC misconfiguration is among the most common Kubernetes security issues in production clusters. Real security reviews produce findings by policy category (excessive scope, wildcard permissions, cluster-admin abuse) and affected team — engineers must correlate these to specific Roles, RoleBindings, and ClusterRoleBindings by inspecting the cluster. This task mirrors that professional workflow.

## Task Description

A security review document is at `/home/ga/Desktop/rbac_review_findings.md`. It describes 4 violations across namespaces `dev-team`, `qa-team`, and `platform-ops`. The agent must:

1. Read the review document to understand which teams and violation categories are affected
2. Inspect all RBAC resources across the 3 namespaces to identify specific resources
3. Remediate each finding using `kubectl` or the Rancher UI

## Injected Violations

| Finding | Namespace | Violation | Fix |
|---------|-----------|-----------|-----|
| A | `dev-team` | `ci-runner` SA has ClusterRoleBinding to `edit` ClusterRole (cluster-wide scope) | Delete the ClusterRoleBinding |
| B | `qa-team` | `qa-tester` Role has wildcard verbs (`*`) on `pods` resource | Replace `*` with specific verbs like `["get", "list", "watch"]` |
| C | `platform-ops` | `ops-agent` SA is bound to `cluster-admin` via ClusterRoleBinding | Delete the ClusterRoleBinding |
| D | `dev-team` | Namespace missing `pod-security.kubernetes.io/enforce: restricted` label | Add the label to `dev-team` namespace |

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | No ClusterRoleBinding binds `ci-runner` (dev-team) to `edit` ClusterRole |
| C2 | 25 | `qa-tester` Role in `qa-team` has no wildcard verbs on `pods` (Role must still exist) |
| C3 | 25 | No ClusterRoleBinding binds `ops-agent` (platform-ops) to `cluster-admin` |
| C4 | 25 | `dev-team` namespace has label `pod-security.kubernetes.io/enforce=restricted` |

**Pass threshold**: 70 points (any 3 of 4 criteria)

## Why This Is Hard

- The review document describes violations by **team** and **category**, not resource names — agent must identify `ci-runner-edit-crb` and `ops-agent-admin-crb` by scanning all ClusterRoleBindings
- RBAC resources span 3 namespaces plus the cluster level — inspecting them requires knowing where to look
- C2 requires modifying (not deleting) the `qa-tester` Role — deleting it gives C2=0
- C4 requires labeling the namespace — a subtle operation not shown in the default Rancher UI workflow
- Finding-A and Finding-C look similar but affect different namespaces and different ClusterRoles

## Namespaces

- `dev-team` — Development team namespace (has violations A and D)
- `qa-team` — QA team namespace (has violation B)
- `platform-ops` — Platform operations namespace (has violation C)

## Workloads

| Workload | Namespace | ServiceAccount |
|----------|-----------|----------------|
| api-dev | dev-team | ci-runner |
| test-runner | qa-team | qa-automation |
| ops-controller | platform-ops | ops-agent |

## Verification Approach

The `export_result.sh` script queries:
- All ClusterRoleBindings via `kubectl get clusterrolebinding -o json` — uses Python to scan for ci-runner→edit and ops-agent→cluster-admin bindings
- `kubectl get role qa-tester -n qa-team -o json` — uses Python to check if any rule on pods has `*` in verbs
- `kubectl get namespace dev-team -o jsonpath '{.metadata.labels.pod-security.kubernetes.io/enforce}'`

Results are written to `/tmp/cluster_rbac_audit_and_remediation_result.json`. The `verifier.py` applies binary scoring per criterion.

## Login Credentials

- **URL**: https://localhost
- **Username**: admin
- **Password**: Admin12345678!

## Anti-Gaming Notes

- Wrong target namespaces gives score=0
- Deleting all namespaces gives score=0
- C2 requires `qa-tester` Role to still exist — deleting it scores 0 on C2
- C1 and C3 check ALL ClusterRoleBindings (not just the original name) — renaming the CRB doesn't help
- Score is binary per criterion — no partial credit within a criterion
