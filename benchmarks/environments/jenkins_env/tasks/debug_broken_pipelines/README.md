# Debug Broken Pipelines

## Task Overview

**Difficulty**: Very Hard
**Occupation Context**: Software QA Analysts and Testers / DevOps Engineers — diagnosing CI/CD pipeline failures is a core daily workflow: reading console output, tracing build errors to their root cause, and applying targeted fixes.

## Scenario

A development team has three failing CI pipelines that have been broken since a recent infrastructure migration. The pipelines block every developer's ability to merge and ship code. As the on-call DevOps engineer, you must triage each failure independently and restore normal CI operation.

## Goal

Fix all three pipelines so they build successfully. Each pipeline has a **different** type of defect — there is no single fix that solves all three.

- **pipeline 1**: `payment-service-ci`
- **pipeline 2**: `user-auth-service`
- **pipeline 3**: `inventory-api-build`

You will need to examine each job's build console output to understand what went wrong before attempting a fix.

## What Makes This Hard

- The agent is not told what the bug is — it must read console logs and diagnose independently.
- Each of the three pipelines has a structurally different type of failure (platform mismatch, credentials misconfiguration, missing environment configuration).
- Fixing one pipeline does not help fix the others.
- The agent must successfully re-trigger and verify each fix.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `payment-service-ci` last build is SUCCESS | 30 |
| `user-auth-service` last build is SUCCESS | 30 |
| `inventory-api-build` last build is SUCCESS | 30 |
| All three pipelines pass (bonus) | 10 |
| **Total** | **100** |

Pass threshold: **60 points** (at least 2 of 3 pipelines fixed and verified).

## Verification Strategy

1. `export_result.sh` queries the Jenkins REST API for the last build result of each job.
2. It also records whether a new build was triggered after the initial failing build.
3. `verifier.py` awards points per job where `lastBuild.result == 'SUCCESS'` and build number exceeds the initial baseline.

## Credential Reference

The Jenkins credential store contains `github-access-token` (username/password). Any pipeline that needs to access GitHub should reference this credential ID.

## Jenkins Access

- URL: http://localhost:8080
- Login: admin / Admin123!
