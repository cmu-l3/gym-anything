# StatefulSet Database Recovery

**Difficulty**: Very Hard
**Timeout**: 900 seconds | **Max Steps**: 100
**Occupation Context**: Site Reliability Engineer / Database Administrator

## Task Description

A production PostgreSQL StatefulSet (`postgres-primary`) in the `data-platform` namespace has been broken after a failed migration. The database pods are not running and the data platform is unavailable. Diagnose all failures and restore the StatefulSet to a healthy running state.

## What Makes This Hard

- 4 failures are injected simultaneously — agent must diagnose each independently
- No hints about which specific components are broken or how many failures exist
- PVC StorageClass can only be changed by deleting the PVC/StatefulSet (cannot be patched in-place)
- StatefulSet recreation requires knowing the correct configuration
- The correct Secret exists in the cluster but with a different name than what the StatefulSet references

## Scoring (100 pts total, pass threshold: 70)

| Criterion | Points | Pass Condition |
|-----------|--------|----------------|
| C1: Pods Running | 25 | ≥1 postgres-primary pod in Running state |
| C2: StorageClass fixed | 25 | PVC uses `local-path` StorageClass (not `premium-ssd`) |
| C3: Secret reference fixed | 25 | StatefulSet references `postgres-credentials` (not `postgres-db-secret`) |
| C4: Memory request fixed | 25 | Memory request ≤ 4Gi (was injected as 32Gi) |

## Injected Failures

1. **StorageClass**: PVC volumeClaimTemplate uses `premium-ssd` which doesn't exist (cluster only has `local-path`)
2. **Volume mount path**: Container mounts at `/var/lib/psql` instead of `/var/lib/postgresql/data`
3. **Memory request**: Container requests `32Gi` memory — exceeds node capacity, causes Pending
4. **Secret reference**: Env vars reference `postgres-db-secret` which doesn't exist (correct: `postgres-credentials`)

## Recovery Strategy

The canonical approach:
1. `kubectl describe statefulset postgres-primary -n data-platform` — identify all config errors
2. Delete the StatefulSet and its PVCs (`kubectl delete statefulset/pvc ...`)
3. Recreate with corrected YAML: `local-path` StorageClass, correct mount path, `512Mi` memory, `postgres-credentials` secret
4. Wait for pod to reach Running state

## Anti-Gaming Analysis

| Strategy | C1 | C2 | C3 | C4 | Score | Pass? |
|----------|----|----|----|----|-------|-------|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | No |
| Fix only memory | 0 | 0 | 0 | 25 | 25 | No |
| Fix SC+Secret+Memory (not mount path) | 0 | 25 | 25 | 25 | 75 | **Yes** |
| Fix all 4 | 25 | 25 | 25 | 25 | 100 | Yes |

Note: Fixing C2+C3+C4 without fixing the mount path (F2) means pods still won't start (C1=0), but
3 direct fixes earn 75 pts — a passing score. This is intentional design: fixing 3 real root causes
demonstrates deep diagnosis even if the mount path fix was missed.
