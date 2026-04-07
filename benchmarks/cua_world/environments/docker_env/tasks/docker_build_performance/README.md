# Task: Docker Build Performance Optimization

## Domain Context
**Role**: QA Analyst / DevOps Engineer
**Occupation**: Software Quality Assurance Analysts (SOC 15-1253.00) — "Used to create and manage isolated test environments, containers, and virtual machines for compatibility testing."

## Task Overview

The AcmeCorp Analytics Service CI pipeline builds a Docker image that is > 1GB and takes over 5 minutes even for trivial code changes. The QA engineer must:

1. **Analyze** the existing Dockerfile's inefficiencies (bad layer order, wrong base image, no separation of dev/prod deps)
2. **Rewrite** the Dockerfile with proper optimizations
3. **Add** a `.dockerignore` file
4. **Rebuild** the optimized image tagged `acme-analytics:optimized`
5. **Verify** the image starts and the `/health` endpoint responds

## What Makes This Hard

- Must identify MULTIPLE problems and fix all of them to hit the size target
- Layer ordering optimization requires understanding Docker caching mechanics
- Must separate production from dev dependencies
- Must verify the app actually works after optimization (not just that it builds)
- Multi-stage builds require understanding of how to copy built artifacts

## Problems in the Original Dockerfile

| Problem | Impact |
|---------|--------|
| Full `python:3.11` image (700MB base) instead of `python:3.11-slim` | +500MB |
| `COPY . .` before `pip install` — destroys cache on every code change | Full pip reinstall each build |
| Dev dependencies installed in production image | +200MB of test tools |
| No `.dockerignore` — copies `__pycache__`, `.git`, `tests/`, venvs | +unnecessary files |
| Multiple separate `RUN apt-get` commands | Extra layers |

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Image size < 400MB | 30 |
| Second build (cached) completes in < 60 seconds | 25 |
| `.dockerignore` file exists with meaningful content | 15 |
| Dev dependencies not in production image | 15 |
| App starts and /health responds 200 | 15 |

**Pass threshold: 60 points**

## Verification Strategy

- `export_result.sh`: Gets image size, measures cached build time, checks `.dockerignore`, runs test container
- `verifier.py`: Validates all optimization criteria

## Technical Notes

- Use `python:3.11-slim` as base (or smaller)
- Use multi-stage builds to separate build and runtime stages
- Put `COPY requirements.txt` before `COPY . .`
- Use separate `requirements.txt` and `requirements-dev.txt`
- Production stage should only install from `requirements.txt`
