# Task: platform_capacity_governance_implementation

## Overview

A fintech SaaS platform's `payments-prod` Kubernetes namespace hosts 4 critical payment processing workloads but has no capacity governance controls. Following resource-exhaustion incidents, the platform team has issued a mandatory governance specification. As the Platform Engineer, you must implement all required controls exactly as specified.

**Difficulty**: Very Hard
**Domain**: Platform Engineering / Kubernetes Capacity Management
**Primary Occupation**: Computer Systems Engineers/Architects

## Professional Context

ResourceQuotas, LimitRanges, HPAs, and PodDisruptionBudgets are standard production-grade Kubernetes controls required by any mature platform team. Finance and regulated industries require these controls for compliance and availability guarantees. Implementing them from a specification document (rather than being given the kubectl commands) is the core engineering skill tested here.

## Task Description

A governance specification document is available at `/home/ga/Desktop/capacity_governance_spec.md`. It defines exact resource names, values, and target workloads. The agent must:

1. Read the specification document
2. Implement each of the 4 controls in the `payments-prod` namespace
3. Use the correct resource names, values, and targets as specified

## Required Controls

| Control | Resource Name | Key Parameters |
|---------|--------------|----------------|
| ResourceQuota | `payments-quota` | limits.cpu=8, limits.memory=16Gi, pods=20, services=10 |
| LimitRange | `payments-limits` | Container default CPU=500m, default memory=512Mi |
| HorizontalPodAutoscaler | `transaction-processor-hpa` | target=transaction-processor, min=2, max=10, CPU=70% |
| PodDisruptionBudget | `payment-gateway-pdb` | target=payment-gateway, minAvailable=1 |

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | `payments-quota` ResourceQuota with cpu=8, mem=16Gi, pods=20, services=10 |
| C2 | 25 | `payments-limits` LimitRange with Container default cpu=500m, memory=512Mi |
| C3 | 25 | `transaction-processor-hpa` HPA: target=transaction-processor, min=2, max=10, cpu=70% |
| C4 | 25 | `payment-gateway-pdb` PDB: minAvailable=1 |

**Pass threshold**: 70 points (any 3 of 4 criteria)

## Why This Is Hard

- The specification provides the business intent, not kubectl commands — the agent must translate to Kubernetes manifests
- HPA `autoscaling/v2` API requires a structured `metrics` array (not the deprecated v1 annotation)
- LimitRange requires specifying `type: Container` with both `default` and `defaultRequest` sections
- All resource names are prescriptive — wrong names get score=0 on that criterion
- ResourceQuota distinguishes between `requests.*` and `limits.*` — the verifier checks `limits.cpu` and `limits.memory`
- Values must be exact: 8 cores CPU, 16Gi memory, 20 pods, 10 services

## Namespace

`payments-prod`

## Workloads

| Workload | Replicas | Purpose |
|----------|---------|---------|
| payment-gateway | 2 | HTTPS payment request handling |
| transaction-processor | 3 | Core payment processing |
| fraud-detector | 1 | ML-based fraud scoring |
| audit-logger | 2 | Regulatory audit log writer |

## Verification Approach

The `export_result.sh` script queries:
- `kubectl get resourcequota payments-quota -o jsonpath` — reads limits.cpu, limits.memory, pods, services
- `kubectl get limitrange payments-limits -o jsonpath` — reads Container default.cpu and default.memory
- `kubectl get hpa transaction-processor-hpa -o json` — parses minReplicas, maxReplicas, and CPU target (via Python for v2 metrics support)
- `kubectl get pdb payment-gateway-pdb -o jsonpath` — reads minAvailable

Results are written to `/tmp/platform_capacity_governance_implementation_result.json`. The `verifier.py` applies normalized comparisons (e.g., `8` == `8000m`) and binary scoring per criterion.

## Login Credentials

- **URL**: https://localhost
- **Username**: admin
- **Password**: Admin12345678!

## Anti-Gaming Notes

- Wrong namespace gives score=0
- Wrong resource names give score=0 for that criterion
- HPA with wrong target (`scaleTargetRef.name != "transaction-processor"`) gives C3=0
- Memory units are normalized: `16Gi` and `16384Mi` both pass; `16G` does not (binary prefix required)
- Score is binary per criterion — no partial credit within a criterion
