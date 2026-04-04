# Task: Project CI Environment Setup

## Domain Context

Software developers setting up CI/CD infrastructure for a new project routinely perform
this class of work: creating build jobs for each tier of the application stack, provisioning
secrets, configuring automated polling, and organising jobs into a dashboard view. This
task mirrors onboarding a real multi-tier project (backend + frontend) onto Jenkins.

Primary occupation: Software Developer (GDP contribution: $6.1 B USD)
Secondary occupation: Software QA / DevOps Engineer

## Goal

Bootstrap the complete Jenkins CI environment for **Project Alpha**. The environment must
contain:

1. **`alpha-backend-build`** — a Pipeline job that:
   - Clones `https://github.com/jenkinsci/pipeline-examples` (branch `master`)
   - Polls SCM for changes every 15 minutes using Jenkins hash-based scheduling (`H/15 * * * *`)

2. **`alpha-frontend-build`** — a job (any type) that:
   - Has a choice parameter named `NODE_VERSION` with options `16`, `18`, `20` (in that order)
   - Has a build discarder configured to keep only the last **7** builds

3. **`npm-registry-token`** — a **secret text** credential to store the NPM registry token

4. **`Project-Alpha CI`** — a list view containing both `alpha-backend-build` and
   `alpha-frontend-build`

The agent must discover all four requirements from the task description alone and configure
the environment without step-by-step UI guidance.

## Scoring (100 points)

| Criterion | Points |
|-----------|--------|
| `alpha-backend-build` exists as Pipeline with Git SCM pointing to correct URL | 25 |
| `alpha-backend-build` has H/15 SCM polling configured | 15 |
| `alpha-frontend-build` has `NODE_VERSION` choice param with values 16/18/20 | 25 |
| `alpha-frontend-build` build discarder keeps 7 builds | 15 |
| `npm-registry-token` credential exists as secret text | 10 |
| View `Project-Alpha CI` contains both jobs | 10 |
| **Total** | **100** |

Pass threshold: **60 points**.

## Verification Strategy

`export_result.sh` (runs inside the VM after the agent session):

- Fetches config XML for each job via `GET /job/<name>/config.xml`
- Parses XML with `xml.etree.ElementTree` to extract:
  - SCM class and remote URL for `alpha-backend-build`
  - SCM polling trigger spec
  - Parameter definitions and build discarder for `alpha-frontend-build`
- Queries `GET /credentials/store/system/domain/_/credential/npm-registry-token/api/json`
  to confirm the credential exists and its type
- Queries `GET /view/Project-Alpha%20CI/api/json` to list view membership
- Writes `/tmp/project_ci_environment_setup_result.json`

`verifier.py` reads the JSON via `copy_from_env` and awards partial credit where applicable.

## Starting State

Jenkins is running with the standard set of built-in jobs/views. There are **no**
pre-existing jobs named `alpha-backend-build` or `alpha-frontend-build`, no credential
`npm-registry-token`, and no view `Project-Alpha CI`. The agent starts with a clean slate.

## Edge Cases

- The agent may implement `alpha-backend-build` as a Scripted Pipeline, Declarative Pipeline,
  or Pipeline with SCM; all are valid as long as the Git URL and polling are present.
- `alpha-frontend-build` may be Freestyle, Pipeline, or any other type; only the parameter
  and build discarder are checked.
- Partial credit is awarded when a job/credential exists but configuration is incomplete.
- The NODE_VERSION choices must be present; order is checked for full credit.
