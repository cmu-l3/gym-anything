# broken_compose_diagnosis

## Overview
**Difficulty**: Very Hard
**Domain**: Computer Systems Engineering / DevOps
**Occupation**: Computer Systems Engineers/Architects ($4.2B GDP sector)

A three-service Docker Compose application has three realistic configuration bugs that prevent it from starting. The agent must diagnose and fix all bugs without being told what they are.

## Professional Context
Systems engineers and DevOps professionals routinely inherit broken deployment configurations. Debugging multi-service Docker Compose failures requires reading error output, understanding service networking, and knowing Docker Compose specification rules. This task tests all three.

## Starting State
- `/home/ga/app-debug/docker-compose.yml` — contains 3 intentional bugs
- `/home/ga/app-debug/flask/` — real Flask application code (correct, do not modify)
- `/home/ga/app-debug/nginx/nginx.conf` — nginx reverse proxy config (correct)

## Goal
Fix `docker-compose.yml` so that all three services (nginx, flask, db) start and run successfully. The application must be accessible at http://localhost:8080.

## The Three Bugs (for verifier reference — NOT shown to agent)
1. **Wrong DB hostname**: `MYSQL_HOST=localhost` should be `MYSQL_HOST=db`
2. **Missing network**: Flask service only joins `frontnet`, must also join `backnet` to reach the database
3. **Undeclared volume**: `db_data` volume is referenced in the db service but the top-level `volumes:` section is absent

## Verification Criteria (100 points)
- **All 3 services running** (30 pts): `docker compose ps` shows flask, nginx, db all running
- **Nginx accessible** (25 pts): HTTP GET http://localhost:8080 returns 200
- **Flask reaches DB** (25 pts): Flask container's MYSQL_HOST env var is `db` (not localhost)
- **Flask on backnet** (10 pts): Flask container is member of the backnet network
- **Volumes section present** (10 pts): docker-compose.yml contains top-level `volumes:` key

**Pass threshold**: 70 points
**Mandatory**: All 3 services must be running for pass

## Anti-Gaming
- Setup records initial container count; verifier checks NEW containers were started
- Timestamp validation: compose must be modified after task start
