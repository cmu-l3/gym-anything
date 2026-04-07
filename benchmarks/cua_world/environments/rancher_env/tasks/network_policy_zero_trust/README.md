# Network Policy Zero Trust

**Difficulty**: Very Hard
**Timeout**: 900 seconds | **Max Steps**: 100
**Occupation Context**: Information Security Engineer / Platform Engineer

## Task Description

A security audit has flagged the online-banking namespace for having no NetworkPolicies, meaning all pods communicate freely — a PCI-DSS violation. A network topology specification is on the desktop at `/home/ga/Desktop/network_topology_spec.md`. Implement zero-trust NetworkPolicies that enforce the documented traffic flows.

## What Makes This Hard

- Agent must read a network topology spec and translate it into 6 Kubernetes NetworkPolicy objects
- Default deny-all is the prerequisite; without it, the other policies don't provide security
- Namespace selectors require correct label knowledge (`kubernetes.io/metadata.name=ingress-nginx`)
- Port specifications must be explicit (port 5432 for DB, 8080/8081/8082 for services)
- Common error: forgetting DNS egress causes app-level failures even if the policy is structurally correct

## Scoring (100 pts total, pass threshold: 70)

| Criterion | Points | Pass Condition |
|-----------|--------|----------------|
| C1: Default deny-all | 25 | `default-deny-all` policy: empty podSelector, policyTypes=[Ingress,Egress], no allow rules |
| C2: frontend-app policy | 25 | Ingress from ingress-nginx namespace + Egress to api-gateway |
| C3: api-gateway policy | 25 | Ingress from frontend-app + Egress to auth-service AND account-service |
| C4: account-db policy | 25 | Ingress ONLY from account-service on port 5432 |

## Architecture

```
[Internet] → ingress-nginx → frontend-app → api-gateway → auth-service
                                                          → account-service → account-db
```

## Anti-Gaming Analysis

| Strategy | C1 | C2 | C3 | C4 | Score | Pass? |
|----------|----|----|----|-----|-------|-------|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | No |
| Allow-all (no deny) | 0 | 0 | 0 | 0 | 0 | No |
| Correct implementation | 25 | 25 | 25 | 25 | 100 | Yes |
| Missing DB port 5432 | 25 | 25 | 25 | 0 | 75 | Yes |

A default-allow (no deny-all) approach scores 0 on C1, blocking any gaming via permissive policies.
