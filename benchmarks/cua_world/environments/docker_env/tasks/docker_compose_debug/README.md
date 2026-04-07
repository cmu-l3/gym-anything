# Task: Docker Compose Multi-Service Debugging

## Domain Context
**Role**: Software Developer / DevOps Engineer
**Occupation**: Software Developers (SOC 15-1252.00) — highest GDP-weighted occupation for Docker. "Standard for creating reproducible development environments and testing deployment artifacts."

## Task Overview

A 5-service e-commerce backend is completely broken. The developer must:

1. **Start** the application and observe failures
2. **Diagnose** each failing service — examine logs (`docker logs`), inspect config (`docker inspect`), check networking
3. **Fix** all 5 configuration bugs in `docker-compose.yml` and `nginx/nginx.conf`
4. **Verify** all services are running and the API responds through Nginx

## What Makes This Hard

- Agent is NOT told what the bugs are — must diagnose from logs and container failures
- 5 distinct bugs of different types (env var name, network reference, URL scheme, port mismatch, Python module path)
- Bugs are interdependent — some services fail because of services they depend on
- Must understand both Docker Compose networking AND Nginx upstream configuration
- Must verify the fix works end-to-end (not just that containers start)

## The 5 Bugs

| # | Location | Bug | Impact |
|---|----------|-----|--------|
| 1 | docker-compose.yml → db service | `POSTGRES_DATABASE` should be `POSTGRES_DB` | Database not initialized, API can't connect |
| 2 | docker-compose.yml → api service | References network `backend-net` which doesn't exist | API container fails to start |
| 3 | docker-compose.yml → api service | `REDIS_URL: redis:6379` should be `redis://cache:6379` | API can't connect to Redis |
| 4 | nginx/nginx.conf | Upstream port `3001` should be `3000` | Nginx can't proxy to API |
| 5 | docker-compose.yml → worker service | `command: python -m app.tasks` should be `python -m worker.tasks` | Worker crashes immediately |

## Success Criteria

| Criterion | Points |
|-----------|--------|
| acme-db running and healthy | 15 |
| acme-cache running and healthy | 10 |
| acme-api running and healthy | 20 |
| acme-nginx running | 15 |
| acme-worker running | 15 |
| API responds with products via nginx (GET /api/products → 200) | 25 |

**Pass threshold: 65 points**

## Verification Strategy

- `export_result.sh`: Checks `docker ps` for each service, curls the nginx endpoint
- `verifier.py`: Validates each service state and the HTTP response

## Starting State

Project is at `~/projects/ecommerce-app/` with broken `docker-compose.yml`
