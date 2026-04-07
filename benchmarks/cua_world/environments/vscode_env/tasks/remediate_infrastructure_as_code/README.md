# Remediate Infrastructure as Code

## Scenario

A SaaS company's infrastructure code has been flagged by an external security
audit with 6 critical misconfigurations across Docker, Kubernetes, Terraform,
and nginx files.  The agent must remediate all findings before the company's
SOC 2 Type II certification renewal.

## Occupation

**Computer Systems Administrator** (SOC 15-1244.00) -- Cloud Computing / SaaS Industry

## Skills Tested

- Docker security best practices (non-root containers, secret management)
- Kubernetes resource management (limits, health probes)
- Terraform / AWS security group configuration
- Nginx security header hardening
- Multi-format configuration file editing (Dockerfile, YAML, HCL, nginx conf)
- Infrastructure security auditing

## Workspace

`/home/ga/workspace/platform_infra/`

| File | Issue |
|------|-------|
| `docker/Dockerfile` | Runs as root -- missing USER directive |
| `docker/docker-compose.yml` | Hardcoded database password and secret key |
| `kubernetes/deployment.yaml` | No resource limits; no health probes |
| `terraform/main.tf` | Overly permissive security group (0-65535 from 0.0.0.0/0) |
| `nginx/nginx.conf` | Missing security headers |

## Difficulty

**Very Hard** -- requires cross-domain infrastructure security knowledge and
the ability to edit multiple configuration file formats (Dockerfile, YAML, HCL,
nginx conf) correctly.

## Verification

The verifier checks whether each misconfiguration has been corrected.  Scoring
is based on the number of issues fixed (pass threshold: 60/100).
