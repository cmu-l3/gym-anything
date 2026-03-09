# compose_production_hardening

## Overview
**Difficulty**: Very Hard
**Domain**: Software Development / DevOps
**Occupation**: Computer Network Architects ($649M GDP) / Software Developers ($18B GDP)

Moving a Docker Compose application from development to production requires adding production-grade reliability, observability, and security features. This task tests comprehensive understanding of Docker Compose production patterns.

## Professional Context
DevOps engineers and software developers must understand production hardening: health checks ensure containers are truly ready before traffic is routed; resource limits prevent runaway processes from affecting other workloads; restart policies ensure self-healing; network isolation follows security best practices (principle of least privilege). These are all standard production requirements.

## Starting State
- `/home/ga/webapp/docker-compose.yml` — Basic compose with 3 services (nginx + app + redis), no production features
- Services are functional but unprotected
- Flat networking (all services on default network)

## Goal
Modify `/home/ga/webapp/docker-compose.yml` (and any referenced Dockerfiles) to add:
1. **Health checks** for all 3 services (compose healthcheck: section or Dockerfile HEALTHCHECK)
2. **Resource limits** — memory AND cpu limits on all 3 services (deploy.resources.limits)
3. **Restart policies** — `restart: unless-stopped` or `restart: always` on all services
4. **Network isolation** — create `frontend` and `backend` networks; nginx connects to both; app connects to both; redis only on backend

The application must remain accessible at http://localhost:9080.

## Verification Criteria (100 points)
- **Health checks on all 3 services** (25 pts): All services have healthcheck defined (compose or Dockerfile)
- **Resource limits on all 3 services** (25 pts): All services have memory + cpu limits via deploy.resources
- **Restart policies on all 3 services** (20 pts): All services have restart: unless-stopped or restart: always
- **Network isolation** (20 pts): frontend and backend networks defined; redis ONLY on backend
- **App accessible** (10 pts): http://localhost:9080 returns HTTP 200

**Pass threshold**: 70 points
**Mandatory for pass**: health checks + resource limits + app accessible
