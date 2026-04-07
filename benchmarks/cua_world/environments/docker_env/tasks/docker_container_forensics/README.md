# Task: Docker Container Forensics & Remediation

## Domain Context

Information Security Engineers and DevSecOps professionals routinely audit running containers for security policy violations. Real incidents involve discovering misconfigured containers in production, understanding their blast radius, and deploying hardened replacements—all without destroying evidence.

## Environment State

Three production containers are running:
- **acme-webapp** — serves the AcmeCorp web application (nginx:1.24-alpine)
- **acme-gateway** — API gateway service (python:3.11-slim)
- **acme-monitor** — system monitoring agent (alpine:3.18)

A security scan has flagged all three with policy violations. The exact nature of the violations is not disclosed—you must investigate each container using `docker inspect`, `docker exec`, `docker logs`, and any other forensic methods.

## Goal

The end state should have:
1. **Three hardened replacement containers running**: `acme-webapp-fixed`, `acme-gateway-fixed`, `acme-monitor-fixed` — each preserving the original service's core functionality but with the security issue resolved
2. **Original vulnerable containers stopped** (not necessarily removed)
3. **Incident report** at `~/Desktop/incident_report.txt` documenting:
   - What security issue was found in each container
   - What the impact would be if exploited
   - What you did to fix it

## Success Criteria

| Criterion | Points |
|-----------|--------|
| acme-webapp-fixed is running without excessive Linux capabilities | 25 |
| acme-gateway-fixed is running without hardcoded secrets in environment | 25 |
| acme-monitor-fixed is running without dangerous host filesystem bind mounts | 25 |
| Original containers (all 3) are stopped | 10 |
| Incident report exists and documents all 3 findings | 15 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Verification Strategy

The verifier checks:
1. `docker inspect acme-webapp-fixed` — HostConfig.CapAdd is null or empty (no extra caps)
2. `docker inspect acme-gateway-fixed` — Config.Env does not contain any of the hardcoded secrets
3. `docker inspect acme-monitor-fixed` — HostConfig.Binds does not mount /etc from host
4. `docker inspect acme-webapp acme-gateway acme-monitor` — all have State.Status = "exited"
5. `~/Desktop/incident_report.txt` exists, modified after task start, and mentions all three container names

## Notes

- Evidence must be preserved: document findings BEFORE stopping original containers
- The fixed containers must actually run (State.Status = "running")
- You may create fixed containers using `docker run` directly or by writing and building a custom image
- Secrets should be replaced with placeholder env vars (e.g., `DATABASE_PASSWORD=<REDACTED>`) or removed entirely; the grader does not require actual working credentials
