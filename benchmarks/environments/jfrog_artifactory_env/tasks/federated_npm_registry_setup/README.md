# Task: federated_npm_registry_setup

## Summary
Build a complete npm package registry infrastructure (3 repos + user + group + permission) for an e-commerce company's frontend platform, including an internal private store, a proxied public mirror, and a unified virtual resolver with proper access controls.

## Occupation Context
- **Role**: Frontend Platform Engineer
- **Industry**: Retail / E-Commerce
- **Realistic scenario**: InfoSec mandated that all npm package consumption route through an internal Artifactory proxy for license scanning and supply-chain protection. The frontend platform engineer must stand up the full infrastructure before teams can migrate their `.npmrc` configs to point at the internal registry.

## Difficulty: very_hard
The task requires 7 coordinated operations across 4 admin sections:
1. Create local npm repo (`npm-internal`)
2. Create remote npm proxy repo (`npmjs-mirror`)
3. Create virtual npm repo (`npm-all`) — references both above, so must be done last
4. Create user (`frontend-lead`) — must precede group membership assignment
5. Create group (`frontend-developers`) — must precede permission and membership
6. Add `frontend-lead` to `frontend-developers` (group membership edit)
7. Create permission target (`frontend-npm-perms`) — references group + repo

## Verification Criteria (100 pts total, pass ≥ 60)
| # | Criterion | Points |
|---|-----------|--------|
| 1 | `npm-internal` exists as LOCAL npm repository | 20 |
| 2 | `npmjs-mirror` exists as REMOTE npm repo pointing to registry.npmjs.org | 15 |
| 3 | `npm-all` exists as VIRTUAL npm repo including both npm-internal and npmjs-mirror | 15 |
| 4 | `frontend-lead` user exists, non-admin, email matches globalretail.com | 15 |
| 5 | `frontend-developers` group exists and `frontend-lead` is a member | 15 |
| 6 | `frontend-npm-perms` grants `frontend-developers` Deploy+Read on `npm-internal` | 20 |

## Setup Behavior
`setup_task.sh` deletes `npm-all`, `npm-internal`, `npmjs-mirror`, `frontend-npm-perms`, `frontend-lead`, `frontend-developers` (in dependency order), then navigates Firefox to the Repositories admin page.

## Do-Nothing Score: 0
All 7 target entities are deleted before the agent starts.
