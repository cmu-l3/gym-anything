# Task: supply_chain_security_remediation

## Overview

The information security team has completed a container security audit of the software supply chain platform and identified 6 high-severity violations across 5 workloads in the `supply-chain` Kubernetes namespace. As the platform security engineer, you must read the audit report, identify which specific workloads contain each violation, and remediate all findings.

**Difficulty**: Very Hard
**Domain**: Platform Security Engineering / Container Security
**Primary Occupation**: Computer Systems Engineers/Architects (CIS Kubernetes Benchmark compliance)

## Professional Context

Container security compliance is a core responsibility of platform engineering teams at software companies operating regulated environments. Real security audits produce findings by vulnerability category, not by specific resource name — engineers must correlate findings to workloads through cluster inspection. This task mirrors that professional workflow.

## Task Description

A security audit report is available at `/home/ga/Desktop/security_audit_report.txt`. The report identifies:

- **FINDING-001**: Privileged container + missing seccomp profile (Infrastructure tier)
- **FINDING-002**: Host Docker socket mount + root user execution (Security tier)
- **FINDING-003**: SYS_ADMIN Linux capability (Build tier)
- **FINDING-004**: Excessive RBAC — ServiceAccount bound to cluster-admin (Orchestration tier)
- **FINDING-005**: Missing resource limits (Compliance tier)
- **FINDING-006**: Additional instance of FINDING-001 (same Infrastructure-tier workload)

The agent must:
1. Read the audit report to understand the violation categories and affected tiers
2. Inspect all workloads in the `supply-chain` namespace to identify which workloads correspond to each finding
3. Remediate each finding by modifying the appropriate Kubernetes resources

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | `registry-proxy`: `privileged` removed, `seccompProfile.type=RuntimeDefault`, resource limits set |
| C2 | 25 | `artifact-scanner`: docker.sock `hostPath` removed, `runAsNonRoot=true` or `runAsUser>0` |
| C3 | 25 | `build-agent`: `SYS_ADMIN` removed from `capabilities.add` |
| C4 | 25 | `deploy-controller`: `ClusterRoleBinding` to `cluster-admin` for its ServiceAccount removed |

**Pass threshold**: 70 points (any 3 of 4 criteria)

## Why This Is Hard

- The audit report describes violation **categories** and affected **tiers**, not specific Kubernetes resource names
- The agent must inspect all 5 workloads and correlate each finding to the right resource
- Fixes span different Kubernetes resource types: Deployment securityContext, hostPath volumes, capabilities, ClusterRoleBindings
- Some workloads have multiple violations; others are clean — the agent must not over-correct
- RBAC fix requires understanding both the Deployment's serviceAccountName and the ClusterRoleBinding structure

## Namespace

`supply-chain`

## Workloads Deployed at Setup

| Workload | Tier | Violation(s) |
|----------|------|-------------|
| registry-proxy | Infrastructure | privileged=true, no seccompProfile, no resource limits |
| artifact-scanner | Security | docker.sock hostPath, runAsUser=0 (root) |
| build-agent | Build | SYS_ADMIN capability |
| deploy-controller | Orchestration | ServiceAccount bound to cluster-admin |
| sbom-generator | Compliance | No resource limits |

## Verification Approach

The `export_result.sh` script queries each workload's security configuration via `kubectl get deployment -o jsonpath` and writes a structured JSON to `/tmp/supply_chain_security_remediation_result.json`. The `verifier.py` reads this file and applies binary scoring per criterion.

## Login Credentials

- **URL**: https://localhost
- **Username**: admin
- **Password**: Admin12345678!

## Anti-Gaming Notes

- Deleting the namespace or deployments gives score=0 (cannot verify against missing resources)
- The cluster-admin CRB check scans ALL ClusterRoleBindings for the SA, not just the original name
- Score is binary per criterion — no partial credit within a criterion
