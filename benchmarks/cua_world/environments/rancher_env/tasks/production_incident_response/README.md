# Task: production_incident_response

## Overview

A Platform/SRE engineer is paged during a production incident. The `ecommerce` namespace is completely down — four microservices are failing in different ways. The engineer must independently diagnose each failure and restore all services to healthy running state.

This task reflects real SRE work: on-call incident response where multiple independent failures occur simultaneously in a microservices deployment.

## Professional Context

**Occupation**: Site Reliability Engineer / Platform Engineer
**Why realistic**: SREs routinely respond to production incidents where multiple services fail simultaneously for different root causes. Rancher is used as the operations console to investigate pod states, service configurations, ConfigMaps, and resource allocations — exactly the workflow tested here.

## Goal

Restore all four microservices in the `ecommerce` namespace to a Running state:
- All pods should be in `Running` phase
- `web-frontend` Service must have active endpoints
- All deployments must be healthy

## What Success Looks Like

1. `api-gateway` deployment has ≥1 Running pod
2. `web-frontend` Service has ≥1 endpoint address (pod labels match Service selector)
3. `cache-layer` ConfigMap has `REDIS_PORT=6379` (not 6380)
4. `batch-processor` deployment has ≥1 Running pod

## Verification Strategy

The verifier checks each criterion independently (25 points each):
- **Criterion 1** (25 pts): api-gateway pods in Running state
- **Criterion 2** (25 pts): web-frontend Service has endpoints (selector matches pods)
- **Criterion 3** (25 pts): cache-layer ConfigMap REDIS_PORT corrected to 6379
- **Criterion 4** (25 pts): batch-processor pods in Running state

**Pass threshold**: 70/100 points (3 of 4 fixes)

## Scoring Strategy Enumeration (Anti-Gaming Check)

| Strategy | C1 | C2 | C3 | C4 | Score | Pass? |
|----------|----|----|----|----|----|-------|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | No |
| Fix only api-gateway | 25 | 0 | 0 | 0 | 25 | No |
| Fix 3 of 4 | 25 | 25 | 25 | 0 | 75 | Yes |
| Fix all | 25 | 25 | 25 | 25 | 100 | Yes |

## Environment Details

- Rancher URL: https://localhost
- Credentials: admin / Admin12345678!
- Namespace: ecommerce (created by setup script)
- Cluster: local (embedded K3s)

## Schema Reference

```bash
# Check pod states
docker exec rancher kubectl get pods -n ecommerce

# Check service endpoints
docker exec rancher kubectl get endpoints -n ecommerce

# Check configmap
docker exec rancher kubectl get configmap cache-config -n ecommerce -o yaml

# Check deployment resource requests
docker exec rancher kubectl get deployment batch-processor -n ecommerce -o yaml
```

## Edge Cases

- The agent may fix issues via Rancher UI or via kubectl terminal access
- The agent may add the `ecommerce` namespace to Rancher's cluster explorer view
- Fixing Service selector: acceptable to change either the selector OR the pod labels
- Fixing batch-processor: acceptable to reduce memory request to any value ≤ 4Gi
