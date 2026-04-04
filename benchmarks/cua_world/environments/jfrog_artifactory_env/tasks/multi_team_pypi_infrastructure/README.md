# Task: multi_team_pypi_infrastructure

## Summary
Build isolated Python package infrastructure for two data teams (Data Science and ML Ops) in JFrog Artifactory: 2 local PyPI repos, 1 remote proxy, 1 virtual aggregator, 2 groups, and 2 permission targets — 8 entities across all major admin sections.

## Occupation Context
- **Role**: ML Infrastructure Engineer
- **Industry**: Data Analytics / Technology
- **Realistic scenario**: Two teams at a data analytics firm need isolated Python package stores to avoid version conflicts. Both need public PyPI access through a single cached proxy. The infra engineer must configure the full repository hierarchy and access control before teams can configure their pip clients.

## Difficulty: very_hard
The task requires 8 coordinated operations spanning every major Artifactory admin section:
1. Create `pypi-datascience` (LOCAL PyPI)
2. Create `pypi-mlops` (LOCAL PyPI)
3. Create `pypi-org-proxy` (REMOTE PyPI, external URL)
4. Create `pypi-all` (VIRTUAL PyPI, references all 3 above — must be last)
5. Create `data-scientists` group
6. Create `mlops-engineers` group
7. Create `ds-pypi-perms` (permission referencing data-scientists + pypi-datascience)
8. Create `mlops-pypi-perms` (permission referencing mlops-engineers + pypi-mlops)

The correct dependency order requires thought: virtual repo after all 3 source repos; permissions after both the groups and their target repos.

## Verification Criteria (100 pts total, pass ≥ 60)
| # | Criterion | Points |
|---|-----------|--------|
| 1 | `pypi-datascience` exists as LOCAL PyPI repository | 12 |
| 2 | `pypi-mlops` exists as LOCAL PyPI repository | 12 |
| 3 | `pypi-org-proxy` exists as REMOTE PyPI repo pointing to pypi.org | 14 |
| 4 | `pypi-all` exists as VIRTUAL PyPI repo including all 3 repos | 12 |
| 5 | `data-scientists` group exists | 10 |
| 6 | `ds-pypi-perms` grants `data-scientists` Deploy+Read on `pypi-datascience` | 15 |
| 7 | `mlops-engineers` group exists | 10 |
| 8 | `mlops-pypi-perms` grants `mlops-engineers` Deploy+Read on `pypi-mlops` | 15 |

## Setup Behavior
`setup_task.sh` deletes all 8 target entities in dependency order (virtual first, permissions before groups, groups last), then navigates Firefox to the Repositories page.

## Do-Nothing Score: 0
All 8 target entities are deleted before the agent starts.
