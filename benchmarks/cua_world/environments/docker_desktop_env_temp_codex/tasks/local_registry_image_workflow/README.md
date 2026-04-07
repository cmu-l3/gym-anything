# local_registry_image_workflow

## Overview
**Difficulty**: Very Hard
**Domain**: Software QA / DevOps / CI-CD
**Occupation**: Software Quality Assurance Analysts ($910M GDP sector)

Setting up a local Docker registry and managing image versioning is a fundamental DevOps skill. This task tests the complete image lifecycle: building with proper semantic versioning, pushing to a local registry, and deploying via registry reference rather than build context.

## Professional Context
QA and DevOps teams use local registries for air-gapped environments, CI/CD pipelines, and staging environments where external network access is restricted. Proper image tagging conventions (semantic versioning, latest) are industry standard.

## Starting State
- `/home/ga/api-service/` — Python Flask API application with Dockerfile (no registry configured)
- No local registry running
- No compose file exists

## Goal
1. Start a local Docker registry (`registry:2`) on port 5000
2. Build the application and push to local registry with tags `v1.0.0` AND `latest`
3. Create `docker-compose.yml` using `image: localhost:5000/api-service:latest` (NOT build:)
4. Deploy the compose stack — API must respond on port 7080

## Verification Criteria (100 points)
- **Registry running on port 5000** (20 pts): `registry:2` container running, port 5000 accessible
- **v1.0.0 tag in registry** (20 pts): `localhost:5000/v2/api-service/tags/list` contains v1.0.0
- **latest tag in registry** (15 pts): `localhost:5000/v2/api-service/tags/list` contains latest
- **Compose uses registry image** (20 pts): docker-compose.yml has `image: localhost:5000/api-service` (not build:)
- **API service running and accessible** (25 pts): HTTP GET port 7080 returns 200

**Pass threshold**: 70 points
**Mandatory for pass**: registry running + v1.0.0 tag in registry + API accessible
