# Task: statefulset_database_cluster_restoration

## Overview

A healthcare data platform's PostgreSQL StatefulSet cluster in the `data-platform` namespace has degraded after a failed storage migration. Four misconfiguration failures were injected across the StatefulSet, Secret, and Service resources. As the Platform Engineer on-call, you must read the runbook, diagnose all 4 failures, and restore the cluster.

**Difficulty**: Very Hard
**Domain**: Database Platform Engineering / Kubernetes StatefulSets
**Primary Occupation**: Computer Systems Engineers/Architects

## Professional Context

StatefulSet-based database clusters are the standard approach for running stateful workloads on Kubernetes. PostgreSQL clusters require precise configuration across image versions, environment variable naming (which the postgres Docker image reads directly), resource requests for scheduler placement, and headless Services for pod-to-pod DNS. Failures in any one of these cause subtle, hard-to-diagnose degradation.

## Task Description

A runbook is available at `/home/ga/Desktop/database_cluster_runbook.md`. It describes the intended configuration for the `postgres-cluster` StatefulSet and its dependencies. The agent must:

1. Read the runbook to understand the required configuration
2. Inspect the `data-platform` namespace to find the 4 discrepancies
3. Fix each failure using `kubectl` or the Rancher UI

## Injected Failures

| # | Resource | Failure | Fix |
|---|----------|---------|-----|
| 1 | `postgres-cluster` StatefulSet | Uses `postgres:14-alpine` instead of `postgres:15-alpine` | Update container image to `postgres:15-alpine` |
| 2 | `postgres-credentials` Secret | Key is `DB_PASSWORD` instead of `POSTGRES_PASSWORD` | Add/rename key to `POSTGRES_PASSWORD` |
| 3 | `postgres-cluster` StatefulSet | Container has no `resources.requests` (cpu/memory missing) | Add `resources.requests.cpu` and `resources.requests.memory` |
| 4 | `postgres-cluster` Service | Not headless (has ClusterIP instead of `clusterIP: None`) | Set `clusterIP: None` to make headless |

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 25 | StatefulSet `postgres-cluster` uses image `postgres:15-alpine` |
| C2 | 25 | Secret `postgres-credentials` has key `POSTGRES_PASSWORD` |
| C3 | 25 | StatefulSet containers have both `cpu` and `memory` resource requests |
| C4 | 25 | Service `postgres-cluster` has `clusterIP: None` (headless) |

**Pass threshold**: 70 points (any 3 of 4 criteria)

## Why This Is Hard

- The runbook describes intended state without listing specific broken resources
- Failures span 3 different resource types (StatefulSet, Secret, Service)
- Secret key renaming requires understanding how the postgres Docker image reads environment variables — `POSTGRES_PASSWORD` is hardcoded into the image's entrypoint script
- Headless Services are not directly visible in the Rancher UI by default — agent must inspect the YAML
- Patching a StatefulSet's `spec.template` (image, resources) triggers a rolling restart of all pods
- `kubectl patch secret` requires careful handling of base64-encoded data keys

## Namespace

`data-platform`

## Resources

| Resource | Kind | Purpose |
|----------|------|---------|
| postgres-cluster | StatefulSet | 3-replica PostgreSQL cluster |
| postgres-credentials | Secret | Database credentials |
| postgres-cluster | Service | Headless service for StatefulSet DNS |
| postgres-cluster-read | Service | Read access endpoint |
| pgbouncer | Deployment | Connection pooler |
| postgres-exporter | Deployment | Prometheus metrics exporter |

## Verification Approach

The `export_result.sh` script queries:
- `kubectl get statefulset postgres-cluster -o jsonpath` — reads image, cpu/memory requests
- `kubectl get secret postgres-credentials -o jsonpath '{.data}'` — parses JSON to list keys (via Python)
- `kubectl get service postgres-cluster -o jsonpath '{.spec.clusterIP}'` — checks for `None`

Results are written to `/tmp/statefulset_database_cluster_restoration_result.json`. The `verifier.py` applies binary scoring per criterion.

## Login Credentials

- **URL**: https://localhost
- **Username**: admin
- **Password**: Admin12345678!

## Anti-Gaming Notes

- Deleting the namespace gives score=0
- Wrong target namespace gives score=0
- C1 accepts any image containing `postgres:15` and `alpine`
- C3 requires both cpu AND memory requests — either alone is insufficient
- C4 requires `clusterIP` to be exactly `None` (not empty, not a valid IP)
- Score is binary per criterion — no partial credit within a criterion
