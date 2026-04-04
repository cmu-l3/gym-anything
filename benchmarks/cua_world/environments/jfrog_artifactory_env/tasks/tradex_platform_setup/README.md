# Task: tradex_platform_setup

## Summary
Complete the full Artifactory onboarding for a new capital markets application project ("TradeX Platform"): create 2 repositories, a team group, a richly-privileged permission target covering both repos, generate a CI/CD access token, and upload the project's first dependency artifact.

## Occupation Context
- **Role**: Artifact Repository Administrator
- **Industry**: Capital Markets / Financial Services
- **Realistic scenario**: A new trading platform project requires its full Artifactory footprint provisioned before sprint 1. The team lead has provided a 6-item checklist. All 6 must be done before the Monday kickoff — partial completion means the build pipeline cannot run.

## Difficulty: very_hard
The task requires 6 coordinated actions across all Artifactory admin sections, with an unusual permission that covers TWO repositories simultaneously and uses 4 privilege types (Admin, Deploy, Annotate, Read):
1. Create `tradex-artifacts` (LOCAL Generic) — Repositories
2. Create `tradex-maven-releases` (LOCAL Maven) — Repositories
3. Create `tradex-developers` group — Security → Groups
4. Create `tradex-dev-perms` — Security → Permissions (must reference both repos, 4 privilege flags)
5. Generate access token for admin — Security → Access Tokens
6. Upload `commons-io-2.15.1.jar` to `tradex-artifacts` — Artifacts browser

The permission step is the hardest: most tasks grant one privilege on one repo; this task requires selecting two repos and four privileges simultaneously in the permission editor.

## Real Data
The upload artifact is `commons-io-2.15.1.jar` from Apache Commons IO 2.15.1, staged to `/home/ga/Desktop/` by `setup_task.sh` from either the pre-cached file at `/home/ga/artifacts/commons-io/` or downloaded from Maven Central (`repo1.maven.org`). This is a real Apache Commons release artifact, not synthetic data.

## Verification Criteria (100 pts total, pass ≥ 60)
| # | Criterion | Points |
|---|-----------|--------|
| 1 | `tradex-artifacts` exists as LOCAL Generic repository | 15 |
| 2 | `tradex-maven-releases` exists as LOCAL Maven repository | 15 |
| 3 | `tradex-developers` group exists | 15 |
| 4 | `tradex-dev-perms` grants `tradex-developers` Admin+Deploy+Annotate+Read on **both** repos | 20 |
| 5 | Access token with description "TradeX CI/CD production token" exists | 15 |
| 6 | `commons-io-2.15.1.jar` artifact uploaded to `tradex-artifacts` repository | 20 |

## Setup Behavior
`setup_task.sh`:
- Deletes `tradex-dev-perms`, `tradex-artifacts`, `tradex-maven-releases`, `tradex-developers`
- Revokes any existing "TradeX CI/CD production token" access tokens
- Ensures `commons-io-2.15.1.jar` is present on the Desktop (copies from cache or downloads from Maven Central)
- Navigates Firefox to the Repositories page

## Do-Nothing Score: 0
All entities deleted + artifact removed from repo before agent starts.
