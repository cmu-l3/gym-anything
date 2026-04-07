# Task: microservice_mesh_connectivity_restoration

## Overview

A botched Kubernetes namespace migration has broken the connectivity between 5 microservices in the `ecommerce-platform` namespace. As the SRE on-call, you must read the architecture reference document, diagnose all 5 failures, and restore full connectivity — without being told which specific resources are broken.

**Difficulty**: Very Hard
**Domain**: Site Reliability Engineering / Kubernetes Networking
**Primary Occupation**: Computer Systems Engineers/Architects

## Professional Context

Microservice connectivity failures after namespace migrations are a common SRE incident type. The failures span multiple Kubernetes resource types: Service selectors, environment variables, ConfigMaps, NetworkPolicies, and Service port definitions. Real incidents require correlating a high-level architecture spec with the actual cluster state — exactly what this task simulates.

## Task Description

An architecture reference document is available at `/home/ga/Desktop/service_architecture.md`. It describes the intended service topology, expected FQDNs, ports, and connectivity requirements. The agent must:

1. Read the architecture document to understand the intended state
2. Inspect the `ecommerce-platform` namespace to discover all 5 discrepancies
3. Fix each failure using `kubectl` or the Rancher UI

## Injected Failures

| # | Resource | Failure | Fix |
|---|----------|---------|-----|
| 1 | `api-gateway` Service | Selector `app: api-gw` instead of `app: api-gateway` — no endpoints | Change selector to `app: api-gateway` |
| 2 | `product-service` Deployment | `INVENTORY_HOST` env var points to `ecommerce-staging` namespace | Update to `inventory-service.ecommerce-platform.svc.cluster.local` |
| 3 | `restrict-cart-egress` NetworkPolicy | Blocks port 3000 egress from cart-service to payment-service | Add port 3000 to egress rules or delete the policy |
| 4 | `payment-config` ConfigMap | `NOTIFICATION_HOST` uses `ecommerce-staging` namespace | Update to `notification-service.ecommerce-platform.svc.cluster.local` |
| 5 | `inventory-db` Service | Port is `5433` instead of `5432` | Change Service port to 5432 |

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 20 | `api-gateway` Service has >= 1 endpoint address |
| C2 | 20 | `product-service` `INVENTORY_HOST` env var contains `ecommerce-platform` FQDN |
| C3 | 20 | NetworkPolicy allows port 3000 egress from cart-service (no blocking rule on 3000) |
| C4 | 20 | `payment-config` ConfigMap `NOTIFICATION_HOST` contains `ecommerce-platform` |
| C5 | 20 | `inventory-db` Service port is 5432 |

**Pass threshold**: 70 points (any 4 of 5 criteria)

## Why This Is Hard

- The architecture document describes **what should be**, not what is broken
- Failures span 5 different Kubernetes resource types (Service, Deployment env, NetworkPolicy, ConfigMap, Service port)
- The agent must correlate each spec requirement with the actual cluster state
- NetworkPolicy analysis requires understanding egress rules and port lists
- Wrong-namespace FQDNs are subtle — services appear to exist but DNS resolves to nothing
- No error messages are shown by the infrastructure itself — the agent must actively probe

## Namespace

`ecommerce-platform`

## Workloads

| Workload | Purpose | Port |
|----------|---------|------|
| api-gateway | Frontend gateway | 80 |
| product-service | Product catalog | 8080 |
| cart-service | Shopping cart | 8081 |
| payment-service | Payment processing | 3000 |
| inventory-db | PostgreSQL database | 5432 |

## Verification Approach

The `export_result.sh` script queries:
- `kubectl get endpoints api-gateway` — counts endpoint addresses
- `kubectl get deployment product-service -o jsonpath` — extracts INVENTORY_HOST env var
- `kubectl get networkpolicy restrict-cart-egress -o json` — parses egress port rules via Python
- `kubectl get configmap payment-config -o jsonpath` — extracts NOTIFICATION_HOST value
- `kubectl get service inventory-db -o jsonpath` — reads the Service port

Results are written to `/tmp/microservice_mesh_connectivity_restoration_result.json`. The `verifier.py` reads this file and applies binary scoring per criterion.

## Login Credentials

- **URL**: https://localhost
- **Username**: admin
- **Password**: Admin12345678!

## Anti-Gaming Notes

- Deleting the namespace gives score=0 (all checks return defaults)
- Wrong target namespace gives score=0
- Deleting the NetworkPolicy counts as C3 PASS (no restriction = allowed)
- Score is binary per criterion — no partial credit within a criterion
- Pass requires fixing at least 4 of 5 failures
