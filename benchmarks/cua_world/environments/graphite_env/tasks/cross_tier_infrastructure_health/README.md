# cross_tier_infrastructure_health

**Difficulty:** very_hard
**Occupation:** DevOps Engineer
**Industry:** Cloud Infrastructure / E-commerce

## Task Description

A DevOps Engineer must build a four-tier infrastructure health dashboard so on-call engineers can quickly identify which system layer is responsible for production degradation.

The dashboard **"Infrastructure Health"** must contain 4 graphs:

| Graph Title | Metric(s) | Key Challenge |
|---|---|---|
| EC2 Compute Tier | EC2 instance CPU metrics | Standard |
| Database Tier | servers.rds_database.cpu.utilization | Standard |
| Load Balancer Tier | derivative(servers.load_balancer.requests.count) | Must use derivative() |
| Storage Tier | EC2 disk write bytes | Standard |

## Why This Is Hard

1. Creating four distinct, correctly titled graphs requires sustained accurate navigation
2. The Load Balancer graph **must** use `derivative()` — raw cumulative counters are not useful
3. The agent must know that request count is a cumulative counter that needs rate conversion
4. Four different metric namespaces must be discovered and correctly targeted

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Dashboard "Infrastructure Health" exists | 10 |
| Dashboard has ≥ 4 graphs | 10 |
| "EC2 Compute Tier" graph with EC2 CPU metric | 15 |
| "Database Tier" graph with RDS CPU metric | 15 |
| "Load Balancer Tier" graph with derivative(LB requests) | 20 |
| "Storage Tier" graph with disk write bytes | 15 |
| All 4 graph titles exactly correct | 15 |

## Verification

The verifier checks each graph's `target` array for the correct metric paths. The Load Balancer check specifically requires `derivative()` wrapping the LB metric.
