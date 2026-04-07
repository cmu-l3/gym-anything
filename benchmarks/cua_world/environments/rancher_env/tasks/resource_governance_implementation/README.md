# Resource Governance Implementation

**Difficulty**: Very Hard
**Timeout**: 900 seconds | **Max Steps**: 100
**Occupation Context**: Platform Engineer / Site Reliability Engineer

## Task Description

The fintech platform's Kubernetes namespaces lack resource governance, posing risks of resource exhaustion and compliance violations. A governance compliance specification has been placed on the desktop at `/home/ga/Desktop/resource_governance_spec.yaml`. Your job is to implement ResourceQuota and LimitRange objects across all namespaces exactly as specified.

## What Makes This Hard

- Agent must read and parse a multi-section YAML spec file from the desktop
- 3 namespaces each with different quota tiers (production/staging/development)
- fintech-dev intentionally has NO ResourceQuota (agent must recognize this is by design, not an omission)
- Values must match exactly — wrong CPU/memory values fail verification
- Agent must choose between Rancher UI and kubectl; spec values require translation to k8s YAML

## Scoring (100 pts total, pass threshold: 70)

| Criterion | Points | Pass Condition |
|-----------|--------|----------------|
| C1: fintech-prod ResourceQuota | 25 | All 7 hard limits match spec (cpu, memory, pods, services, pvcs) |
| C2: fintech-staging ResourceQuota | 25 | All 7 hard limits match spec |
| C3: fintech-prod LimitRange | 25 | Container type: default, defaultRequest, max, min all match spec |
| C4: fintech-staging + fintech-dev LimitRanges | 25 | Both namespaces have correct Container-type limits |

## Spec Summary (from `/home/ga/Desktop/resource_governance_spec.yaml`)

**fintech-prod** (tier: production):
- ResourceQuota: requests.cpu=16, requests.memory=32Gi, limits.cpu=32, limits.memory=64Gi, pods=50, services=20, pvcs=10
- LimitRange Container: default cpu=500m/mem=512Mi, defaultRequest cpu=250m/mem=256Mi, max cpu=4/mem=8Gi, min cpu=50m/mem=64Mi

**fintech-staging** (tier: staging):
- ResourceQuota: requests.cpu=8, requests.memory=16Gi, limits.cpu=16, limits.memory=32Gi, pods=30, services=15, pvcs=5
- LimitRange Container: default cpu=250m/mem=256Mi, defaultRequest cpu=100m/mem=128Mi, max cpu=2/mem=4Gi, min cpu=25m/mem=32Mi

**fintech-dev** (tier: development):
- ResourceQuota: NONE (developers need flexibility — per spec comment)
- LimitRange Container: default cpu=200m/mem=256Mi, defaultRequest cpu=100m/mem=128Mi, max cpu=1/mem=2Gi, min cpu=10m/mem=16Mi
