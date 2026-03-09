# multistage_dockerfile_optimization

## Overview
**Difficulty**: Very Hard
**Domain**: Software Development / DevOps
**Occupation**: Software Developers ($18B GDP sector)

A Node.js application has a bloated single-stage Dockerfile that installs all development dependencies into the final image. The agent must understand the build process, identify the cause of image bloat, and rewrite the Dockerfile using a multi-stage build to produce a production-ready image under 250 MB.

## Professional Context
Software developers routinely optimize Docker builds for CI/CD pipelines and production deployments. Large images increase deployment times, registry costs, and attack surface. Multi-stage builds are the industry-standard solution, separating build-time dependencies from runtime artifacts.

## Starting State
- `/home/ga/todo-app/` — Real Node.js application (Docker's getting-started app)
- `/home/ga/todo-app/Dockerfile` — Single-stage bloated Dockerfile (DO NOT rename/delete, rewrite it)
- `todo-app:original` — Already built reference image (~1GB+)

## Goal
Rewrite `/home/ga/todo-app/Dockerfile` as a multi-stage build and build the tag `todo-app:optimized`. The optimized image must be under 250 MB and the app must serve HTTP on port 3000.

## Verification Criteria (100 points)
- **Multi-stage Dockerfile present** (20 pts): Dockerfile contains at least 2 `FROM` statements (multi-stage pattern)
- **Optimized image exists** (15 pts): `todo-app:optimized` tag present in local images
- **Image size < 250 MB** (30 pts): Full credit <250MB; partial 10pts if 250-400MB; 0 if >400MB
- **Size reduction achieved** (20 pts): Optimized image is at least 50% smaller than original
- **App functional on port 3000** (15 pts): Running optimized container responds HTTP 200 on port 3000

**Pass threshold**: 70 points
**Mandatory for pass**: multi-stage + optimized image exists + size < 250MB

## Anti-Gaming
- Original image size recorded at setup time
- Dockerfile mtime checked against task start
- App functionality verified by HTTP check
